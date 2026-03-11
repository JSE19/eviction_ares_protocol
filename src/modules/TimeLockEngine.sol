//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITimeLock} from "../interfaces/ITimeLock.sol";
import {IProposal} from "../interfaces/IProposal.sol";

contract TimeLockEngine is ITimeLock {
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant MAX_DELAY = 21 days;
    uint256 public spendingWindow = 2 days;
    uint256 public maxTokenPerWindow = 5 ether;
    uint256 public minDelay;
    uint256 public gracePeriod;

    address public adminAddress;
    address public proposalContractAddress;
    address public guardianAddress;

    mapping(uint256 => uint256) public nonces;

    mapping(bytes32 => QueuedOp) public queue;

    uint256 public windowStart;
    uint256 public ethSpentThisWindow;

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, NotAuthorized());
        _;
    }

    modifier onlyProposalContract() {
        require(msg.sender == proposalContractAddress, NotAuthorized());
        _;
    }
    modifier onlyGuardianOrProposalManager() {
        if (msg.sender != guardianAddress && msg.sender != proposalContractAddress) {
            revert NotAuthorized();
        }
        _;
    }

    constructor(uint256 _minDelay, uint256 _gracePeriod, address _proposalContractAddress, address _guardianAddress) {
        require(_minDelay >= MIN_DELAY && _minDelay <= MAX_DELAY, DelayTooLongOrShort());

        require(_gracePeriod > 0, ZeroGracePeriod());

        require(_proposalContractAddress != address(0), ZeroAddress());

        require(_guardianAddress != address(0), ZeroAddress());

        minDelay = _minDelay;
        gracePeriod = _gracePeriod;
        proposalContractAddress = _proposalContractAddress;
        guardianAddress = _guardianAddress;
        adminAddress = msg.sender;
        windowStart = block.timestamp;
    }

    function schedule(uint256 proposalId, IProposal.Action calldata action)
        external
        override
        onlyProposalContract
        returns (bytes32)
    {
        uint256 nonce = nonces[proposalId] + 1;

        bytes32 actionHash = keccak256(abi.encode(action));

        bytes32 operationId = keccak256(abi.encode(proposalId, actionHash, nonce));

        uint256 executionTime = block.timestamp + minDelay;
        uint256 expiryTime = executionTime + gracePeriod;

        queue[operationId] = QueuedOp({
            proposalId: proposalId,
            actionHash: actionHash,
            executionTime: executionTime,
            expiryTime: expiryTime,
            status: OperationStatus.PENDING,
            nonce: nonce
        });

        emit OperationScheduled(operationId, proposalId, executionTime, expiryTime);

        return operationId;
    }

    function cancel(bytes32 operationId) external override onlyGuardianOrProposalManager {
        QueuedOp storage op = queue[operationId];
        require(op.status != OperationStatus.UNSET, OperationNotReady(operationId));
        require(op.status != OperationStatus.CANCELLED, OperationAlreadyCancelled(operationId));
        require(op.status != OperationStatus.DONE, OperationAlreadyDone(operationId));

        op.status = OperationStatus.CANCELLED;

        emit OperationCancelled(operationId, op.proposalId, msg.sender);
    }

    function execute(bytes32 operationId, IProposal.Action calldata action)
        external
        override
        onlyGuardianOrProposalManager
    {
        QueuedOp storage op = queue[operationId];

        require(op.status != OperationStatus.UNSET, OperationNotReady(operationId));
        require(op.status != OperationStatus.CANCELLED, OperationAlreadyCancelled(operationId));
        require(op.status != OperationStatus.DONE, OperationAlreadyDone(operationId));

        require(block.timestamp >= op.executionTime, OperationNotReady(operationId));

        require(block.timestamp <= op.expiryTime, OperationExpired(operationId));

        require(keccak256(abi.encode(action)) == op.actionHash, InvalidAction());

        // Mark as done before execution to prevent reentrancy
        op.status = OperationStatus.DONE;

        _executeAction(action);

        emit OperationExecuted(operationId, op.proposalId);
    }

    function _executeAction(IProposal.Action calldata action) internal {
        IProposal.actionType t = action.actionType;

        if (t == IProposal.actionType.TRANSFER) {
            _executeTransfer(action);
        } else if (t == IProposal.actionType.CALL) {
            _executeCall(action);
        } else if (t == IProposal.actionType.UPGRADE) {
            _executeUpgrade(action);
        }
    }

    function _executeTransfer(IProposal.Action calldata action) internal {
        if (action.token == address(0)) {
            _checkAndUpdateSpendingLimit(action.amount);
            (bool ok,) = action.target.call{value: action.amount}("");
            require(ok, "TimelockEngine: ETH transfer failed");
        } else {
            (bool ok, bytes memory ret) =
                action.token.call(abi.encodeWithSignature("transfer(address,uint256)", action.target, action.amount));
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TimelockEngine: ERC20 transfer failed");
        }
    }

    function _executeUpgrade(IProposal.Action calldata action) internal {
        (bool ok, bytes memory returnData) = action.target.call(action.data);
        if (!ok) {
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
            revert("TimelockEngine: upgrade failed");
        }
    }

    function _executeCall(IProposal.Action calldata action) internal {
        (bool ok, bytes memory returnData) = action.target.call{value: action.amount}(action.data);
        if (!ok) {
            // Bubble up the revert reason
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
            revert("TimelockEngine: call failed");
        }
    }

    function _checkAndUpdateSpendingLimit(uint256 amount) internal {
        // Reset window if it has elapsed
        if (block.timestamp >= windowStart + spendingWindow) {
            windowStart = block.timestamp;
            ethSpentThisWindow = 0;
        }

        uint256 newTotal = ethSpentThisWindow + amount;
        if (newTotal > maxTokenPerWindow) {
            revert SpendingLimitExceeded();
        }

        ethSpentThisWindow = newTotal;
    }

    function getOperation(bytes32 operationId) external view override returns (QueuedOp memory) {
        if (queue[operationId].status == OperationStatus.UNSET) {
            revert OperationNotFound(operationId);
        }
        return queue[operationId];
    }

    function getOperationStatus(
        bytes32 operationId
    ) external view override returns (OperationStatus) {
        return queue[operationId].status;
    }
}

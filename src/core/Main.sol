//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IProposal} from "../interfaces/IProposal.sol";
import {ITimeLock} from "../interfaces/ITimeLock.sol";
import {IAuthorization} from "../interfaces/IAuthorization.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";

contract Main {
    uint256 public constant PROPOSAL_DEPOSIT = 0.1 ether;
    address public constant SLASH_RECIPIENT = address(0xdead);

    IProposal public immutable proposal;
    ITimeLock public immutable timeLock;
    IAuthorization public immutable authorization;
    IRewardDistributor public immutable rewardDistributor;

    address public admin;
    address public guardian;

    mapping(uint256 => address) public proposalDepositor;

    mapping(uint256 => uint256) public proposalDepositAmount;

    mapping(uint256 => bytes32) public proposalOperationId;

    event Proposed(uint256 indexed proposalId, address indexed proposer);
    event Queued(uint256 indexed proposalId, bytes32 indexed operationId);
    event Executed(uint256 indexed proposalId);
    event Cancelled(uint256 indexed proposalId, address indexed cancelledBy, bool depositSlashed);
    event DepositRefunded(uint256 indexed proposalId, address indexed proposer, uint256 amount);
    event DepositSlashed(uint256 indexed proposalId, address indexed proposer, uint256 amount);

    error InsufficientDeposit(uint256 sent, uint256 required);
    error DepositRefundFailed(uint256 proposalId);
    error SameBlockProposal(uint256 proposalId);
    error NotGuardian(address caller);
    error NotAdmin(address caller);
    error NoDepositOnRecord(uint256 proposalId);
    error AddressZero();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin(msg.sender);
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian(msg.sender);
        _;
    }

    constructor(
        address _proposalContract,
        address _timelockContract,
        address _authorizationContract,
        address _rewardDistributorContract,
        address _guardianAddress
    ) {
        require(_proposalContract != address(0), "TreasuryCore: zero proposalManager");
        require(_timelockContract != address(0), "TreasuryCore: zero timelockEngine");
        require(_authorizationContract != address(0), "TreasuryCore: zero authLayer");
        require(_rewardDistributorContract != address(0), "TreasuryCore: zero rewardDistributor");
        require(_guardianAddress != address(0), "TreasuryCore: zero guardian");

        proposal = IProposal(_proposalContract);
        timeLock = ITimeLock(_timelockContract);
        authorization = IAuthorization(_authorizationContract);
        rewardDistributor = IRewardDistributor(_rewardDistributorContract);
        guardian = _guardianAddress;
        admin = msg.sender;
    }

    function propose(IProposal.Action calldata action, bytes32 descriptionHash)
        external
        payable
        returns (uint256 proposalId)
    {
        if (msg.value < PROPOSAL_DEPOSIT) {
            revert InsufficientDeposit(msg.value, PROPOSAL_DEPOSIT);
        }

        proposalId = proposal.createProposal(action, descriptionHash);

        proposalDepositor[proposalId] = msg.sender;
        proposalDepositAmount[proposalId] = msg.value;

        emit Proposed(proposalId, msg.sender);
    }

    function queue(uint256 proposalId, IProposal.Action calldata action) external {
        uint256 snapshotBlock = proposal.proposalSnapshotBlock(proposalId);
        if (snapshotBlock >= block.number) {
            revert SameBlockProposal(proposalId);
        }

        proposal.queueProp(proposalId);

        bytes32 operationId = timeLock.schedule(proposalId, action);

        proposalOperationId[proposalId] = operationId;

        emit Queued(proposalId, operationId);
    }

    function execute(uint256 proposalId, IProposal.Action calldata action) external {
        bytes32 operationId = proposalOperationId[proposalId];

        timeLock.execute(operationId, action);

        // Refund proposer deposit on success
        _refundDeposit(proposalId);

        emit Executed(proposalId);
    }

    function cancel(uint256 proposalId, string calldata reason) external {
        bool isGuardian = (msg.sender == guardian);
        bool isProposer = (msg.sender == proposalDepositor[proposalId]);

        require(isGuardian || isProposer, "TreasuryCore: not authorised to cancel");

        proposal.cancelProp(proposalId, reason);

        bytes32 operationId = proposalOperationId[proposalId];
        if (operationId != bytes32(0)) {
            // Only cancel if still PENDING in the timelock
            ITimeLock.OperationStatus status = timeLock.getOperationStatus(operationId);

            if (status == ITimeLock.OperationStatus.PENDING) {
                timeLock.cancel(operationId);
            }
        }

        if (isGuardian && !isProposer) {
            _slashDeposit(proposalId);
            emit Cancelled(proposalId, msg.sender, true);
        } else {
            _refundDeposit(proposalId);
            emit Cancelled(proposalId, msg.sender, false);
        }
    }

    function createRewardRound(bytes32 _root, address _token, uint256 _totalAmount)
        external
        onlyAdmin
        returns (uint256 roundId)
    {
        roundId = rewardDistributor.createRound(_root, _token, _totalAmount);
    }

    function updateRewardRoot(uint256 _roundId, bytes32 _newRoot) external onlyAdmin {
        rewardDistributor.updateRoot(_roundId, _newRoot);
    }

    function setGuardian(address _newGuardian) external onlyAdmin {
        require(_newGuardian != address(0), AddressZero());
        guardian = _newGuardian;
    }

    function _refundDeposit(uint256 proposalId) internal {
        address depositor = proposalDepositor[proposalId];
        uint256 amount = proposalDepositAmount[proposalId];

        if (depositor == address(0) || amount == 0) return;

        // Clear before transfer (CEI)
        proposalDepositAmount[proposalId] = 0;

        (bool ok,) = depositor.call{value: amount}("");
        if (!ok) revert DepositRefundFailed(proposalId);

        emit DepositRefunded(proposalId, depositor, amount);
    }

    function _slashDeposit(uint256 proposalId) internal {
        address depositor = proposalDepositor[proposalId];
        uint256 amount = proposalDepositAmount[proposalId];

        if (depositor == address(0) || amount == 0) return;

        // Clear before transfer (CEI)
        proposalDepositAmount[proposalId] = 0;

        (bool ok,) = SLASH_RECIPIENT.call{value: amount}("");
        require(ok, "TreasuryCore: slash transfer failed");

        emit DepositSlashed(proposalId, depositor, amount);
    }

    receive() external payable {}
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IProposal} from "./IProposal.sol";

interface ITimeLock {
    enum OperationStatus {
        UNSET,
        PENDING,
        DONE,
        CANCELLED
    }

    struct QueuedOp {
        uint256 proposalId;
        bytes32 actionHash;
        uint256 executionTime;
        uint256 expiryTime;
        OperationStatus status;
        uint256 nonce;
    }

    event OperationScheduled(
        bytes32 indexed operationId, uint256 indexed proposalId, uint256 executionTime, uint256 expiryTime
    );
    event OperationExecuted(bytes32 indexed operationId, uint256 indexed proposalId);
    event OperationCancelled(bytes32 indexed operationId, uint256 indexed proposalId, address cancelledBy);
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);

    error OperationNotFound(bytes32 operationId);
    error OperationNotReady(bytes32 operationId);
    error OperationExpired(bytes32 operationId);
    error OperationAlreadyCancelled(bytes32 operationId);
    error OperationAlreadyDone(bytes32 operationId);
    
    error NotAuthorized();
    error DelayTooLongOrShort();
    error ZeroGracePeriod();
    error ZeroAddress();
    error InvalidAction();
    error SpendingLimitExceeded();

    function schedule(uint256 proposalId, IProposal.Action calldata action) external returns (bytes32);

    function execute(bytes32 operationId, IProposal.Action calldata action) external;

    function cancel(bytes32 operationId) external;

    function getOperation(bytes32 operationId) external view returns (QueuedOp memory);
}

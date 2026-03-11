//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProposal {
    enum propStat {
        PENDING,
        APPROVED,
        QUEUED,
        EXECUTED,
        CANCELLED
    }

    enum actionType {
        TRANSFER,
        CALL,
        UPGRADE
    }

    struct Action {
        actionType actionType;
        address token;
        address target;
        uint256 amount;
        bytes data;
    }

    struct Proposal {
        uint256 id;
        address proposer;
        Action action;
        propStat status;
        uint256 approvalCount;
        uint256 createdAt;
        uint256 queuedAt;
        bytes32 descriptionHash;
    }

    event ProposalCreated(
        address indexed proposer,
        uint256 indexed proposalId,
        actionType actionType,
        address target,
        uint256 amount,
        bytes32 descriptionHash
    );

    event ProposalApproved(address indexed signer, uint256 indexed proposalId, uint256 newApprovalCount);

    event ProposalReadyToQueue(uint256 indexed proposalId);

    event ProposalExecuted(uint256 indexed proposalId);

    event ProposalCancelled(uint256 indexed proposalId, address indexed canceledBy, string reason);

    error ProposalNotFound(uint256 proposalId);
    error AlreadyApproved();
    error ThresholdNotMet();
    error NotAuthorizedProposer();
    error NotAdmin();
    error StatusNotPending();
    error InvalidAction();
    error AmountMustBeGreaterThanZero();
    error NotAuthorizer();
    error ThresholdShouldBeGreaterThanZero();
    error AddressZero();
    error NotTimeLock();
    error ProposalExpired();

    error ProposalExcecuted();

    //Function to create new proposal
    function createProposal(Action memory action, bytes32 descriptionHash) external returns (uint256);

    //Function to approve a proposal
    function approveProp(uint256 proposalId, address signer) external;

    function queueProp(uint256 proposalId) external;

    function executeProp(uint256 proposalId) external;

    function cancelProp(uint256 proposalId, string memory reason) external;

    function getProps(uint256 proposalId) external view returns (Proposal memory);

    function proposalSnapshotBlock(uint256 proposalId) external view returns (uint256);
}

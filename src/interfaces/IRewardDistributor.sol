//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewardDistributor {
    struct Round {
        bytes32 root;
        address token;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 createdAt;
        bool active;
    }

    event RoundCreated(uint256 indexed roundId, bytes32 root, address indexed token, uint256 totalAmount);

    event RootUpdated(uint256 indexed roundId, bytes32 oldRoot, bytes32 newRoot);

    event RewardClaimed(uint256 indexed roundId, address indexed claimant, uint256 amount);
    event RoundClosed(uint256 indexed roundId);

    error AlreadyClaimed(uint256 roundId, address claimant);
    error InvalidProof(uint256 roundId, address claimant);
    error RoundNotActive(uint256 roundId);
    error RoundNotFound(uint256 roundId);
    error ZeroAmount();
    error ZeroRoot();
    error ZeroToken();
    error InsufficientRoundBalance(uint256 available, uint256 requested);
    error NotAuthorized(address caller);
    error NothingToClaim();

    function createRound(bytes32 root, address token, uint256 totalAmount) external returns (uint256 roundId);

    function updateRoot(uint256 roundId, bytes32 newRoot) external;

    function claim(uint256 roundId, uint256 amount, bytes32[] calldata proof) external;

    function closeRound(uint256 roundId) external;

    function getRound(uint256 roundId) external view returns (Round memory);

    function hasClaimed(uint256 roundId, address claimant) external view returns (bool);
}

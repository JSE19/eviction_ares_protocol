//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";

import {MerkleLib} from "../libraries/MerkleLib.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardDistributor is IRewardDistributor {
    using SafeERC20 for IERC20;
    address public admin;

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAuthorized(msg.sender);
        _;
    }

    uint256 private roundCount;
    mapping(uint256 => Round) rounds;
    mapping(uint256 => mapping(address => bool)) private claimed;

    constructor() {
        admin = msg.sender;
    }

    function recoverUnclaimed(uint256 _roundId, address _recipient) external onlyAdmin {
        Round storage round = rounds[_roundId];
        if (round.createdAt == 0) revert RoundNotFound(_roundId);
        if (round.active) revert RoundNotActive(_roundId);

        uint256 remaining = round.totalAmount - round.claimedAmount;
        require(remaining > 0, NothingToClaim());

        round.claimedAmount = round.totalAmount;

        IERC20(round.token).safeTransfer(_recipient, remaining);
    }

    function createRound(bytes32 _root, address _token, uint256 _totalAmount)
        external
        override
        onlyAdmin
        returns (uint256 roundId)
    {
        if (_root == bytes32(0)) revert ZeroRoot();
        if (_token == address(0)) revert ZeroToken();
        if (_totalAmount == 0) revert ZeroAmount();

        unchecked {
            roundId = ++roundCount;
        }

        rounds[roundId] = Round({
            root: _root,
            token: _token,
            totalAmount: _totalAmount,
            claimedAmount: 0,
            createdAt: block.timestamp,
            active: true
        });

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);

        emit RoundCreated(roundId, _root, _token, _totalAmount);
    }

    function updateRoot(uint256 _roundId, bytes32 _newRoot) external override onlyAdmin {
        if (_newRoot == bytes32(0)) revert ZeroRoot();

        Round storage round = rounds[_roundId];
        if (round.createdAt == 0) revert RoundNotFound(_roundId);
        if (!round.active) revert RoundNotActive(_roundId);

        bytes32 oldRoot = round.root;
        round.root = _newRoot;

        emit RootUpdated(_roundId, oldRoot, _newRoot);
    }

    function claim(uint256 _roundId, uint256 _amount, bytes32[] calldata _proof) external override {
        Round storage round = rounds[_roundId];
        if (round.createdAt == 0) revert RoundNotFound(_roundId);
        if (!round.active) revert RoundNotActive(_roundId);

        if (_amount == 0) revert ZeroAmount();

        if (claimed[_roundId][msg.sender]) revert AlreadyClaimed(_roundId, msg.sender);

        MerkleLib.verifyOrRevert(round.root, _proof, msg.sender, _amount);

        uint256 remaining = round.totalAmount - round.claimedAmount;
        if (_amount > remaining) {
            revert InsufficientRoundBalance(remaining, _amount);
        }

        claimed[_roundId][msg.sender] = true;
        round.claimedAmount += _amount;

        emit RewardClaimed(_roundId, msg.sender, _amount);

        IERC20(round.token).safeTransfer(msg.sender, _amount);
    }

    function closeRound(uint256 _roundId) external override onlyAdmin {
        Round storage round = rounds[_roundId];
        if (round.createdAt == 0) revert RoundNotFound(_roundId);
        if (!round.active) revert RoundNotActive(_roundId);

        round.active = false;
        emit RoundClosed(_roundId);
    }

    function getRound(uint256 _roundId) external view override returns (Round memory) {
        if (rounds[_roundId].createdAt == 0) revert RoundNotFound(_roundId);
        return rounds[_roundId];
    }

    function hasClaimed(uint256 _roundId, address _claimant) external view override returns (bool) {
        return claimed[_roundId][_claimant];
    }
}

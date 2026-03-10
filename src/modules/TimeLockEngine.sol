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
}

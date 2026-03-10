//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IProposal} from "../interfaces/IProposal.sol";

contract Proposal is IProposal {
    
    uint256 public proposalCount;
    uint256 public approvalThreshold;
    uint constant PROPOSAL_EXPIRY = 7 days;

    address public authorizationAddress;
    address public timelockAddress;
    address public guardianAddress;
    address public adminAddress;


    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public approvals;

    modifier onlyAdmin {
        require(msg.sender == adminAddress, NotAdmin());
        _;
    }

    modifier onlyAuthorizer {
        require(msg.sender == authorizationAddress, NotAuthorizer());
        _;
    }

    modifier onlyTimeLock {
        require(msg.sender == timelockAddress, NotTimeLock());
        _;
    }

    modifier proposalExists(uint256 _proposalId) {
        require(proposals[_proposalId].createdAt != 0, ProposalNotFound(_proposalId));
        _;
    }

    constructor(uint256 _approvalThreshold, address _authorizationAddress,address _guardianAddress, address _timelockAddress) {
        require(_approvalThreshold > 0, ThresholdShouldBeGreaterThanZero());

        require(_authorizationAddress != address(0) && 
        _guardianAddress != address(0) && _timelockAddress != address(0), AddressZero());


        approvalThreshold = _approvalThreshold;
        authorizationAddress = _authorizationAddress;
        guardianAddress = _guardianAddress;
        timelockAddress = _timelockAddress;
        adminAddress = msg.sender;
        
    }

    function setGuardian(address _newGuardian) external onlyAdmin {
        require(_newGuardian != address(0), AddressZero());
        guardianAddress = _newGuardian;
    }


    function createProposal(Action calldata action, bytes32 descriptionHash) external override returns (uint256) {

        _validateAction(action);

        proposalCount += 1;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            action: action,
            status: propStat.PENDING,
            approvalCount: 0,
            createdAt: block.timestamp,
            queuedAt: 0,
            descriptionHash: descriptionHash
        });

        emit ProposalCreated(msg.sender, proposalCount, action.actionType, action.target, action.amount, descriptionHash);
        return proposalCount;
    }

    function approveProp(uint256 _proposalId, address _signer) external override onlyAuthorizer proposalExists(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];

        // require(proposal.id != 0, ProposalNotFound(_proposalId));

        require(approvals[_proposalId][_signer] == false, AlreadyApproved());

        require(proposal.status == propStat.PENDING, StatusNotPending());


        approvals[_proposalId][_signer] = true;
        proposal.approvalCount += 1;

        emit ProposalApproved(_signer, _proposalId, proposal.approvalCount);

        if(proposal.approvalCount >= approvalThreshold) {
            proposal.status = propStat.APPROVED;
            emit ProposalReadyToQueue(_proposalId);
        }
    }

    function queueProp(uint256 _proposalId) external override proposalExists(_proposalId)  {
        Proposal storage proposal = proposals[_proposalId];

        require(proposal.status == propStat.APPROVED, ThresholdNotMet());

        if (block.timestamp > proposal.createdAt + PROPOSAL_EXPIRY) {
            // Auto-cancel instead of silently failing
            proposal.status = propStat.CANCELLED;
            emit ProposalCancelled(_proposalId, msg.sender, "expired before queuing");
            return;
        }

        proposal.status = propStat.QUEUED;
        proposal.queuedAt = block.timestamp;

        emit ProposalExecuted(_proposalId);
    }

    function executeProp(uint256 _proposalId)  external override onlyTimeLock proposalExists(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];

        require(proposal.status == propStat.QUEUED, StatusNotPending());

        if (block.timestamp > proposal.queuedAt + PROPOSAL_EXPIRY) {
            
            proposal.status = propStat.CANCELLED;
            emit ProposalCancelled(_proposalId, msg.sender, "expired before execution");
            return;
        }

        proposal.status = propStat.EXECUTED;

        emit ProposalExecuted(_proposalId);
        
    }

    function cancelProp(uint256 _proposalId, string memory reason) external override proposalExists(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];

        require(proposal.status == propStat.PENDING || proposal.status == propStat.APPROVED, StatusNotPending());

        require(msg.sender == proposal.proposer || msg.sender == adminAddress, NotAuthorizedProposer());

        

        bool isGuardian = msg.sender == guardianAddress;
        bool isProposerCancellingEarly = (
            msg.sender == proposal.proposer &&
            (proposal.status == propStat.PENDING ||
             proposal.status == propStat.APPROVED)
        );

        require(isGuardian || isProposerCancellingEarly, NotAuthorizedProposer());

        proposal.status = propStat.CANCELLED;

        emit ProposalCancelled(_proposalId, msg.sender, reason);
        
    }

    function getProps(uint256 _proposalId)  external view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    function _validateAction(Action memory action) internal pure {
        require(action.target != address(0), InvalidAction());
        
        require(action.token != address(0), InvalidAction());

        if (action.actionType == actionType.TRANSFER) {
            
            require(action.amount > 0, AmountMustBeGreaterThanZero());

            require(action.data.length == 0, InvalidAction());
            
        }

        if (action.actionType == actionType.UPGRADE) {
           
        
            if (action.amount != 0) revert InvalidAction();
            if (action.data.length != 0) revert InvalidAction();
            
            if (action.token != address(0)) revert InvalidAction();
        }

      
    }


    

}
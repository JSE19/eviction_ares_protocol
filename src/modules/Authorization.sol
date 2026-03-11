//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAuthorization} from "../interfaces/IAuthorization.sol";
import {IProposal} from "../interfaces/IProposal.sol";
import {SignatureLib} from "../libraries/SignatureLib.sol";

contract Authorization is IAuthorization{


    bytes32 private domainSeparator_;
    uint256 private chainId;

    IProposal public proposalContract;

    address public admin;

    mapping(address => bool) private authorizedSigners;
    mapping(address => uint256) private nonces;

    modifier onlyAdmin() {
        require(msg.sender == admin, NotAdmin());
        _;
    }

    constructor(address _proposalContract, address[] memory initialSigners ) {
        require(_proposalContract != address(0), ZeroAddress());
        require(initialSigners.length > 0, ZeroSigners());

        proposalContract = IProposal(_proposalContract);

        admin = msg.sender;

        chainId = block.chainid;
        domainSeparator_ = SignatureLib.buildDomainSeparator(
            "ARES Treasury",
            "1",
            block.chainid,
            address(this)
        )    ;



        for (uint256 i = 0; i < initialSigners.length; i++) {
            require(initialSigners[i] != address(0), ZeroAddress());
            authorizedSigners[initialSigners[i]] = true;
            emit SignerAdded(initialSigners[i]);
        }
    }

    function verifyAndApprove(uint256 _proposalId, bytes32 _actionHash,uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external override {
        _verifyFull(msg.sender,_proposalId, _actionHash, _deadline, _v, _r, _s);
    }

    function verifyAndApproveFor(
        address _signer,
        uint256 _proposalId,
        bytes32 _actionHash,
        uint256 _deadline,
        uint8   _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        _verifyFull(_signer, _proposalId, _actionHash, _deadline, _v, _r, _s);
    }


    function _verifyFull(
        address _signer,
        uint256 _proposalId,
        bytes32 _actionHash,
        uint256 _deadline,
        uint8   _v,
        bytes32 _r,
        bytes32 _s
    ) internal {

        uint256 currentNonce = nonces[_signer];

        
        address recovered = SignatureLib.verifyApproval(
            domainSeparator_,
            _proposalId,
            _actionHash,
            currentNonce,
            _deadline,
            _v, _r, _s
        );

        
        if (recovered != _signer) revert InvalidSignature();

       
        if (!authorizedSigners[recovered]) revert UnauthorisedSigner(recovered);

        
        nonces[_signer] = currentNonce + 1;

       
        emit ApprovalVerified(_signer,_proposalId, currentNonce);

       
        proposalContract.approveProp(_proposalId, _signer);
    }

   function addSigner(address _signer) external override onlyAdmin{
    require(_signer != address(0), ZeroAddress());
    require(!authorizedSigners[_signer], AlreadyASigner());

    authorizedSigners[_signer] = true;
    emit SignerAdded(_signer);
   }

   function removeSigner(address _signer) external override onlyAdmin {
        require(authorizedSigners[_signer], NotASigner());
        authorizedSigners[_signer] = false;
        emit SignerRemoved(_signer);
    }

    function isSigner(address _signer) external view override returns (bool) {
        return authorizedSigners[_signer];
    }

    function getNonce(address _signer) external view override returns (uint256) {
        return nonces[_signer];
    }
    
    function domainSeparator() external view override returns (bytes32) {
        return domainSeparator_;
    }


}
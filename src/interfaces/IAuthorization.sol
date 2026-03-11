//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAuthorization {
    struct ApprovalMessage {
        uint256 proposalId;
        bytes32 actionHash;
        uint256 nonce;
        uint256 deadline;
    }

    event ApprovalVerified(
        address indexed signer,
        uint256 indexed proposalId,
        uint256 nonce 
    );

    event SignerAdded(address indexed signer);

    event SignerRemoved(address indexed signer);

    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    error InvalidSignature();
    error SignatureExpired(uint256 deadline, uint256 currentTime);
    error SignatureAlreadyUsed(address signer, uint256 nonce);
    error UnauthorisedSigner(address signer);
    error InvalidNonce(address signer, uint256 provided, uint256 expected);
    error MalleableSignature(bytes32 s);
    error NotAdmin();
    error ZeroSigners();
    error InvalidVValue(uint8 v);
    error ZeroAddress();
    error AlreadyASigner();
    error NotASigner();

    function verifyAndApprove(uint256 proposalId, bytes32 actionHash,uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    function addSigner(address signer) external;

    function removeSigner(address signer) external; 

    function isSigner(address signer) external view returns (bool);

    function getNonce(address signer) external view returns (uint256);
    
    //Returns the EIP-712 domain separator for this contract.
    ///         Useful for off-chain signature construction and debugging.
    function domainSeparator() external view returns (bytes32);
}

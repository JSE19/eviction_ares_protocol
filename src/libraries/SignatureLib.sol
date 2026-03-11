//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library SignatureLib {
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant APPROVAL_TYPEHASH =
        keccak256("ApprovalMessage(uint256 proposalId,bytes32 actionHash,uint256 nonce,uint256 deadline)");

    bytes32 internal constant HALF_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    error SL_InvalidSignature();
    error SL_SignatureExpired(uint256 deadline, uint256 currentTime);
    error SL_MalleableSignature(bytes32 s);
    error SL_InvalidVValue(uint8 v);

    function buildDomainSeparator(
        string memory _name,
        string memory _version,
        uint256 _chainId,
        address _verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(_name)), keccak256(bytes(_version)), _chainId, _verifyingContract
            )
        );
    }

    function hashApprovalMessage(uint256 proposalId, bytes32 actionHash, uint256 nonce, uint256 deadline)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(APPROVAL_TYPEHASH, proposalId, actionHash, nonce, deadline));
    }

    function buildDigest(bytes32 _domainSeparator, bytes32 _structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator, _structHash));
    }

    function recover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) internal pure returns (address signer) {
        if (s > HALF_ORDER) revert SL_MalleableSignature(s);
        if (v != 27 && v != 28) revert SL_InvalidVValue(v);
        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert SL_InvalidSignature();
    }

    function verifyApproval(
        bytes32 _domainSeparator,
        uint256 _proposalId,
        bytes32 _actionHash,
        uint256 _nonce,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal view returns (address signer) {
        if (block.timestamp > _deadline) revert SL_SignatureExpired(_deadline, block.timestamp);

        bytes32 structHash = hashApprovalMessage(_proposalId, _actionHash, _nonce, _deadline);
        bytes32 digest = buildDigest(_domainSeparator, structHash);

        signer = recover(digest, _v, _r, _s);

        if (signer == address(0)) revert SL_InvalidSignature();
        return signer;
    }
}

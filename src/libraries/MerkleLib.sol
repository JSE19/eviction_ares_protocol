//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library MerkleLib {
    error ML_InvalidProof();
    error ML_EmptyProof();
    error ML_ZeroRoot();

    function hashLeaf(
        address recipient,
        uint256 amount
    ) internal pure returns(bytes32 leaf){
        leaf = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(recipient, amount))
        ));
    }

    function verify(
        bytes32   _root,
        bytes32[] calldata _proof,
        address   _recipient,
        uint256   _amount
    ) internal pure returns (bool valid) {

        if (_root == bytes32(0)) revert ML_ZeroRoot();

       
        bytes32 computed = hashLeaf(_recipient, _amount);

        
        uint256 len = _proof.length;
        for (uint256 i = 0; i < len; ) {
            computed = _combineSorted(computed, _proof[i]);
            unchecked { i++; }
        }

       
        valid = (computed == _root);
    }

    function verifyOrRevert(
        bytes32   root,
        bytes32[] calldata proof,
        address   recipient,
        uint256   amount
    ) internal pure {
        if (!verify(root, proof, recipient, amount)) revert ML_InvalidProof();
    }


    function computeRoot(
        bytes32[] memory _leaves
    ) internal pure returns (bytes32 root) {
        require(_leaves.length > 0, "MerkleLib: empty leaves");

        uint256 len = _leaves.length;

       
        if (len == 1) return _leaves[0];

        
        while (len > 1) {
            uint256 newLen = (len + 1) / 2; 
            for (uint256 i = 0; i < newLen; ) {
                uint256 left  = i * 2;
                uint256 right = left + 1;
                
                _leaves[i] = _combineSorted(
                    _leaves[left],
                    right < len ? _leaves[right] : _leaves[left]
                );
                unchecked { i++; }
            }
            len = newLen;
        }

        root = _leaves[0];
    }

    function _combineSorted(
        bytes32 a,
        bytes32 b
    ) private pure returns (bytes32 combined) {
        
        if (a <= b) {
            combined = keccak256(abi.encodePacked(a, b));
        } else {
            combined = keccak256(abi.encodePacked(b, a));
        }
    }

}

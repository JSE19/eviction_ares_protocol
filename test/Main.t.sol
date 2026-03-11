// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Proposal} from "../src/modules/Proposal.sol";
import {TimeLockEngine} from "../src/modules/TimeLockEngine.sol";
import {Authorization} from "../src/modules/Authorization.sol";
import {RewardDistributor} from "../src/modules/RewardDisttributor.sol";
import {Main} from "../src/core/Main.sol";
import {IProposal} from "../src/interfaces/IProposal.sol";
import {ITimeLock} from "../src/interfaces/ITimeLock.sol";
import {MerkleLib} from "../src/libraries/MerkleLib.sol";
import {SignatureLib} from "../src/libraries/SignatureLib.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Minimal ERC-20 for testing
// ─────────────────────────────────────────────────────────────────────────────

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// Reentrant token — calls back into distributor on transfer

contract ReentrantToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    RewardDistributor public distributor;
    uint256 public roundId;
    uint256 public claimAmount;
    bytes32[] public proof;
    bool public attacked;

    function setup(address _distributor, uint256 _roundId, uint256 _amount) external {
        distributor = RewardDistributor(_distributor);
        roundId = _roundId;
        claimAmount = _amount;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    // Called when tokens are sent to recipient — tries to re-enter claim()
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        if (!attacked) {
            attacked = true;
            // This should revert with AlreadyClaimed
            distributor.claim(roundId, claimAmount, proof);
        }
        return true;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main test contract
// ─────────────────────────────────────────────────────────────────────────────

contract ARESTest is Test {
    // Contracts
    Proposal proposalManager;
    TimeLockEngine timelockEngine;
    Authorization authLayer;
    RewardDistributor distributor;
    Main treasury;
    MockToken token;

    // Addresses
    address admin = address(0xA1);
    address guardian = address(0xA2);
    address alice = address(0xA3);
    address bob = address(0xA4);

    // Signer keys (whitelisted signers)
    uint256 signer1Pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 signer2Pk = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address signer1;
    address signer2;

    uint256 constant DELAY = 2 days;
    uint256 constant GRACE = 7 days;
    uint256 constant DEPOSIT = 0.1 ether;

    // ─────────────────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        signer1 = vm.addr(signer1Pk);
        signer2 = vm.addr(signer2Pk);

        vm.deal(admin, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);

        token = new MockToken();

        // Build signer array
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        // Deploy all modules
        vm.startPrank(admin);

        proposalManager = new Proposal(2, address(1), address(2), guardian);
        timelockEngine = new TimeLockEngine(DELAY, GRACE, address(proposalManager), guardian);
        authLayer = new Authorization(address(proposalManager), signers);

        // Redeploy proposalManager with real addresses
        proposalManager = new Proposal(2, address(authLayer), address(timelockEngine), guardian);
        authLayer = new Authorization(address(proposalManager), signers);

        distributor = new RewardDistributor();

        treasury = new Main(
            address(proposalManager), address(timelockEngine), address(authLayer), address(distributor), guardian
        );

        proposalManager.setAuthorisedProposer(address(treasury), true);
        proposalManager.setAuthorisedProposer(admin, true);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    // Build a simple ETH transfer action
    function _action(address to, uint256 amt) internal pure returns (IProposal.Action memory) {
        return IProposal.Action({
            actionType: IProposal.actionType.TRANSFER, token: address(0), target: to, amount: amt, data: ""
        });
    }

    // Hash an action the same way TimelockEngine does
    function _hashAction(IProposal.Action memory a) internal pure returns (bytes32) {
        return keccak256(abi.encode(a.actionType, a.token, a.target, a.amount, keccak256(a.data)));
    }

    // Build an EIP-712 signature
    function _sign(uint256 pk, uint256 proposalId, bytes32 actionHash, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ApprovalMessage(uint256 proposalId,bytes32 actionHash,uint256 nonce,uint256 deadline)"),
                proposalId,
                actionHash,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", authLayer.domainSeparator(), structHash));
        (v, r, s) = vm.sign(pk, digest);
    }

    // Run propose → 2 approvals → queue. Returns proposalId and operationId.
    function _proposeAndQueue(IProposal.Action memory action)
        internal
        returns (uint256 proposalId, bytes32 operationId)
    {
        vm.prank(admin);
        proposalId = treasury.propose{value: DEPOSIT}(action, keccak256("desc"));

        bytes32 ah = _hashAction(action);
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v1, bytes32 r1, bytes32 s1) = _sign(signer1Pk, proposalId, ah, authLayer.getNonce(signer1), deadline);
        authLayer.verifyAndApproveFor(signer1, proposalId, ah, deadline, v1, r1, s1);

        (uint8 v2, bytes32 r2, bytes32 s2) = _sign(signer2Pk, proposalId, ah, authLayer.getNonce(signer2), deadline);
        authLayer.verifyAndApproveFor(signer2, proposalId, ah, deadline, v2, r2, s2);

        vm.roll(block.number + 1); // advance one block (flash-loan check)
        treasury.queue(proposalId, action);
        operationId = treasury.proposalOperationId(proposalId);
    }

    // Build a 2-leaf Merkle tree. Returns root and proof for leaf[0].
    function _merkle(address r0, uint256 a0, address r1, uint256 a1)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof)
    {
        bytes32 l0 = MerkleLib.hashLeaf(r0, a0);
        bytes32 l1 = MerkleLib.hashLeaf(r1, a1);
        root = l0 <= l1 ? keccak256(abi.encodePacked(l0, l1)) : keccak256(abi.encodePacked(l1, l0));
        proof = new bytes32[](1);
        proof[0] = l1;
    }

    // =========================================================================
    //  TEST 1 — Reentrancy: claim() cannot be re-entered
    // =========================================================================

    function test_Attack_Reentrancy() public {
        // Deploy reentrant token
        ReentrantToken rt = new ReentrantToken();

        uint256 amount = 50 ether;
        bytes32 leaf = MerkleLib.hashLeaf(alice, amount);
        bytes32[] memory emptyProof = new bytes32[](0);

        // Fund and create round
        rt.mint(admin, amount);
        vm.startPrank(admin);
        rt.approve(address(distributor), amount);
        uint256 roundId = distributor.createRound(leaf, address(rt), amount);
        vm.stopPrank();

        // Tell the reentrant token what to call back
        rt.setup(address(distributor), roundId, amount);

        // Alice claims — token.transfer() will try to re-enter claim()
        // The re-entrant call must revert with AlreadyClaimed
        vm.prank(alice);
        vm.expectRevert();
        distributor.claim(roundId, amount, emptyProof);

        // Alice did NOT receive tokens twice
        assertLe(rt.balanceOf(alice), amount, "should not receive more than allocation");
    }

    // =========================================================================
    //  TEST 2 — Double claim: second claim in same round reverts
    // =========================================================================

    function test_Attack_DoubleClaim() public {
        (bytes32 root, bytes32[] memory proof) = _merkle(alice, 100 ether, bob, 50 ether);

        token.mint(admin, 150 ether);
        vm.startPrank(admin);
        token.approve(address(distributor), 150 ether);
        uint256 roundId = distributor.createRound(root, address(token), 150 ether);
        vm.stopPrank();

        // First claim — succeeds
        vm.prank(alice);
        distributor.claim(roundId, 100 ether, proof);

        // Second claim — reverts
        vm.prank(alice);
        vm.expectRevert();
        distributor.claim(roundId, 100 ether, proof);
    }

    // =========================================================================
    //  TEST 3 — Invalid signature: wrong private key
    // =========================================================================

    function test_Attack_InvalidSignature() public {
        IProposal.Action memory action = _action(alice, 1 ether);

        vm.prank(admin);
        uint256 proposalId = treasury.propose{value: DEPOSIT}(action, keccak256("desc"));

        bytes32 ah = _hashAction(action);
        uint256 deadline = block.timestamp + 1 hours;

        // Sign with a random non-whitelisted key
        uint256 randomPk = 0xDEAD;
        address randomAddr = vm.addr(randomPk);

        (uint8 v, bytes32 r, bytes32 s) = _sign(randomPk, proposalId, ah, 0, deadline);

        vm.expectRevert();
        authLayer.verifyAndApproveFor(randomAddr, proposalId, ah, deadline, v, r, s);
    }

    // =========================================================================
    //  TEST 4 — Invalid signature: replayed nonce
    // =========================================================================

    function test_Attack_SignatureReplay() public {
        IProposal.Action memory action = _action(alice, 1 ether);

        vm.prank(admin);
        uint256 proposalId = treasury.propose{value: DEPOSIT}(action, keccak256("desc"));

        bytes32 ah = _hashAction(action);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = authLayer.getNonce(signer1);

        (uint8 v, bytes32 r, bytes32 s) = _sign(signer1Pk, proposalId, ah, nonce, deadline);

        // First use — valid
        authLayer.verifyAndApproveFor(signer1, proposalId, ah, deadline, v, r, s);

        // Replay the same (v, r, s) — nonce has advanced, digest is wrong
        vm.expectRevert();
        authLayer.verifyAndApproveFor(signer1, proposalId, ah, deadline, v, r, s);
    }

    // =========================================================================
    //  TEST 5 — Premature execution: execute before delay elapses
    // =========================================================================

    function test_Attack_PrematureExecution() public {
        vm.deal(address(timelockEngine), 5 ether);

        IProposal.Action memory action = _action(alice, 1 ether);
        (uint256 proposalId, bytes32 operationId) = _proposeAndQueue(action);

        // Try to execute immediately — delay has NOT passed
        ITimeLock.QueuedOp memory op = timelockEngine.getOperation(operationId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimeLock.OperationNotReady.selector, operationId, op.executionTime, block.timestamp
            )
        );
        treasury.execute(proposalId, action);
    }

    // =========================================================================
    //  TEST 6 — Proposal replay: re-executing a completed proposal
    // =========================================================================

    function test_Attack_ProposalReplay() public {
        vm.deal(address(timelockEngine), 5 ether);

        IProposal.Action memory action = _action(alice, 1 ether);
        (uint256 proposalId, bytes32 operationId) = _proposeAndQueue(action);

        // Warp past delay and execute once — valid
        vm.warp(block.timestamp + DELAY + 1);
        treasury.execute(proposalId, action);

        // Try to execute again — operation is DONE
        vm.expectRevert(abi.encodeWithSelector(ITimeLock.OperationAlreadyDone.selector, operationId));
        timelockEngine.execute(operationId, action);
    }

    // =========================================================================
    //  TEST 7 — Invalid Merkle proof: wrong proof rejected
    // =========================================================================

    function test_Attack_InvalidMerkleProof() public {
        (bytes32 root, bytes32[] memory aliceProof) = _merkle(alice, 100 ether, bob, 50 ether);

        token.mint(admin, 150 ether);
        vm.startPrank(admin);
        token.approve(address(distributor), 150 ether);
        uint256 roundId = distributor.createRound(root, address(token), 150 ether);
        vm.stopPrank();

        // Charlie tries to claim using Alice's proof — invalid
        vm.prank(bob);
        vm.expectRevert(MerkleLib.ML_InvalidProof.selector);
        distributor.claim(roundId, 100 ether, aliceProof);
    }

    // =========================================================================
    //  TEST 8 — Signature malleability: upper-half s rejected
    // =========================================================================

    function test_Attack_SignatureMalleability() public {
        IProposal.Action memory action = _action(alice, 1 ether);

        vm.prank(admin);
        uint256 proposalId = treasury.propose{value: DEPOSIT}(action, keccak256("desc"));

        bytes32 ah = _hashAction(action);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = authLayer.getNonce(signer1);

        (uint8 v, bytes32 r, bytes32 s) = _sign(signer1Pk, proposalId, ah, nonce, deadline);

        // Compute the malleable mirror: s' = curve_order - s
        bytes32 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 ms = bytes32(uint256(n) - uint256(s));
        uint8 mv = v == 27 ? 28 : 27;

        // Mirror signature must be rejected
        vm.expectRevert(abi.encodeWithSelector(SignatureLib.SL_MalleableSignature.selector, ms));
        authLayer.verifyAndApproveFor(signer1, proposalId, ah, deadline, mv, r, ms);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/bridges/CrossEVMBridge.sol";
import "./MockERC20.sol";

contract CrossEVMBridgeDeepTest is Test {
    SeraphToken public ser;
    CrossEVMBridge public bridge;

    address public treasury = makeAddr("treasury");
    address public guardian = makeAddr("guardian");
    address public challenger = makeAddr("challenger");

    address public relayer1 = makeAddr("relayer1");
    address public relayer2 = makeAddr("relayer2");
    address public relayer3 = makeAddr("relayer3");
    address public eve = makeAddr("eve"); // malicious relayer

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public dave = makeAddr("dave");

    bytes32 public constant SERAPH_EVM_ID = keccak256("SERAPH_EVM");
    bytes32 public constant XMR_EVM_ID = keccak256("XMR_EVM");
    bytes32 public constant BASE_CHAIN_ID = keccak256("BASE_CHAIN");

    event RelayerBonded(address indexed relayer, uint256 totalBond);
    event RelayerUnbonded(address indexed relayer, uint256 amount, uint256 remainingBond);
    event BatchSubmitted(uint256 indexed batchId, bytes32 indexed sourceChainId, bytes32 stateRoot, address indexed relayer);
    event BatchChallenged(uint256 indexed batchId, address indexed challenger, address indexed slashedRelayer);
    event TokensLocked(uint256 indexed nonce, address indexed sender, address indexed recipient, uint256 amount, bytes32 destChainId);
    event TokensClaimed(uint256 indexed batchId, bytes32 indexed nullifier, address indexed recipient, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        ser = new SeraphToken(address(0), treasury, address(0));
        vm.prank(treasury);
        ser.setSellTaxEnabled(false);

        bridge = new CrossEVMBridge(address(ser), SERAPH_EVM_ID, guardian);
        vm.prank(treasury);
        ser.setMinter(address(bridge), true);

        // Fund test accounts
        vm.deal(relayer1, 10 ether);
        vm.deal(relayer2, 10 ether);
        vm.deal(relayer3, 10 ether);
        vm.deal(eve, 10 ether);
        vm.deal(challenger, 1 ether);

        vm.prank(treasury);
        ser.mint(alice, 100_000e18);
        vm.prank(treasury);
        ser.mint(bob, 100_000e18);
    }

    // Helper for sorted pair hashing (matching CrossEVMBridge._verifyProof)
    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // Helper to compute bridge leaf
    function computeLeaf(bytes32 nullifier, address recipient, uint256 amount, bytes32 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(nullifier, recipient, amount, chainId));
    }

    /* ========================================================================= */
    /* 1. MULTI-RELAYER CONCURRENT BONDING & UNBONDING TIMING EDGE CASES         */
    /* ========================================================================= */

    function test_MultiRelayer_BondingThresholds() public {
        // Less than 1 ether bond reverts
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.bondRelayer{value: 0.5 ether}();

        // 1 ether or more succeeds
        vm.prank(relayer1);
        bridge.bondRelayer{value: 1 ether}();
        assertEq(bridge.relayerBonds(relayer1), 1 ether);

        // Can top up with additional amount (even < 1 ether) since total >= MIN_RELAYER_BOND
        vm.prank(relayer1);
        bridge.bondRelayer{value: 0.5 ether}();
        assertEq(bridge.relayerBonds(relayer1), 1.5 ether);

        // Multiple relayers bonding concurrently
        vm.prank(relayer2);
        bridge.bondRelayer{value: 3 ether}();
        assertEq(bridge.relayerBonds(relayer2), 3 ether);

        vm.prank(relayer3);
        bridge.bondRelayer{value: 1.5 ether}();
        assertEq(bridge.relayerBonds(relayer3), 1.5 ether);
    }

    function test_MultiRelayer_UnbondWithoutBatches_ImmediateSuccess() public {
        vm.prank(relayer3);
        bridge.bondRelayer{value: 2 ether}();

        // Relayer 3 has submitted 0 batches (lastBatchSubmittedAt == 0)
        // Can unbond immediately without waiting 1 hour
        uint256 balBefore = relayer3.balance;
        vm.prank(relayer3);
        bridge.unbondRelayer(1.5 ether);
        assertEq(relayer3.balance, balBefore + 1.5 ether);
        assertEq(bridge.relayerBonds(relayer3), 0.5 ether);

        // Can unbond remaining bond
        vm.prank(relayer3);
        bridge.unbondRelayer(0.5 ether);
        assertEq(bridge.relayerBonds(relayer3), 0);
    }

    function test_MultiRelayer_ConcurrentTimingEdgeCases_BeforeVsAfter1Hour() public {
        // Relayer 1 bonds 2 ether, Relayer 2 bonds 3 ether
        vm.prank(relayer1);
        bridge.bondRelayer{value: 2 ether}();
        vm.prank(relayer2);
        bridge.bondRelayer{value: 3 ether}();

        uint256 t0 = 10_000;
        vm.warp(t0);

        // Relayer 1 submits batch at t0
        vm.prank(relayer1);
        bridge.submitStateBatch(XMR_EVM_ID, keccak256("root_relayer1"));
        assertEq(bridge.lastBatchSubmittedAt(relayer1), t0);

        // Advance 500s; Relayer 2 submits batch at t0 + 500
        vm.warp(t0 + 500);
        vm.prank(relayer2);
        bridge.submitStateBatch(XMR_EVM_ID, keccak256("root_relayer2"));
        assertEq(bridge.lastBatchSubmittedAt(relayer2), t0 + 500);

        // --- At t0 + 3599 (1 second BEFORE 1 hour for Relayer 1) ---
        vm.warp(t0 + 3599);

        // Relayer 1 unbonding MUST revert
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.ChallengeWindowActive.selector);
        bridge.unbondRelayer(1 ether);

        // Relayer 2 unbonding MUST revert (only 3099s elapsed)
        vm.prank(relayer2);
        vm.expectRevert(CrossEVMBridge.ChallengeWindowActive.selector);
        bridge.unbondRelayer(1 ether);

        // --- At t0 + 3600 (EXACTLY 1 hour after Relayer 1 submitted) ---
        vm.warp(t0 + 3600);

        // Relayer 1 unbonding 1 ether MUST SUCCEED
        uint256 r1BalBefore = relayer1.balance;
        vm.prank(relayer1);
        bridge.unbondRelayer(1 ether);
        assertEq(relayer1.balance, r1BalBefore + 1 ether);
        assertEq(bridge.relayerBonds(relayer1), 1 ether);

        // Relayer 2 still within challenge window (3100s < 3600s) -> MUST REVERT
        vm.prank(relayer2);
        vm.expectRevert(CrossEVMBridge.ChallengeWindowActive.selector);
        bridge.unbondRelayer(1 ether);

        // --- At t0 + 4100 (EXACTLY 1 hour after Relayer 2 submitted: t0 + 500 + 3600) ---
        vm.warp(t0 + 4100);

        // Relayer 2 full unbond of 3 ether MUST SUCCEED
        uint256 r2BalBefore = relayer2.balance;
        vm.prank(relayer2);
        bridge.unbondRelayer(3 ether);
        assertEq(relayer2.balance, r2BalBefore + 3 ether);
        assertEq(bridge.relayerBonds(relayer2), 0);

        // Relayer 2 now has 0 bond; cannot submit another batch
        vm.prank(relayer2);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.submitStateBatch(XMR_EVM_ID, keccak256("root_relayer2_second"));

        // Relayer 1 still has 1 ether bond (>= MIN_RELAYER_BOND); submits second batch at t0 + 5000
        vm.warp(t0 + 5000);
        vm.prank(relayer1);
        bridge.submitStateBatch(XMR_EVM_ID, keccak256("root_relayer1_second"));
        assertEq(bridge.lastBatchSubmittedAt(relayer1), t0 + 5000);

        // New submission restarts challenge window for Relayer 1
        vm.warp(t0 + 5000 + 10);
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.ChallengeWindowActive.selector);
        bridge.unbondRelayer(1 ether);
    }

    function test_MultiRelayer_UnbondInvalidAmounts_Reverts() public {
        vm.prank(relayer1);
        bridge.bondRelayer{value: 2 ether}();

        // Unbonding 0 reverts
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.unbondRelayer(0);

        // Unbonding more than balance reverts
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.unbondRelayer(2.0001 ether);
    }

    function test_MultiRelayer_PartialUnbondBelowMin_BlocksSubsequentBatches() public {
        vm.prank(relayer1);
        bridge.bondRelayer{value: 1.5 ether}();

        // Partial unbond of 0.6 ether leaving 0.9 ether
        vm.prank(relayer1);
        bridge.unbondRelayer(0.6 ether);
        assertEq(bridge.relayerBonds(relayer1), 0.9 ether);

        // Cannot submit batch because bond is now < 1 ether
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.submitStateBatch(XMR_EVM_ID, keccak256("root"));

        // Top up bond by 0.2 ether -> 1.1 ether -> now can submit
        vm.prank(relayer1);
        bridge.bondRelayer{value: 0.2 ether}();
        assertEq(bridge.relayerBonds(relayer1), 1.1 ether);

        vm.prank(relayer1);
        uint256 batchId = bridge.submitStateBatch(XMR_EVM_ID, keccak256("root"));
        assertEq(batchId, 0);
    }

    /* ========================================================================= */
    /* 2. FRAUDULENT BATCH SUBMISSION & GUARDIAN SLASHING VIA challengeBatch()   */
    /* ========================================================================= */

    function test_FraudulentBatch_SlashToChallengerAndBatchCancelled() public {
        // Eve bonds 5 ether
        vm.prank(eve);
        bridge.bondRelayer{value: 5 ether}();
        assertEq(bridge.relayerBonds(eve), 5 ether);

        // Eve submits fraudulent batch
        bytes32 fakeRoot = keccak256("fake_state_root");
        vm.prank(eve);
        uint256 badBatchId = bridge.submitStateBatch(XMR_EVM_ID, fakeRoot);

        // 1. Non-guardian cannot challenge
        vm.prank(alice);
        vm.expectRevert(CrossEVMBridge.Unauthorized.selector);
        bridge.challengeBatch(badBatchId, challenger);

        // 2. Guardian cannot pass address(0) as challenger
        vm.prank(guardian);
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.challengeBatch(badBatchId, address(0));

        // 3. Guardian cannot challenge non-existent batch
        vm.prank(guardian);
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.challengeBatch(999, challenger);

        // 4. Guardian slashes fraudulent batch
        uint256 challengerBalBefore = challenger.balance;

        vm.expectEmit(true, true, true, true);
        emit BatchChallenged(badBatchId, challenger, eve);

        vm.prank(guardian);
        bridge.challengeBatch(badBatchId, challenger);

        // Verify slashed funds transferred in full to challenger
        assertEq(challenger.balance, challengerBalBefore + 5 ether);
        // Verify Eve's bond is reduced to 0
        assertEq(bridge.relayerBonds(eve), 0);

        // Verify batch is marked challenged
        (, , , , bool challenged) = bridge.batches(badBatchId);
        assertTrue(challenged);

        // 5. Cannot challenge the same batch again
        vm.prank(guardian);
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.challengeBatch(badBatchId, challenger);

        // 6. Slashed Eve cannot submit new batches
        vm.prank(eve);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.submitStateBatch(XMR_EVM_ID, keccak256("new_root"));

        // 7. Slashed Eve cannot unbond
        vm.prank(eve);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.unbondRelayer(1 ether);

        // 8. Even after 1 hour, claims against the challenged batch are permanently blocked
        vm.warp(block.timestamp + 1 hours + 1);
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes32 nullifier = keccak256("nullifier_on_cancelled_batch");

        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.claimBridged(badBatchId, nullifier, alice, 100e18, emptyProof);
    }

    function test_FraudulentBatch_SlashWithZeroBondRemaining() public {
        // Relayer bonds 1 ether, submits batch, waits 1h, unbonds 1 ether
        vm.prank(relayer1);
        bridge.bondRelayer{value: 1 ether}();
        vm.prank(relayer1);
        uint256 batchId = bridge.submitStateBatch(XMR_EVM_ID, keccak256("root"));

        vm.warp(block.timestamp + 1 hours);
        vm.prank(relayer1);
        bridge.unbondRelayer(1 ether);
        assertEq(bridge.relayerBonds(relayer1), 0);

        // Guardian challenges batch: slashed bond is 0, transfer doesn't revert, batch marked challenged
        uint256 challengerBalBefore = challenger.balance;
        vm.prank(guardian);
        bridge.challengeBatch(batchId, challenger);
        assertEq(challenger.balance, challengerBalBefore);

        (, , , , bool challenged) = bridge.batches(batchId);
        assertTrue(challenged);
    }

    /* ========================================================================= */
    /* 3. DOUBLE-SPEND ATTEMPTS WITH REPLAY NULLIFIERS                          */
    /* ========================================================================= */

    function test_ClaimBridged_ReplayNullifierOnSameBatch_Reverts() public {
        vm.prank(relayer1);
        bridge.bondRelayer{value: 1 ether}();

        bytes32 nullifier = keccak256("unique_nullifier_01");
        uint256 amount = 1_000e18;
        bytes32 leaf = computeLeaf(nullifier, alice, amount, SERAPH_EVM_ID);

        vm.prank(relayer1);
        uint256 batchId = bridge.submitStateBatch(XMR_EVM_ID, leaf);

        bytes32[] memory emptyProof = new bytes32[](0);

        // Cannot claim before 1 hour challenge window
        vm.expectRevert(CrossEVMBridge.ChallengeWindowActive.selector);
        bridge.claimBridged(batchId, nullifier, alice, amount, emptyProof);

        // Warp past challenge window
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 aliceBalBefore = ser.balanceOf(alice);
        vm.expectEmit(true, true, true, true);
        emit TokensClaimed(batchId, nullifier, alice, amount);
        bridge.claimBridged(batchId, nullifier, alice, amount, emptyProof);

        assertEq(ser.balanceOf(alice), aliceBalBefore + amount);
        assertTrue(bridge.processedNullifiers(nullifier));

        // ATTACK 1: Exact replay by Alice on the same batch
        vm.expectRevert(CrossEVMBridge.NullifierAlreadyUsed.selector);
        bridge.claimBridged(batchId, nullifier, alice, amount, emptyProof);

        // ATTACK 2: Replay by attacker Carol attempting to claim to herself
        vm.expectRevert(CrossEVMBridge.NullifierAlreadyUsed.selector);
        bridge.claimBridged(batchId, nullifier, carol, amount, emptyProof);

        // ATTACK 3: Replay with modified amount
        vm.expectRevert(CrossEVMBridge.NullifierAlreadyUsed.selector);
        bridge.claimBridged(batchId, nullifier, alice, amount * 2, emptyProof);
    }

    function test_ClaimBridged_ReplayNullifierAcrossDifferentBatches_Reverts() public {
        vm.prank(relayer1);
        bridge.bondRelayer{value: 2 ether}();

        bytes32 nullifier = keccak256("cross_batch_nullifier");
        uint256 amount = 500e18;
        bytes32 leaf1 = computeLeaf(nullifier, alice, amount, SERAPH_EVM_ID);

        // Relayer submits batch 1 containing nullifier
        vm.prank(relayer1);
        uint256 batch1 = bridge.submitStateBatch(XMR_EVM_ID, leaf1);

        vm.warp(block.timestamp + 1 hours + 1);
        bytes32[] memory emptyProof = new bytes32[](0);

        // Legitimate claim on batch 1
        bridge.claimBridged(batch1, nullifier, alice, amount, emptyProof);
        assertTrue(bridge.processedNullifiers(nullifier));

        // Malicious relayer submits batch 2 also containing the same nullifier
        bytes32 leaf2 = computeLeaf(nullifier, bob, amount, SERAPH_EVM_ID);
        vm.prank(relayer1);
        uint256 batch2 = bridge.submitStateBatch(XMR_EVM_ID, leaf2);

        vm.warp(block.timestamp + 1 hours + 1);

        // Cross-batch double-spend MUST revert with NullifierAlreadyUsed
        vm.expectRevert(CrossEVMBridge.NullifierAlreadyUsed.selector);
        bridge.claimBridged(batch2, nullifier, bob, amount, emptyProof);
    }

    function test_ClaimBridged_ZeroNullifierOrRecipientOrAmount_Reverts() public {
        vm.prank(relayer1);
        bridge.bondRelayer{value: 1 ether}();
        bytes32 root = keccak256("root");
        vm.prank(relayer1);
        uint256 batchId = bridge.submitStateBatch(XMR_EVM_ID, root);

        vm.warp(block.timestamp + 1 hours + 1);
        bytes32[] memory emptyProof = new bytes32[](0);

        // Zero nullifier reverts
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.claimBridged(batchId, bytes32(0), alice, 100e18, emptyProof);

        // Zero recipient reverts
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.claimBridged(batchId, keccak256("nullifier"), address(0), 100e18, emptyProof);

        // Zero amount reverts
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.claimBridged(batchId, keccak256("nullifier"), alice, 0, emptyProof);
    }

    /* ========================================================================= */
    /* 4. PAUSE / UNPAUSE CIRCUIT BREAKER                                        */
    /* ========================================================================= */

    function test_SetPaused_BlocksAllBridgingAndUnpauseRestoresFunctionality() public {
        // 1. Non-guardian cannot pause
        vm.prank(alice);
        vm.expectRevert(CrossEVMBridge.Unauthorized.selector);
        bridge.setPaused(true);

        // 2. Guardian pauses bridge
        vm.expectEmit(true, true, true, true);
        emit Paused(guardian);
        vm.prank(guardian);
        bridge.setPaused(true);
        assertTrue(bridge.paused());

        // Setup test state
        vm.prank(relayer1);
        bridge.bondRelayer{value: 1 ether}(); // Bonding is still possible during pause for emergency recap

        bytes32 nullifier = keccak256("pause_test_nullifier");
        uint256 amount = 100e18;
        bytes32 leaf = computeLeaf(nullifier, alice, amount, SERAPH_EVM_ID);

        // 3. submitStateBatch is BLOCKED while paused
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.BridgePaused.selector);
        bridge.submitStateBatch(XMR_EVM_ID, leaf);

        // 4. bridgeOut is BLOCKED while paused
        vm.startPrank(alice);
        ser.approve(address(bridge), amount);
        vm.expectRevert(CrossEVMBridge.BridgePaused.selector);
        bridge.bridgeOut(bob, amount, XMR_EVM_ID);
        vm.stopPrank();

        // 5. claimBridged is BLOCKED while paused
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(CrossEVMBridge.BridgePaused.selector);
        bridge.claimBridged(0, nullifier, alice, amount, emptyProof);

        // 6. Guardian unpauses bridge
        vm.expectEmit(true, true, true, true);
        emit Unpaused(guardian);
        vm.prank(guardian);
        bridge.setPaused(false);
        assertFalse(bridge.paused());

        // 7. Clean restoration: submitStateBatch works
        vm.prank(relayer1);
        uint256 batchId = bridge.submitStateBatch(XMR_EVM_ID, leaf);
        assertEq(batchId, 0);

        // 8. Clean restoration: bridgeOut works
        vm.startPrank(alice);
        ser.approve(address(bridge), amount);
        uint256 nonce = bridge.bridgeOut(bob, amount, XMR_EVM_ID);
        assertEq(nonce, 0);
        assertEq(ser.balanceOf(address(bridge)), amount);
        vm.stopPrank();

        // 9. Clean restoration: claimBridged works after challenge window
        vm.warp(block.timestamp + 1 hours + 1);
        uint256 aliceBalBefore = ser.balanceOf(alice);
        bridge.claimBridged(batchId, nullifier, alice, amount, emptyProof);
        assertEq(ser.balanceOf(alice), aliceBalBefore + amount);
    }

    /* ========================================================================= */
    /* 5. INVALID MERKLE PROOF REJECTION                                         */
    /* ========================================================================= */

    bytes32 internal nullifier0 = keccak256("nullifier_0");
    bytes32 internal nullifier1 = keccak256("nullifier_1");
    bytes32 internal nullifier2 = keccak256("nullifier_2");
    bytes32 internal nullifier3 = keccak256("nullifier_3");
    uint256 internal amt0 = 100e18;
    uint256 internal amt1 = 200e18;
    uint256 internal amt2 = 300e18;
    uint256 internal amt3 = 400e18;
    bytes32 internal l0;
    bytes32 internal l1;
    bytes32 internal l2;
    bytes32 internal l3;
    bytes32 internal h01;
    bytes32 internal h23;
    bytes32 internal treeRoot;
    uint256 internal treeBatchId;

    function _initMerkleTree() internal {
        l0 = computeLeaf(nullifier0, alice, amt0, SERAPH_EVM_ID);
        l1 = computeLeaf(nullifier1, bob, amt1, SERAPH_EVM_ID);
        l2 = computeLeaf(nullifier2, carol, amt2, SERAPH_EVM_ID);
        l3 = computeLeaf(nullifier3, dave, amt3, SERAPH_EVM_ID);

        h01 = hashPair(l0, l1);
        h23 = hashPair(l2, l3);
        treeRoot = hashPair(h01, h23);

        vm.prank(relayer1);
        bridge.bondRelayer{value: 2 ether}();
        vm.prank(relayer1);
        treeBatchId = bridge.submitStateBatch(XMR_EVM_ID, treeRoot);
        vm.warp(block.timestamp + 1 hours + 1);
    }

    function test_InvalidMerkleProof_MutatedProofElement_Reverts() public {
        _initMerkleTree();

        bytes32[] memory mutatedProof = new bytes32[](2);
        mutatedProof[0] = bytes32(uint256(l1) ^ 1);
        mutatedProof[1] = h23;

        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(treeBatchId, nullifier0, alice, amt0, mutatedProof);
    }

    function test_InvalidMerkleProof_WrongLengthOrOrder_Reverts() public {
        _initMerkleTree();

        // Truncated proof (length 1)
        bytes32[] memory truncatedProof = new bytes32[](1);
        truncatedProof[0] = l1;
        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(treeBatchId, nullifier0, alice, amt0, truncatedProof);

        // Extended proof (length 3)
        bytes32[] memory extendedProof = new bytes32[](3);
        extendedProof[0] = l1;
        extendedProof[1] = h23;
        extendedProof[2] = keccak256("extra");
        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(treeBatchId, nullifier0, alice, amt0, extendedProof);

        // Swapped proof order [H23, L1]
        bytes32[] memory swappedProof = new bytes32[](2);
        swappedProof[0] = h23;
        swappedProof[1] = l1;
        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(treeBatchId, nullifier0, alice, amt0, swappedProof);
    }

    function test_InvalidMerkleProof_TamperedLeafInputs_Reverts() public {
        _initMerkleTree();

        bytes32[] memory validProofL0 = new bytes32[](2);
        validProofL0[0] = l1;
        validProofL0[1] = h23;

        // Tampered recipient (Eve instead of Alice)
        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(treeBatchId, nullifier0, eve, amt0, validProofL0);

        // Tampered amount (2x amount)
        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(treeBatchId, nullifier0, alice, amt0 * 2, validProofL0);

        // Tampered nullifier (nullifier1 with Leaf 0's proof and recipient)
        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(treeBatchId, nullifier1, alice, amt0, validProofL0);

        // Valid proof applied to a different batch root
        vm.prank(relayer1);
        uint256 otherBatchId = bridge.submitStateBatch(XMR_EVM_ID, keccak256("unrelated_root"));
        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(otherBatchId, nullifier0, alice, amt0, validProofL0);
    }

    function test_ValidMerkleProof_MultiLeafTreeClaims_Succeed() public {
        _initMerkleTree();

        // Claim Leaf 0: proof [L1, H23]
        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = l1;
        proof0[1] = h23;

        uint256 aliceBefore = ser.balanceOf(alice);
        bridge.claimBridged(treeBatchId, nullifier0, alice, amt0, proof0);
        assertEq(ser.balanceOf(alice), aliceBefore + amt0);

        // Claim Leaf 2: proof [L3, H01]
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = l3;
        proof2[1] = h01;

        uint256 carolBefore = ser.balanceOf(carol);
        bridge.claimBridged(treeBatchId, nullifier2, carol, amt2, proof2);
        assertEq(ser.balanceOf(carol), carolBefore + amt2);
    }

    /* ========================================================================= */
    /* 6. ADDITIONAL PROTOCOL EDGE CASES                                         */
    /* ========================================================================= */

    function test_BridgeConstructor_ZeroAddress_Reverts() public {
        vm.expectRevert("CrossEVMBridge: zero address");
        new CrossEVMBridge(address(0), SERAPH_EVM_ID, guardian);

        vm.expectRevert("CrossEVMBridge: zero address");
        new CrossEVMBridge(address(ser), SERAPH_EVM_ID, address(0));
    }

    function test_SubmitStateBatch_InvalidParameters_Reverts() public {
        vm.prank(relayer1);
        bridge.bondRelayer{value: 1 ether}();

        // Zero sourceChainId
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.submitStateBatch(bytes32(0), keccak256("root"));

        // Same as localChainId
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.submitStateBatch(SERAPH_EVM_ID, keccak256("root"));

        // Zero stateRoot
        vm.prank(relayer1);
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.submitStateBatch(XMR_EVM_ID, bytes32(0));
    }

    function test_BridgeOut_InvalidParameters_Reverts() public {
        // Zero recipient
        vm.startPrank(alice);
        ser.approve(address(bridge), 100e18);
        vm.expectRevert("CrossEVMBridge: invalid bridge params");
        bridge.bridgeOut(address(0), 100e18, XMR_EVM_ID);

        // Zero amount
        vm.expectRevert("CrossEVMBridge: invalid bridge params");
        bridge.bridgeOut(bob, 0, XMR_EVM_ID);

        // Zero destChainId
        vm.expectRevert("CrossEVMBridge: invalid bridge params");
        bridge.bridgeOut(bob, 100e18, bytes32(0));

        // Same destChainId as localChainId
        vm.expectRevert("CrossEVMBridge: invalid bridge params");
        bridge.bridgeOut(bob, 100e18, SERAPH_EVM_ID);
        vm.stopPrank();
    }
}

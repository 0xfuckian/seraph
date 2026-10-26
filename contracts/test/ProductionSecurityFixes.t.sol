// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/PrivacyPool.sol";
import "../core/bridges/CrossEVMBridge.sol";
import "../governance/SeraphTimelock.sol";
import "./mocks/MockVerifier.sol";

contract ProductionSecurityFixesTest is Test {
    SeraphToken public token;
    PrivacyPool public pool;
    CrossEVMBridge public bridge;
    MockVerifier public verifier;
    SeraphTimelock public timelock;

    address public treasury = address(0x1111);
    address public guardian = address(0x2222);
    address public relayer = address(0x3333);
    address public user = address(0x4444);
    address public attacker = address(0x6666);
    address public newGovernance = address(0x7777);

    bytes32 public localChain = bytes32(uint256(84532)); // Base Sepolia
    bytes32 public remoteChain = bytes32(uint256(8453));

    function setUp() public {
        vm.deal(relayer, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(attacker, 100 ether);

        verifier = new MockVerifier();

        token = new SeraphToken(address(0), treasury, address(0));
        bridge = new CrossEVMBridge(address(token), localChain, guardian);
        pool = new PrivacyPool(address(token), treasury, address(verifier), address(0));

        vm.startPrank(treasury);
        token.setPrivacyPool(address(pool));
        token.setMinter(address(bridge), true);
        token.mint(user, 10_000e18);
        token.mint(address(pool), 50_000e18);
        vm.stopPrank();

        vm.prank(guardian);
        bridge.setBridgeVerifier(address(verifier));
    }

    /* ------------------------------------------------------------------ */
    /* 1. ZK PROOF VERIFICATION CANNOT BE BYPASSED                        */
    /* ------------------------------------------------------------------ */

    function test_PrivacyPool_ZeroVerifierCannotBeSet() public {
        vm.prank(treasury);
        vm.expectRevert("PrivacyPool: zero verifier not allowed");
        pool.setSpendVerifier(address(0));
    }

    function test_PrivacyPool_ZeroVerifierRevertsPrivateTransferAndUnshield() public {
        // Deploy sandbox pool with address(0)
        PrivacyPool unconfiguredPool = new PrivacyPool(address(token), treasury, address(0), address(0));

        bytes32 root = unconfiguredPool.getLastRoot();
        bytes32[] memory nullifiers = new bytes32[](1);
        nullifiers[0] = keccak256("test_nullifier");
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = keccak256("test_commitment");

        // privateTransfer must revert if spendVerifier == address(0)
        vm.expectRevert("PrivacyPool: spend verifier not configured");
        unconfiguredPool.privateTransfer(nullifiers, commitments, root, "");

        // unshield must revert if spendVerifier == address(0)
        vm.expectRevert("PrivacyPool: spend verifier not configured");
        unconfiguredPool.unshield(keccak256("test_nullifier"), 100e18, user, root, "");
    }

    function test_PrivacyPool_InvalidZKProofReverts() public {
        verifier.setShouldPass(false);

        vm.startPrank(user);
        token.approve(address(pool), 1000e18);
        pool.shield(1000e18, keccak256("comm_1"), "");
        vm.stopPrank();

        bytes32 root = pool.getLastRoot();
        bytes32[] memory nullifiers = new bytes32[](1);
        nullifiers[0] = keccak256("n1");
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = keccak256("c2");

        vm.expectRevert("PrivacyPool: invalid proof");
        pool.privateTransfer(nullifiers, commitments, root, "invalid_proof");

        vm.expectRevert("PrivacyPool: invalid proof");
        pool.unshield(keccak256("n1"), 100e18, user, root, "invalid_proof");
    }

    /* ------------------------------------------------------------------ */
    /* 2. PERMISSIONLESS BRIDGE FRAUD CHALLENGES                          */
    /* ------------------------------------------------------------------ */

    function test_CrossEVMBridge_PermissionlessFraudProofSlashesRelayer() public {
        vm.prank(relayer);
        bridge.bondRelayer{value: 1 ether}();

        bytes32 badRoot = keccak256("malicious_state_root");
        vm.prank(relayer);
        uint256 batchId = bridge.submitStateBatch(remoteChain, badRoot);

        // Attacker or any public challenger sees fraud
        address publicChallenger = address(0x9999);
        uint256 challengerBalanceBefore = publicChallenger.balance;

        bytes32[] memory signals = new bytes32[](1);
        signals[0] = badRoot;

        // verifier confirms fraud
        verifier.setShouldPassBridge(true);

        vm.prank(publicChallenger);
        bridge.challengeBatchWithFraudProof(batchId, "fraud_proof", signals);

        // Relayer's bond slashed to 0 and sent directly to challenger as bounty
        assertEq(bridge.relayerBonds(relayer), 0);
        assertEq(publicChallenger.balance, challengerBalanceBefore + 1 ether);

        (,,,, bool challenged) = bridge.batches(batchId);
        assertTrue(challenged);
    }

    function test_CrossEVMBridge_PermissionlessDuplicateNullifierChallenge() public {
        bytes32 nullifier = keccak256("spent_nullifier");
        bytes32 leaf = keccak256(abi.encodePacked(nullifier, user, uint256(100e18), localChain));
        bytes32 stateRoot = leaf;

        vm.prank(relayer);
        bridge.bondRelayer{value: 1 ether}();
        vm.prank(relayer);
        uint256 batchId = bridge.submitStateBatch(remoteChain, stateRoot);

        // Wait out challenge window for first legitimate claim
        vm.warp(block.timestamp + 1 hours + 1);

        bytes32[] memory proof = new bytes32[](0);

        // Claim tokens initially
        bridge.claimBridged(batchId, nullifier, user, 100e18, proof);
        assertTrue(bridge.processedNullifiers(nullifier));

        // Now relayer posts another batch attempting to reuse nullifier
        vm.prank(relayer);
        bridge.bondRelayer{value: 1 ether}();
        bytes32 badRoot = leaf;
        vm.prank(relayer);
        uint256 secondBatchId = bridge.submitStateBatch(remoteChain, badRoot);

        // Anyone spots duplicate nullifier within challenge window
        address watcher = address(0x8888);
        uint256 watcherBefore = watcher.balance;

        vm.prank(watcher);
        bridge.challengeDuplicateNullifier(secondBatchId, nullifier, user, 100e18, proof);

        assertEq(bridge.relayerBonds(relayer), 0);
        assertEq(watcher.balance, watcherBefore + 2 ether);

        (,,,, bool challenged2) = bridge.batches(secondBatchId);
        assertTrue(challenged2);
    }

    /* ------------------------------------------------------------------ */
    /* 3. 2-STEP GOVERNANCE TRANSFERS (PRIVILEGE DECENTRALIZATION)         */
    /* ------------------------------------------------------------------ */

    function test_SeraphToken_TwoStepTreasuryHandover() public {
        vm.prank(treasury);
        token.transferTreasury(newGovernance);
        assertEq(token.pendingTreasury(), newGovernance);

        // Unauthorized cannot claim
        vm.prank(attacker);
        vm.expectRevert("SeraphToken: not pending treasury");
        token.acceptTreasury();

        // Valid new governance accepts
        vm.prank(newGovernance);
        token.acceptTreasury();
        assertEq(token.treasury(), newGovernance);
        assertEq(token.pendingTreasury(), address(0));
        assertTrue(token.minters(newGovernance));
    }

    function test_PrivacyPool_TwoStepTreasuryHandover() public {
        vm.prank(treasury);
        pool.transferTreasury(newGovernance);
        assertEq(pool.pendingTreasury(), newGovernance);

        vm.prank(newGovernance);
        pool.acceptTreasury();
        assertEq(pool.treasury(), newGovernance);
        assertEq(pool.pendingTreasury(), address(0));
    }

    function test_CrossEVMBridge_TwoStepGuardianHandover() public {
        vm.prank(guardian);
        bridge.transferGuardian(newGovernance);
        assertEq(bridge.pendingGuardian(), newGovernance);

        vm.prank(newGovernance);
        bridge.acceptGuardian();
        assertEq(bridge.guardian(), newGovernance);
        assertEq(bridge.pendingGuardian(), address(0));
    }

    /* ------------------------------------------------------------------ */
    /* 4. GOVERNANCE TIMELOCK CONTROLLER                                  */
    /* ------------------------------------------------------------------ */

    function test_SeraphTimelock_MinDelayFloorAndExecution() public {
        address[] memory proposers = new address[](1);
        proposers[0] = treasury;
        address[] memory executors = new address[](1);
        executors[0] = treasury;

        // Delay < 1 day must revert
        vm.expectRevert("SeraphTimelock: delay too short for production");
        new SeraphTimelock(12 hours, proposers, executors, treasury);

        // Production delay of 2 days
        timelock = new SeraphTimelock(2 days, proposers, executors, treasury);
        assertEq(timelock.getMinDelay(), 2 days);
    }
}

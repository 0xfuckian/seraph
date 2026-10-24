// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/PrivacyPool.sol";
import "../core/bridges/CrossEVMBridge.sol";

contract CircuitBreakersAndExemptionsTest is Test {
    SeraphToken public ser;
    PrivacyPool public pool;
    CrossEVMBridge public bridge;

    address public treasury = address(0x1111);
    address public guardian = address(0x2222);
    address public dexRouter = address(0x3333);
    address public alice = address(0x4444);
    address public bob = address(0x5555);

    bytes32 public constant LOCAL_CHAIN = keccak256("seraph_evm");
    bytes32 public constant REMOTE_CHAIN = keccak256("base_layer");

    function setUp() public {
        vm.deal(treasury, 100 ether);
        vm.deal(guardian, 100 ether);
        vm.deal(alice, 100 ether);

        vm.startPrank(treasury);
        ser = new SeraphToken(address(0), treasury, address(0));
        pool = new PrivacyPool(address(ser), treasury, address(0), address(0));
        ser.setPrivacyPool(address(pool));
        bridge = new CrossEVMBridge(address(ser), LOCAL_CHAIN, guardian);
        ser.setTaxExempt(address(bridge), true);

        // Mint some SER to alice
        ser.mint(alice, 10_000 ether);
        vm.stopPrank();
    }

    /* ------------------------------------------------------------------ */
    /* SERAPH Tax Exemption Tests                                         */
    /* ------------------------------------------------------------------ */

    function test_TaxExemption_PreventsSellTaxOnDEX() public {
        // Alice sends SER to dexRouter without exemption -> 1% tax collected
        vm.prank(alice);
        ser.transfer(dexRouter, 1000 ether);
        // 1% tax = 10 SER (5 burned, 5 to treasury), dexRouter receives 990 SER
        assertEq(ser.balanceOf(dexRouter), 990 ether);
        assertEq(ser.balanceOf(treasury), 5 ether);

        // Now Treasury marks dexRouter as taxExempt
        vm.prank(treasury);
        ser.setTaxExempt(dexRouter, true);
        assertTrue(ser.taxExempt(dexRouter));

        // Alice sends another 1000 SER to dexRouter -> 0% tax
        vm.prank(alice);
        ser.transfer(dexRouter, 1000 ether);
        assertEq(ser.balanceOf(dexRouter), 1990 ether); // exact +1000 SER

        // Non-treasury cannot set taxExempt
        vm.prank(alice);
        vm.expectRevert("SeraphToken: caller is not treasury");
        ser.setTaxExempt(alice, true);
    }

    /* ------------------------------------------------------------------ */
    /* PrivacyPool Pause Circuit Breaker Tests                            */
    /* ------------------------------------------------------------------ */

    function test_PrivacyPool_PauseBlocksShieldTransferUnshield() public {
        bytes32 commitment = keccak256("test_commitment");
        bytes32 root = pool.getLastRoot();
        bytes32 nullifier = keccak256("test_nullifier");

        // Treasury pauses pool
        vm.prank(treasury);
        pool.setPaused(true);
        assertTrue(pool.paused());

        // Shield reverts
        vm.startPrank(alice);
        ser.approve(address(pool), 100 ether);
        vm.expectRevert("PrivacyPool: paused");
        pool.shield(100 ether, commitment, "");

        // Private transfer reverts
        bytes32[] memory nullifiers = new bytes32[](1);
        nullifiers[0] = nullifier;
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = commitment;
        vm.expectRevert("PrivacyPool: paused");
        pool.privateTransfer(nullifiers, commitments, root, "");

        // Unshield reverts
        vm.expectRevert("PrivacyPool: paused");
        pool.unshield(nullifier, 100 ether, alice, root, "");
        vm.stopPrank();

        // Non-treasury cannot pause/unpause
        vm.prank(alice);
        vm.expectRevert("PrivacyPool: not treasury");
        pool.setPaused(false);

        // Treasury unpauses pool
        vm.prank(treasury);
        pool.setPaused(false);
        assertFalse(pool.paused());

        // Now shield succeeds cleanly
        vm.prank(alice);
        pool.shield(100 ether, commitment, "");
        assertEq(ser.balanceOf(address(pool)), 100 ether);
    }

    /* ------------------------------------------------------------------ */
    /* CrossEVMBridge Pause Circuit Breaker Tests                         */
    /* ------------------------------------------------------------------ */

    function test_CrossEVMBridge_PauseBlocksBridgeOperations() public {
        // Guardian pauses bridge
        vm.prank(guardian);
        bridge.setPaused(true);
        assertTrue(bridge.paused());

        // Bridge out reverts
        vm.startPrank(alice);
        ser.approve(address(bridge), 50 ether);
        vm.expectRevert(CrossEVMBridge.BridgePaused.selector);
        bridge.bridgeOut(bob, 50 ether, REMOTE_CHAIN);
        vm.stopPrank();

        // Submit state batch reverts
        vm.deal(alice, 5 ether);
        vm.startPrank(alice);
        bridge.bondRelayer{value: 2 ether}();
        vm.expectRevert(CrossEVMBridge.BridgePaused.selector);
        bridge.submitStateBatch(REMOTE_CHAIN, keccak256("state_root"));
        vm.stopPrank();

        // Non-guardian cannot pause/unpause
        vm.prank(alice);
        vm.expectRevert(CrossEVMBridge.Unauthorized.selector);
        bridge.setPaused(false);

        // Guardian unpauses bridge
        vm.prank(guardian);
        bridge.setPaused(false);
        assertFalse(bridge.paused());

        // Now bridgeOut succeeds
        vm.startPrank(alice);
        bridge.bridgeOut(bob, 50 ether, REMOTE_CHAIN);
        vm.stopPrank();
        assertEq(ser.balanceOf(address(bridge)), 50 ether);
    }
}

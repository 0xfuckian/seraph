// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/bridges/CrossEVMBridge.sol";
import "../core/gas/GasRelayer.sol";
import "../modules/messaging/InvoiceRegistry.sol";
import "../modules/ai_payments/UsageVault.sol";
import "../modules/stablecoin/CollateralVault.sol";
import "./MockERC20.sol";

contract ProtocolModulesTest is Test {
    SeraphToken public ser;
    MockERC20 public wxmr;

    CrossEVMBridge public bridge;
    GasRelayer public gasRelayer;
    InvoiceRegistry public invoices;
    UsageVault public aiVault;
    CollateralVault public cdpVault;

    address public treasury = makeAddr("treasury");
    address public guardian = makeAddr("guardian");
    address public relayer = makeAddr("relayer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    bytes32 public constant SERAPH_EVM_ID = keccak256("SERAPH_EVM");
    bytes32 public constant XMR_EVM_ID = keccak256("XMR_EVM");

    function setUp() public {
        ser = new SeraphToken(address(0), treasury, address(0));
        vm.prank(treasury);
        ser.setSellTaxEnabled(false);

        wxmr = new MockERC20("Wrapped XMR", "wXMR", 18, 0);

        bridge = new CrossEVMBridge(address(ser), SERAPH_EVM_ID, guardian);
        vm.prank(treasury);
        ser.setMinter(address(bridge), true);

        gasRelayer = new GasRelayer(address(ser), address(wxmr), 1000e18, 10e18);
        invoices = new InvoiceRegistry();
        aiVault = new UsageVault(address(ser));
        cdpVault = new CollateralVault(address(ser), 2e18); // $2.00 per SER

        vm.prank(treasury);
        ser.mint(alice, 100_000e18);
        wxmr.mint(alice, 100e18);
        vm.deal(relayer, 10 ether);
    }

    function test_CrossEVMBridge_BondBatchClaimAndSlash() public {
        vm.prank(relayer);
        bridge.bondRelayer{value: 1 ether}();

        bytes32 nullifier = keccak256("bridge_note_1");
        uint256 amount = 500e18;
        bytes32 leaf = keccak256(abi.encodePacked(nullifier, bob, amount, SERAPH_EVM_ID));

        vm.prank(relayer);
        uint256 batchId = bridge.submitStateBatch(XMR_EVM_ID, leaf);

        bytes32[] memory emptyProof = new bytes32[](0);

        // Cannot claim before challenge window passes
        vm.expectRevert(CrossEVMBridge.ChallengeWindowActive.selector);
        bridge.claimBridged(batchId, nullifier, bob, amount, emptyProof);

        vm.warp(block.timestamp + 1 hours + 1);
        bridge.claimBridged(batchId, nullifier, bob, amount, emptyProof);
        assertEq(ser.balanceOf(bob), amount);

        // Replay must revert
        vm.expectRevert(CrossEVMBridge.NullifierAlreadyUsed.selector);
        bridge.claimBridged(batchId, nullifier, bob, amount, emptyProof);

        // Fraudulent batch gets challenged and slashes relayer bond
        vm.prank(relayer);
        uint256 badBatch = bridge.submitStateBatch(XMR_EVM_ID, keccak256("bad_root"));
        uint256 aliceEthBefore = alice.balance;
        vm.prank(guardian);
        bridge.challengeBatch(badBatch, alice);
        assertEq(alice.balance - aliceEthBefore, 1 ether);
        assertEq(bridge.relayerBonds(relayer), 0);
    }

    function test_GasRelayer_PayInXMR() public {
        bytes32 voucherCommit = keccak256("voucher_1");
        bytes32 voucherNullifier = keccak256("voucher_nullifier_1");

        vm.startPrank(alice);
        wxmr.approve(address(gasRelayer), 1e18);
        gasRelayer.fundGasVoucher(address(wxmr), 1e18, voucherCommit);
        vm.stopPrank();

        bytes memory callData = abi.encodeWithSelector(
            InvoiceRegistry.sendEncryptedMessage.selector,
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            bytes("encrypted_hello")
        );

        vm.prank(relayer);
        gasRelayer.executeWithGasAbstraction(voucherNullifier, address(wxmr), 0.25e18, address(invoices), callData);

        assertEq(wxmr.balanceOf(relayer), 0.25e18);
    }

    function test_InvoiceRegistry_CreateAndSettle() public {
        bytes32 invId = keccak256("inv_001");
        vm.prank(bob);
        invoices.createInvoice(invId, keccak256("stealth_bob"), bob, address(ser), 250e18, hex"deadbeef");

        vm.startPrank(alice);
        ser.approve(address(invoices), 250e18);
        invoices.settleInvoice(invId, keccak256("pay_nullifier_001"));
        vm.stopPrank();

        assertEq(ser.balanceOf(bob), 250e18);
    }

    function test_AIUsageVault_UnlinkableTicketRedemption() public {
        bytes32 secret = keccak256("agent_secret_key");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.startPrank(alice);
        ser.approve(address(aiVault), 1000e18);
        aiVault.depositCredits(commitment, 1000e18);
        vm.stopPrank();

        bytes32 ticketNullifier = keccak256("ticket_1");
        vm.prank(bob); // Bob is the AI compute provider
        aiVault.redeemUsageTicket(commitment, ticketNullifier, 300e18, secret);

        vm.prank(bob);
        uint256 claimed = aiVault.claimEarnings();
        assertEq(claimed, 300e18);
        assertEq(ser.balanceOf(bob), 300e18);
        assertEq(aiVault.creditCommitments(commitment), 700e18);
    }

    function test_CollateralVault_MintAndBurnPrivateStablecoin() public {
        // Alice deposits 1,500 SER ($3,000 value at $2/SER) and mints 2,000 xUSD (150% CR)
        vm.startPrank(alice);
        ser.approve(address(cdpVault), 1500e18);
        cdpVault.depositAndMint(1500e18, 2000e18);
        assertEq(cdpVault.xUSD().balanceOf(alice), 2000e18);

        // Minting 1 more wei of xUSD exceeds 150% CR and reverts
        vm.expectRevert(CollateralVault.InsufficientCollateralRatio.selector);
        cdpVault.depositAndMint(0, 1);

        // Burn 2,000 xUSD and withdraw all 1,500 SER
        cdpVault.burnAndWithdraw(2000e18, 1500e18);
        vm.stopPrank();

        assertEq(cdpVault.xUSD().balanceOf(alice), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../modules/messaging/InvoiceRegistry.sol";
import "./MockERC20.sol";

contract InvoiceRegistryDeepTest is Test {
    SeraphToken public ser;
    MockERC20 public wxmr;
    InvoiceRegistry public registry;

    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    event EncryptedMessageSent(bytes32 indexed recipientPubkey, bytes32 indexed ephemeralPubkey, bytes ciphertext);
    event InvoiceCreated(bytes32 indexed invoiceId, bytes32 indexed stealthRecipient, address token, uint256 amount);
    event InvoiceSettled(bytes32 indexed invoiceId, bytes32 indexed paymentNullifier, uint256 amount);

    function setUp() public {
        ser = new SeraphToken(address(0), treasury, address(0));
        vm.prank(treasury);
        ser.setSellTaxEnabled(false);

        wxmr = new MockERC20("Wrapped XMR", "wXMR", 18, 0);
        registry = new InvoiceRegistry();

        // Mint tokens to payers
        vm.prank(treasury);
        ser.mint(alice, 100_000e18);
        wxmr.mint(alice, 100_000e18);

        vm.prank(treasury);
        ser.mint(carol, 100_000e18);
        wxmr.mint(carol, 100_000e18);
    }

    /* ========================================================================= */
    /* 1. INVOICE CREATION WITH STEALTH RECIPIENT & ENCRYPTED MEMO               */
    /* ========================================================================= */

    function test_CreateInvoice_SuccessWithEncryptedMemo() public {
        bytes32 invoiceId = keccak256("invoice_ser_001");
        bytes32 stealthRecipient = keccak256("stealth_pubkey_bob");
        address claimAddr = bob;
        address token = address(ser);
        uint256 amount = 1_500e18;
        bytes memory encryptedMemo = hex"0123456789abcdefa1b2c3d4e5f60718293a4b5c6d7e8f";

        vm.expectEmit(true, true, false, true);
        emit InvoiceCreated(invoiceId, stealthRecipient, token, amount);

        vm.prank(bob);
        registry.createInvoice(invoiceId, stealthRecipient, claimAddr, token, amount, encryptedMemo);

        (
            bytes32 storedStealthRecipient,
            address storedClaimAddr,
            address storedToken,
            uint256 storedAmount,
            bool storedSettled,
            bytes memory storedMemo
        ) = registry.invoices(invoiceId);

        assertEq(storedStealthRecipient, stealthRecipient);
        assertEq(storedClaimAddr, claimAddr);
        assertEq(storedToken, token);
        assertEq(storedAmount, amount);
        assertFalse(storedSettled);
        assertEq(storedMemo, encryptedMemo);
    }

    function test_CreateInvoice_DifferentMemoSizes() public {
        // Case A: Empty memo
        bytes32 idA = keccak256("invoice_empty_memo");
        registry.createInvoice(idA, keccak256("stealth_a"), bob, address(ser), 10e18, "");
        (, , , , , bytes memory memoA) = registry.invoices(idA);
        assertEq(memoA.length, 0);

        // Case B: Large 1KB encrypted memo
        bytes memory largeMemo = new bytes(1024);
        for (uint256 i = 0; i < 1024; i++) {
            largeMemo[i] = bytes1(uint8(i % 256));
        }

        bytes32 idB = keccak256("invoice_large_memo");
        registry.createInvoice(idB, keccak256("stealth_b"), bob, address(wxmr), 50e18, largeMemo);
        (, , , , , bytes memory memoB) = registry.invoices(idB);
        assertEq(memoB.length, 1024);
        assertEq(keccak256(memoB), keccak256(largeMemo));
    }

    function test_CreateInvoice_DuplicateId_Reverts() public {
        bytes32 invoiceId = keccak256("duplicate_invoice");
        registry.createInvoice(invoiceId, keccak256("stealth_1"), bob, address(ser), 100e18, hex"aa");

        // Attempting to re-create same invoice ID reverts
        vm.expectRevert(InvoiceRegistry.InvoiceExists.selector);
        registry.createInvoice(invoiceId, keccak256("stealth_2"), carol, address(wxmr), 200e18, hex"bb");
    }

    function test_CreateInvoice_InvalidParameters_Reverts() public {
        bytes32 validId = keccak256("valid_id");

        // Zero invoiceId
        vm.expectRevert("InvoiceRegistry: invalid invoice");
        registry.createInvoice(bytes32(0), keccak256("stealth"), bob, address(ser), 100e18, hex"aa");

        // Zero amount
        vm.expectRevert("InvoiceRegistry: invalid invoice");
        registry.createInvoice(validId, keccak256("stealth"), bob, address(ser), 0, hex"aa");

        // Zero claimAddr
        vm.expectRevert("InvoiceRegistry: invalid invoice");
        registry.createInvoice(validId, keccak256("stealth"), address(0), address(ser), 100e18, hex"aa");

        // Zero token
        vm.expectRevert("InvoiceRegistry: invalid invoice");
        registry.createInvoice(validId, keccak256("stealth"), bob, address(0), 100e18, hex"aa");
    }

    /* ========================================================================= */
    /* 2. PAYMENT SETTLEMENT & NULLIFIER ENFORCEMENT                             */
    /* ========================================================================= */

    function test_SettleInvoice_SER_Success() public {
        bytes32 invoiceId = keccak256("ser_invoice_settle");
        bytes32 nullifier = keccak256("nullifier_ser_01");
        uint256 amount = 500e18;

        registry.createInvoice(invoiceId, keccak256("stealth_bob"), bob, address(ser), amount, hex"cafebabe");

        uint256 aliceBalBefore = ser.balanceOf(alice);
        uint256 bobBalBefore = ser.balanceOf(bob);

        vm.startPrank(alice);
        ser.approve(address(registry), amount);

        vm.expectEmit(true, true, false, true);
        emit InvoiceSettled(invoiceId, nullifier, amount);

        registry.settleInvoice(invoiceId, nullifier);
        vm.stopPrank();

        // Balances verified
        assertEq(ser.balanceOf(alice), aliceBalBefore - amount);
        assertEq(ser.balanceOf(bob), bobBalBefore + amount);

        // State verified
        (, , , , bool settled, ) = registry.invoices(invoiceId);
        assertTrue(settled);
        assertTrue(registry.usedPaymentNullifiers(nullifier));
    }

    function test_SettleInvoice_WXMR_Success() public {
        bytes32 invoiceId = keccak256("wxmr_invoice_settle");
        bytes32 nullifier = keccak256("nullifier_wxmr_01");
        uint256 amount = 25e18;

        registry.createInvoice(invoiceId, keccak256("stealth_bob"), bob, address(wxmr), amount, hex"feedbeef");

        uint256 aliceBalBefore = wxmr.balanceOf(alice);
        uint256 bobBalBefore = wxmr.balanceOf(bob);

        vm.startPrank(alice);
        wxmr.approve(address(registry), amount);

        vm.expectEmit(true, true, false, true);
        emit InvoiceSettled(invoiceId, nullifier, amount);

        registry.settleInvoice(invoiceId, nullifier);
        vm.stopPrank();

        assertEq(wxmr.balanceOf(alice), aliceBalBefore - amount);
        assertEq(wxmr.balanceOf(bob), bobBalBefore + amount);

        (, , , , bool settled, ) = registry.invoices(invoiceId);
        assertTrue(settled);
        assertTrue(registry.usedPaymentNullifiers(nullifier));
    }

    function test_SettleInvoice_DuplicateSettlementWithNewNullifier_Reverts() public {
        bytes32 invoiceId = keccak256("settle_twice_test");
        bytes32 nullifier1 = keccak256("nullifier_1");
        bytes32 nullifier2 = keccak256("nullifier_2");
        uint256 amount = 100e18;

        registry.createInvoice(invoiceId, keccak256("stealth_bob"), bob, address(ser), amount, hex"01");

        vm.startPrank(alice);
        ser.approve(address(registry), amount * 2);
        registry.settleInvoice(invoiceId, nullifier1);

        // Attempting to settle again with a fresh nullifier reverts AlreadySettled
        vm.expectRevert(InvoiceRegistry.AlreadySettled.selector);
        registry.settleInvoice(invoiceId, nullifier2);
        vm.stopPrank();
    }

    function test_SettleInvoice_ReplayNullifierAcrossDifferentInvoices_Reverts() public {
        bytes32 inv1 = keccak256("inv_cross_1");
        bytes32 inv2 = keccak256("inv_cross_2");
        bytes32 sharedNullifier = keccak256("shared_nullifier");
        uint256 amount = 50e18;

        registry.createInvoice(inv1, keccak256("stealth_bob"), bob, address(ser), amount, hex"01");
        registry.createInvoice(inv2, keccak256("stealth_carol"), carol, address(ser), amount, hex"02");

        // Alice settles inv1 with sharedNullifier
        vm.startPrank(alice);
        ser.approve(address(registry), amount);
        registry.settleInvoice(inv1, sharedNullifier);
        vm.stopPrank();

        // Carol attempts to settle inv2 using the same sharedNullifier -> MUST REVERT NullifierAlreadyUsed
        vm.startPrank(carol);
        ser.approve(address(registry), amount);
        vm.expectRevert(InvoiceRegistry.NullifierAlreadyUsed.selector);
        registry.settleInvoice(inv2, sharedNullifier);
        vm.stopPrank();
    }

    function test_SettleInvoice_ZeroNullifier_Reverts() public {
        bytes32 invoiceId = keccak256("inv_zero_nullifier");
        registry.createInvoice(invoiceId, keccak256("stealth"), bob, address(ser), 100e18, hex"01");

        vm.startPrank(alice);
        ser.approve(address(registry), 100e18);
        vm.expectRevert(InvoiceRegistry.NullifierAlreadyUsed.selector);
        registry.settleInvoice(invoiceId, bytes32(0));
        vm.stopPrank();
    }

    function test_SettleInvoice_UnknownInvoice_Reverts() public {
        bytes32 nonExistentId = keccak256("non_existent_invoice");
        vm.startPrank(alice);
        ser.approve(address(registry), 100e18);
        vm.expectRevert(InvoiceRegistry.UnknownInvoice.selector);
        registry.settleInvoice(nonExistentId, keccak256("nullifier"));
        vm.stopPrank();
    }

    function test_SettleInvoice_InsufficientAllowanceOrBalance_Reverts() public {
        bytes32 invoiceId = keccak256("insufficient_funds_inv");
        registry.createInvoice(invoiceId, keccak256("stealth"), bob, address(ser), 1_000e18, hex"01");

        // Alice approves only 500e18
        vm.startPrank(alice);
        ser.approve(address(registry), 500e18);
        vm.expectRevert();
        registry.settleInvoice(invoiceId, keccak256("nullifier_underapproved"));
        vm.stopPrank();

        // Account with 0 balance
        address poorGuy = makeAddr("poorGuy");
        vm.startPrank(poorGuy);
        ser.approve(address(registry), 1_000e18);
        vm.expectRevert();
        registry.settleInvoice(invoiceId, keccak256("nullifier_nobalance"));
        vm.stopPrank();
    }

    /* ========================================================================= */
    /* 3. ENCRYPTED MESSAGING ACROSS 20 SIMULATED ACCOUNTS                        */
    /* ========================================================================= */

    function test_SendEncryptedMessage_Across20SimulatedAccounts() public {
        for (uint256 i = 1; i <= 20; i++) {
            bytes32 recipientPubkey = keccak256(abi.encodePacked("recipient_account_", i));
            bytes32 ephemeralPubkey = keccak256(abi.encodePacked("ephemeral_key_", i, block.timestamp));

            // Generate payload of size (16 + i * 8) bytes with arbitrary pseudo-random patterns
            uint256 payloadSize = 16 + (i * 8);
            bytes memory payload = new bytes(payloadSize);
            for (uint256 j = 0; j < payloadSize; j++) {
                payload[j] = bytes1(uint8((i * 17 + j * 31) % 256));
            }

            address sender = address(uint160(uint256(keccak256(abi.encodePacked("sender", i)))));

            vm.expectEmit(true, true, false, true);
            emit EncryptedMessageSent(recipientPubkey, ephemeralPubkey, payload);

            vm.prank(sender);
            registry.sendEncryptedMessage(recipientPubkey, ephemeralPubkey, payload);
        }
    }

    function test_SendEncryptedMessage_MultipleMessagesSameRecipient() public {
        bytes32 recipientPubkey = keccak256("stealth_viewkey_bob");

        // Send 5 sequential encrypted messages to the same recipient with different payloads
        for (uint256 i = 0; i < 5; i++) {
            bytes32 ephemeralPubkey = keccak256(abi.encodePacked("ephemeral", i));
            bytes memory message = abi.encodePacked("Secret message #", i, " for Bob's eyes only");

            vm.expectEmit(true, true, false, true);
            emit EncryptedMessageSent(recipientPubkey, ephemeralPubkey, message);

            registry.sendEncryptedMessage(recipientPubkey, ephemeralPubkey, message);
        }
    }

    function test_SendEncryptedMessage_InvalidParameters_Reverts() public {
        bytes32 validRecipient = keccak256("valid_recipient");
        bytes32 validEphemeral = keccak256("valid_ephemeral");
        bytes memory validPayload = hex"aabbcc";

        // Zero recipientPubkey reverts
        vm.expectRevert("InvoiceRegistry: invalid message");
        registry.sendEncryptedMessage(bytes32(0), validEphemeral, validPayload);

        // Empty ciphertext reverts
        vm.expectRevert("InvoiceRegistry: invalid message");
        registry.sendEncryptedMessage(validRecipient, validEphemeral, "");

        // Zero ephemeralPubkey is permitted if recipient and ciphertext are valid
        vm.expectEmit(true, true, false, true);
        emit EncryptedMessageSent(validRecipient, bytes32(0), validPayload);
        registry.sendEncryptedMessage(validRecipient, bytes32(0), validPayload);
    }
}

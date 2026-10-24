// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title InvoiceRegistry
 * @notice First-party Seraph module for Private Messaging + Payments (Whitepaper Section 7).
 *         Supports encrypted view-key memos, stealth tips, and invoice settlement in SER or wXMR.
 */
contract InvoiceRegistry is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Invoice {
        bytes32 stealthRecipient;
        address claimAddr;
        address token;
        uint256 amount;
        bool settled;
        bytes encryptedMemo;
    }

    mapping(bytes32 => Invoice) public invoices;
    mapping(bytes32 => bool) public usedPaymentNullifiers;

    event EncryptedMessageSent(bytes32 indexed recipientPubkey, bytes32 indexed ephemeralPubkey, bytes ciphertext);
    event InvoiceCreated(bytes32 indexed invoiceId, bytes32 indexed stealthRecipient, address token, uint256 amount);
    event InvoiceSettled(bytes32 indexed invoiceId, bytes32 indexed paymentNullifier, uint256 amount);

    error InvoiceExists();
    error UnknownInvoice();
    error AlreadySettled();
    error NullifierAlreadyUsed();

    /**
     * @notice Broadcast an encrypted message to `recipientPubkey` (scannable via IncomingViewKey).
     */
    function sendEncryptedMessage(
        bytes32 recipientPubkey,
        bytes32 ephemeralPubkey,
        bytes calldata ciphertext
    ) external {
        require(recipientPubkey != bytes32(0) && ciphertext.length > 0, "InvoiceRegistry: invalid message");
        emit EncryptedMessageSent(recipientPubkey, ephemeralPubkey, ciphertext);
    }

    /**
     * @notice Register a stealth-addressed invoice with an encrypted memo.
     */
    function createInvoice(
        bytes32 invoiceId,
        bytes32 stealthRecipient,
        address claimAddr,
        address token,
        uint256 amount,
        bytes calldata encryptedMemo
    ) external {
        if (invoices[invoiceId].amount != 0) revert InvoiceExists();
        require(invoiceId != bytes32(0) && amount > 0 && claimAddr != address(0) && token != address(0), "InvoiceRegistry: invalid invoice");

        invoices[invoiceId] = Invoice({
            stealthRecipient: stealthRecipient,
            claimAddr: claimAddr,
            token: token,
            amount: amount,
            settled: false,
            encryptedMemo: encryptedMemo
        });
        emit InvoiceCreated(invoiceId, stealthRecipient, token, amount);
    }

    /**
     * @notice Settle an invoice with ERC-20 tokens (SER / wXMR) and emit a payment nullifier receipt.
     */
    function settleInvoice(bytes32 invoiceId, bytes32 paymentNullifier) external nonReentrant {
        Invoice storage inv = invoices[invoiceId];
        if (inv.amount == 0) revert UnknownInvoice();
        if (inv.settled) revert AlreadySettled();
        if (paymentNullifier == bytes32(0) || usedPaymentNullifiers[paymentNullifier]) revert NullifierAlreadyUsed();

        inv.settled = true;
        usedPaymentNullifiers[paymentNullifier] = true;
        IERC20(inv.token).safeTransferFrom(msg.sender, inv.claimAddr, inv.amount);
        emit InvoiceSettled(invoiceId, paymentNullifier, inv.amount);
    }
}

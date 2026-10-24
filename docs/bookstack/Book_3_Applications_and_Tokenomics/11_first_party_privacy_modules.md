# Chapter 11: First-Party Privacy Modules

## 11.1 The Ecosystem of First-Party Privacy Modules

Seraph extends beyond simple token transfers by providing an integrated suite of native, first-party privacy applications deployed directly on the confidential EVMs:

```
                            FIRST-PARTY PRIVACY MODULES
   ┌───────────────────────┐   ┌───────────────────────┐   ┌───────────────────────┐
   │    CollateralVault    │   │      UsageVault       │   │    InvoiceRegistry    │
   ├───────────────────────┤   ├───────────────────────┤   ├───────────────────────┤
   │ • Mint private `xUSD` │   │ • Autonomous AI Agent │   │ • Stealth Invoicing   │
   │ • Over-collateralized │   │   Compute Streaming   │   │ • Encrypted Memos     │
   │   CDP with SER / XMR  │   │ • Unlinkable One-Time │   │ • Cryptographic Claim │
   │ • 150% Health Ratio   │   │   Usage Tickets       │   │   Settlements         │
   └───────────────────────┘   └───────────────────────┘   └───────────────────────┘
```

---

## 11.2 Private Stablecoins: `xUSD` & `CollateralVault`

Volatility in crypto assets makes everyday commerce difficult. The `CollateralVault` enables users to lock SER or XMR collateral and mint **`xUSD`**—a confidential, decentralized dollar stablecoin.

### Mechanics & Invariants:
1. **Minimum Collateralization Ratio (150%)**:
   $$\text{Collateral Ratio} = \frac{\text{Collateral} \times \text{Price}_{\text{USD}}}{\text{Debt}_{\text{xUSD}}} \ge 150\%$$
2. **Deposit & Mint**:
   ```solidity
   function depositAndMint(
       uint256 collateralAmount,
       uint256 mintAmount
   ) external nonReentrant;
   ```
   Users deposit collateral and mint synthetic `xUSD` directly into their private balances.
3. **Burn & Withdraw**:
   ```solidity
   function burnAndWithdraw(
       uint256 burnAmount,
       uint256 withdrawCollateral
   ) external nonReentrant;
   ```
   Users burn `xUSD` to unlock their underlying collateral, maintaining the 150% ratio.
4. **Confidential Circulation**: Once minted, `xUSD` can be shielded and transferred through the `PrivacyPool` with zero public record of sender, recipient, or balance.

---

## 11.3 Autonomous AI Agent Billing: `UsageVault`

As autonomous AI agents, machine learning inference nodes, and cloud compute clusters transact on-chain, they require high-frequency, low-latency, unlinkable micro-payments without exposing corporate infrastructure budgets.

The `UsageVault` implements **cryptographic one-time usage tickets**:

```
 Client / AI Agent                                 UsageVault Contract                             AI Compute Provider
        │                                                   │                                               │
        │ 1. Deposits credits (`depositCredits`)            │                                               │
        │    Commitment = H(amount, secretPreimage)         │                                               │
        ├──────────────────────────────────────────────────>│                                               │
        │                                                   │                                               │
        │ 2. Sends one-time ticket off-chain to Provider   │                                               │
        │    (ticketNullifier = H(secretPreimage), amount)  │                                               │
        │ ──────────────────────────────────────────────────┼──────────────────────────────────────────────>│
        │                                                   │                                               │
        │                                                   │ 3. Redeems ticket (`redeemUsageTicket`)       │
        │                                                   │    Verifies H(amount, secret) == commitment   │
        │                                                   │ <─────────────────────────────────────────────│
        │                                                   │                                               │
        │                                                   │ 4. Withdraws provider revenue                 │
        │                                                   │    (`claimEarnings`)                          │
```

### SDK Integration:
```typescript
import { createCreditDeposit, UsageVaultClient } from "@seraph-protocol/sdk";

// 1. Create unlinkable credit ticket
const secretPreimage = randomBytes32();
const ticket = createCreditDeposit(100n * 10n**18n, secretPreimage);

// 2. Deposit into vault
const client = new UsageVaultClient(vaultAddress);
const tx = client.encodeDeposit(ticket.commitment, 100n * 10n**18n);
```

---

## 11.4 Stealth Invoicing & Encrypted Messaging: `InvoiceRegistry`

The `InvoiceRegistry` contract solves privacy for merchant invoicing and peer-to-peer business transactions:

### 1. Invoice Creation
```solidity
function createInvoice(
    bytes32 invoiceId,
    bytes32 stealthRecipient,
    address claimAddr,
    address token,
    uint256 amount,
    bytes calldata encryptedMemo
) external nonReentrant;
```
- The merchant publishes an invoice bound to a stealth destination address.
- The memo (specifying goods, order ID, or service description) is encrypted under the buyer's view key.

### 2. Settle & Nullify
```solidity
function settleInvoice(
    bytes32 invoiceId,
    bytes32 paymentNullifier
) external nonReentrant;
```
- When the payment is executed, the `paymentNullifier` is permanently recorded.
- Replaying payments across different invoices is strictly prevented (`NullifierAlreadyUsed`).

### 3. End-to-End Encrypted Messaging
Users can broadcast encrypted messages to any recipient's public key:
```solidity
function sendEncryptedMessage(
    bytes32 recipientPubkey,
    bytes32 ephemeralPubkey,
    bytes calldata ciphertext
) external;
```
This enables native on-chain communication for trade negotiations, OTC settlement confirmations, and payment notices.

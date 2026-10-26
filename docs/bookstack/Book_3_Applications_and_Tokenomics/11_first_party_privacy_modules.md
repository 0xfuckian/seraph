# Chapter 11: First-Party Privacy Modules

## 11.1 The Ecosystem of First-Party Privacy Modules

Seraph extends beyond simple token transfers by providing an integrated suite of native, first-party privacy applications deployed directly on the confidential EVMs:

```
                            FIRST-PARTY PRIVACY MODULES
   +-----------------------+   +-----------------------+   +-----------------------+
   |    CollateralVault    |   |      UsageVault       |   |    InvoiceRegistry    |
   +-----------------------+   +-----------------------+   +-----------------------+
   | - Mint private xUSD   |   | - Autonomous AI Agent |   | - Stealth Invoicing   |
   | - Over-collateralized |   |   Compute Streaming   |   | - Encrypted Memos     |
   |   CDP with SER / XMR  |   | - Unlinkable One-Time |   | - Atomic Token Pull   |
   | - 150% Health Ratio   |   |   Usage Tickets       |   |   Settlements         |
   +-----------------------+   +-----------------------+   +-----------------------+
```

---

## 11.2 Private Stablecoins: `xUSD` & `CollateralVault`

Volatility in crypto assets makes everyday commerce difficult. The `CollateralVault` enables users to lock SER or XMR collateral and mint **`xUSD`**—a confidential, decentralized dollar stablecoin.

### Phase 0 Sandbox Deployment:
- **Minimum Collateralization Ratio (150%)**:
  `Collateral Ratio = (Collateral * Price_USD) / Debt_xUSD >= 150%`
- **Deposit & Mint**:
  ```solidity
  function depositAndMint(
      uint256 collateralAmount,
      uint256 mintAmount
  ) external nonReentrant;
  ```
  Users deposit collateral and mint synthetic `xUSD` directly into their balances.
- **Burn & Withdraw**:
  ```solidity
  function burnAndWithdraw(
      uint256 burnAmount,
      uint256 withdrawCollateral
  ) external nonReentrant;
  ```
  Users burn `xUSD` to unlock underlying collateral, preserving the 150% ratio.
- **Price Feed**: In Phase 0, `collateralPriceUsd` is calibrated by governance via `setCollateralPrice`.

### Production Roadmap (Phase 2/3):
1. **Decentralized Oracles**: Integration of dual push/pull oracles (Pyth Network and Chainlink Data Feeds) with TWAP smoothing.
2. **Liquidation Engine**:
   - **Liquidation Threshold**: 130% collateralization ratio.
   - **Liquidation Bonus**: 10% discount on liquidated collateral paid to liquidator bots.
   - **Stability Fees**: Algorithmic borrowing interest rate adjusted to maintain dollar parity.
3. **Confidential Circulation**: Once minted, `xUSD` can be shielded and transferred through the `PrivacyPool` with zero public record of sender, recipient, or balance.

---

## 11.3 Autonomous AI Agent Billing: `UsageVault`

As autonomous AI agents, machine learning inference nodes, and cloud compute clusters transact on-chain, they require high-frequency, low-latency, unlinkable micro-payments without exposing corporate infrastructure budgets.

The `UsageVault` implements **cryptographic one-time usage tickets**:

```
 Client / AI Agent                                 UsageVault Contract                             AI Compute Provider
        |                                                   |                                               |
        | 1. Deposits credits (depositCredits)              |                                               |
        |    Commitment = H(amount, secretPreimage)         |                                               |
        +-------------------------------------------------->|                                               |
        |                                                   |                                               |
        | 2. Sends one-time ticket off-chain to Provider   |                                               |
        |    (ticketNullifier = H(secretPreimage), amount)  |                                               |
        | --------------------------------------------------+---------------------------------------------->|
        |                                                   |                                               |
        |                                                   | 3. Redeems ticket (redeemUsageTicket)         |
        |                                                   |    Verifies H(amount, secret) == commitment   |
        |                                                   | <---------------------------------------------+
        |                                                   |                                               |
        |                                                   | 4. Withdraws provider revenue                 |
        |                                                   |    (claimEarnings)                            |
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

The `InvoiceRegistry` contract (`contracts/modules/messaging/InvoiceRegistry.sol`) provides merchant invoicing and peer-to-peer business transactions:

### 1. Invoice Creation
```solidity
function createInvoice(
    bytes32 invoiceId,
    bytes32 stealthRecipient,
    address claimAddr,
    address token,
    uint256 amount,
    bytes calldata encryptedMemo
) external;
```
- The merchant publishes an invoice bound to a stealth recipient identifier and a designated public claim address (`claimAddr`).
- The memo (specifying goods, order ID, or service terms) is encrypted under the buyer's view key.

### 2. Settle & Atomic Token Transfer
```solidity
function settleInvoice(
    bytes32 invoiceId,
    bytes32 paymentNullifier
) external nonReentrant;
```
- **Atomic Token Transfer**: The contract verifies that the invoice exists and is unsettled, then pulls the exact `inv.amount` of `inv.token` directly from `msg.sender` to `inv.claimAddr` via `IERC20(inv.token).safeTransferFrom(...)`.
- **Payment Nullifier**: Records `usedPaymentNullifiers[paymentNullifier] = true`, permanently preventing payment replays.
- **Verifiable Settlement**: Proves on-chain that the exact requested asset and quantity was paid, while the transaction memo remains encrypted.

### 3. End-to-End Encrypted Messaging
Users can broadcast encrypted messages to any recipient's public key:
```solidity
function sendEncryptedMessage(
    bytes32 recipientPubkey,
    bytes32 ephemeralPubkey,
    bytes calldata ciphertext
) external;
```
This enables on-chain communication for trade negotiations, OTC settlement confirmations, and payment notices.

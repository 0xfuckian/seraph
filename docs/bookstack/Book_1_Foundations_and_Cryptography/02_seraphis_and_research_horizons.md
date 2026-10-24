# Chapter 2: Seraphis, Jamtis & Research Horizons

## 2.1 Technical Distinction: Production Architecture vs. Research Horizons

> [!IMPORTANT]
> **Architectural Clarity**: The current production deployment of Seraph Protocol (including our Base Sepolia contracts, Rust base layer, and TypeScript SDK) operates on an **incremental Merkle tree of depth 20 ($2^{20} = 1,048,576$ notes)** with deterministic nullifier derivation and Groth16/PLONK zero-knowledge spend verification.
>
> **Seraphis**, **Jamtis**, and **FCMP++** represent next-generation cryptographic upgrade paths on our long-term research roadmap. They are not active in the current Phase 0 testnet contracts, but form the theoretical blueprint for Seraph Phase 4.

---

## 2.2 The Seraphis Model: Enotes and Separation of Concerns

Seraphis is a next-generation transaction protocol designed by koe for Monero. It fundamentally redesigns the UTXO concept into modular cryptographic objects called **electronic notes (enotes)**.

In legacy CryptoNote/Monero protocols, a single private key is entangled with:
1. Detecting incoming funds (scanning).
2. Proving balance ownership.
3. Signing spending authorization.

Seraphis separates these capabilities into distinct, non-overlapping keys:
```
                      MASTER SEED
                           │
       ┌───────────────────┼───────────────────┐
       ▼                   ▼                   ▼
  Spend Key           View Key           Scan Key
  (Authorizes         (Audits            (Identifies
   Outflows)           Amounts)           Inflows)
```

### The Structure of an Enote
An enote in Seraphis consists of:
1. **Value Commitment**: A Pedersen commitment $C = vH + rG$ concealing the value.
2. **One-Time Public Key**: Derived via stealth address protocols.
3. **Key Image Generator**: An elliptic curve point used specifically for nullifier creation, disentangled from the one-time address.

---

## 2.3 Jamtis: Hierarchical Address and Wallet Key Structure

Jamtis is the comprehensive wallet addressing standard designed to accompany Seraphis. Jamtis addresses are divided into specific key components:

$$\text{Jamtis Address} = (\mathcal{K}_{\text{spend}}, \mathcal{K}_{\text{view}}, \mathcal{K}_{\text{scan}})$$

### Advantages of Jamtis Wallet Hierarchies:
- **Fast Ledger Scanning**: A lightweight client or hardware wallet can delegate the scan key to a cloud scanning node without giving that node the ability to see transaction values or spend funds.
- **Selective Audit Keys**: An auditor can be given a read-only audit view key that sees transaction amounts for tax reconciliation, but cannot initiate transfers.
- **Delegated Proof Generation**: Zero-knowledge proof generation can be offloaded to untrusted high-performance server clusters using an ephemeral proving delegation key.

---

## 2.4 Balance and Membership Proofs in Seraphis

In Seraphis, a transaction is structured as an algebraic balance proof across three components:

1. **Membership Proofs**: Each input enote proves that it belongs to the valid set of unspent transaction outputs.
2. **Value Balance Proof**: Proves that:
   $$\sum_{i} C_{\text{in}}^{(i)} - \sum_{j} C_{\text{out}}^{(j)} - \text{Fee} \cdot H = 0$$
3. **Range Proofs**: Bulletproofs++ proving that each output value is non-negative and strictly bounded within $[0, 2^{64}-1]$.

---

## 2.5 How Seraph Adapts These Principles to the Base Layer

Seraph takes the core mathematical insights of Seraphis—particularly **modular key separation** and **unlinkable enote structures**—and adapts them into a high-performance EVM-compatible framework:

### 1. Dual View Keys in Production
Seraph ships today with separate **Incoming View Keys** (for scanning unspent notes) and **Outgoing View Keys** (for generating verifiable compliance disclosure packages).

```typescript
// Production SDK Key Separation (sdk/typescript/src/index.ts)
const keys = deriveWalletKeys(spendKey);
// keys.spendKey -> authorizes nullifier consumption
// keys.viewKey  -> scans and decrypts incoming note memos
// keys.pubkey   -> static identity for stealth address derivation
```

### 2. State-Tree Note Commitments
Rather than requiring global linear scans across the entire chain history, Seraph organizes all commitments into an indexed Merkle tree where inclusion proofs can be verified on-chain in constant time ($O(1)$) with zero storage bloat.

### 3. Native Multi-Asset Isolation
Unlike legacy systems designed around a single native asset, Seraph notes natively incorporate an `AssetId` domain tag:
$$\text{Commitment} = \text{Keccak256}(\text{AssetId} \mathbin{\Vert} \text{Amount} \mathbin{\Vert} \text{RecipientPubkey} \mathbin{\Vert} \text{Blinding})$$

This allows SER tokens, native XMR, and custom confidential assets to share the exact same anonymity pool without cross-asset substitution risk.

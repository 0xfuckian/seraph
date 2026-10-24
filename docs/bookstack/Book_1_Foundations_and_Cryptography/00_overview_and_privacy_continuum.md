# Chapter 0: Protocol Overview & The Privacy Continuum

## 0.1 Introduction: What Seraph Is

Seraph is a modular privacy protocol engineered to resolve the fundamental trilemma between **cryptographic privacy**, **programmable smart contracts**, and **regulatory auditability**. 

Historically, decentralized ledger architectures have been split into two mutually exclusive camps:
1. **UTXO-based Privacy Networks** (such as Monero): Offering peerless anonymity sets, confidential transaction values, and stealth unlinkability, but lacking Turing-complete contract execution and multi-token composability.
2. **Account-based Smart Contract Platforms** (such as Ethereum and EVM rollups): Offering rich programmable composability, decentralized finance (DeFi), and autonomous application development, but exposing complete transaction graphs, account balances, and interaction histories to global surveillance and predatory MEV bots.

Seraph bridges this divide through a **four-level Privacy Continuum** anchored by a high-throughput, Monero-inspired base layer running alongside dual confidential Ethereum Virtual Machines (Seraph EVM and XMR EVM).

```
   ┌────────────────────────────────────────────────────────────────────────┐
   │                       THE PRIVACY CONTINUUM                            │
   └────────────────────────────────────────────────────────────────────────┘
     Level 0: Public EVM Execution (Transparent Auditability & Composability)
         │
         ▼ (approveAndShield)
     Level 1: Shielded Pool & Confidential Balances (Hidden Net Worth)
         │
         ▼ (privateTransfer)
     Level 2: Ephemeral Stealth Routing & Full Anonymity Set
         │
         ▼ (zk-EVM Precompiles)
     Level 3: Confidential Contract State & Homomorphic Private Settlement
```

---

## 0.2 The Privacy Continuum: Levels 0 to 3

Seraph recognizes that privacy is not a binary toggle, but a continuum where different economic activities demand different privacy assurances:

| Level | Name | Visibility | State Architecture | Primary Use Cases |
| :--- | :--- | :--- | :--- | :--- |
| **Level 0** | **Public EVM** | Sender, recipient, and amount fully public | Standard ERC-20 (`SERAPH.sol`) & EVM balance storage | DEX market liquidity, launchpad token discovery, public treasury accounting |
| **Level 1** | **Shielded Pool** | Balances hidden; deposit/withdraw events public | Merkle tree of Pedersen commitments (`PrivacyPool.sol`) | Long-term balance protection, wealth storage without exposing wallet balances |
| **Level 2** | **Full Stealth** | Sender, recipient, amount, and asset completely obfuscated | Depth-20 Incremental Merkle tree ($2^{20}$ capacity) + Nullifier registry | Private P2P payments, payroll settlement, dark pool order placement |
| **Level 3** | **Confidential Contracts** | Contract logic executed with encrypted state and zero-knowledge inputs | Dual Private EVMs with homomorphic precompiles & ZK proof verifiers | Private lending/CDP (`CollateralVault`), AI usage billing (`UsageVault`), sealed ballots |

### When Each Level Applies
- **Choose Level 0** when bootstrapping public liquidity on automated market makers (AMMs), interacting with third-party protocol contracts (e.g., Uniswap v3, Aave), or demonstrating provable balance solvency.
- **Choose Level 1** when storing capital long-term to prevent targeted spear-phishing and balance scraping, without disconnecting from the EVM ecosystem.
- **Choose Level 2** when conducting sensitive financial settlements between counterparties where neither party's transaction graph should be linked.
- **Choose Level 3** when executing stateful multiparty logic—such as streaming payments to autonomous AI agents, algorithmic market makers with hidden depth, or institutional credit facilities.

---

## 0.3 Who the Docs Are For

This documentation suite is organized into distinct tracks tailored to four primary stakeholder groups:

### 1. End Users & Privacy Advocates
- Understand the mechanics of shielding and unshielding tokens.
- Manage desktop, mobile, and web wallets safely.
- Learn how view keys protect privacy while allowing selective compliance disclosure.

### 2. Smart Contract & Frontend Developers
- Build privacy-preserving decentralized applications using standard Solidity.
- Integrate the `@seraph-protocol/sdk` TypeScript client and Rust base-layer bindings.
- Utilize on-chain precompiles for confidential state management, stealth addresses, and zero-knowledge verification.

### 3. Validators, Relayers & Node Operators
- Run full nodes and lightweight verification clients.
- Operate bonded relayers on the Cross-EVM Bridge and earn protocol routing fees.
- Participate in sequencer clusters and consensus validation.

### 4. Token Holders & Ecosystem Creators
- Review SER tokenomics, supply caps, and automatic fee burn mechanics.
- Participate in DAO governance proposals and confidential voting ballots.
- Deploy fair-launch bonding curve tokens with custom multi-way fee distributions using the Seraph Launchpad.

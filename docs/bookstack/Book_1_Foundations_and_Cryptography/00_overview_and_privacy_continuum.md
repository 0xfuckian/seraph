# Chapter 0: Protocol Overview & The Privacy Continuum

> **Document Status**: Production Manual v1.0.0 · Core EVM Privacy Contracts Shipped on Base Sepolia (Chain ID 84532) · Sovereign Base Layer PoC in Active R&D · Zero Mainnet Capital Permitted Prior to Formal External Audits.

---

## Document Front Matter & Deployment Specification

```
================================================================================
SERAPH PROTOCOL — TECHNICAL SPECIFICATION & ARCHITECTURAL MANUAL
Version:     v1.0.0-production-spec
Last Update: October 2026
Network:     Base Sepolia (Chain ID: 84532)
Repository:  https://github.com/0xfuckian/seraph
License:     MIT Open Source License
================================================================================
```

### Current Deployment vs. Target Architecture
- **Shipped & Tested on Base Sepolia (Chain ID 84532)**: The core EVM privacy continuum—comprising `SeraphToken` (ERC-20 with dynamic sell-side burn and tax exemption registry), `PrivacyPool` (depth-20 incremental Merkle tree, note commitment vault, zero-knowledge spend verifier), `CrossEVMBridge` (relayer bonding and optimistic challenge state machine), `GasRelayer` (dual-asset gas abstraction in SER and wXMR), `SeraphPresale` (tier-based vesting vault), and `SeraphLaunchpad` (multi-model bonding curves with 5-way fee routing). Tested across 205 Foundry unit/fuzz tests, 256,000 invariant runs, and 59 TypeScript SDK integration tests.
- **Active Research & Roadmap (Target Architecture)**: The sovereign Monero-inspired settlement base layer (Phase 0 PoC in Rust) and the dedicated XMR EVM (Phase 2). All cross-environment anonymity claims represent active engineering milestones designed to anchor into the live EVM privacy core.

---

## 0.1 Executive Risk Factors & Regulatory Disclaimers

*(Drafted in consultation with counsel for institutional and regulatory compliance)*

1. **Pre-Mainnet & Testnet Status**: All smart contracts described in this manual are currently deployed on Base Sepolia, an experimental Ethereum test network. No mainnet token generation event (TGE) or public deposit window has opened. Contract addresses, cryptographic parameters, fee allocations, and delivery schedules are subject to modification based on third-party security audits.
2. **Smart Contract & Software Risk**: Despite rigorous internal testing (205 passing Foundry tests, 256,000 invariant verification cycles), smart contracts may harbor undiscovered defects, reentrancy vulnerabilities, or compiler anomalies. Passing internal test suites is not a guarantee of security. No capital should be committed until independent audits conclude.
3. **Cryptographic Prover & Setup Assumptions**: The EVM privacy pool relies on Groth16 zero-knowledge proofs over the BN254 elliptic curve, which require a structured reference string (SRS) generated via a multi-party computation (MPC) ceremony. A compromise of the ceremony's toxic waste parameters would allow proof forgery. Long-term protocol upgrades target post-quantum, transparent STARK proofs.
4. **Limits of On-Chain Privacy**: Cryptographic privacy does not guarantee absolute anonymity against external correlation attacks. User IP addresses, deposit/withdrawal timing patterns, round-number deposit amounts, and public KYC entry points can leak identity metadata outside protocol control. Users must utilize relayer gas abstraction and unlinked stealth addresses to maintain high anonymity sets.
5. **Administrative & Governance Authority**: Certain protocol functions possess emergency powers—specifically the Guardian Council's ability to trigger a circuit breaker pause on `PrivacyPool` and `CrossEVMBridge` within 15 minutes of threat detection, and the DAO Treasury's timelocked governance over verifier addresses. Refer to Chapter 18 for the complete administrative authority matrix.
6. **Regulatory & Tax Responsibilities**: Privacy-enhancing protocols and digital assets face divergent legal classifications across jurisdictions. Users remain solely responsible for tax reporting, anti-money laundering (AML) compliance, and adherence to local laws. Chapter 10 specifies verifiable view-key compliance tools to assist with audit disclosures without sacrificing financial sovereignty.

---

## 0.2 Canonical Deployment Registry (Base Sepolia · 84532)

| Contract System | Network | Chain ID | Deployed Address | Implementation Status |
| :--- | :--- | :--- | :--- | :--- |
| **SeraphPresale** | Base Sepolia | 84532 | `0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE` | Live Verification Sandbox |
| **SeraphLaunchpad** | Base Sepolia | 84532 | `0xe0349E4cC431329207e98C5205062776e058A846` | Live Verification Sandbox |
| **SeraphToken (SER)** | Base Sepolia | 84532 | `0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F` | Shipped Core Contract |
| **PrivacyPool** | Base Sepolia | 84532 | `0x8B32194380695B47aebC9D55A674BfF6174a90fE` | Shipped Core Contract |
| **CrossEVMBridge** | Base Sepolia | 84532 | `0x42f2F13fF1439811C8e24483733A0B1B6194b632` | Shipped Core Contract |
| **GasRelayer** | Base Sepolia | 84532 | `0x6F412586e398F659086Eb3A284699564fcf2fE6c` | Shipped Core Contract |
| **InvoiceRegistry** | Base Sepolia | 84532 | `0x9Db76466A8201fe6fB078696874e44D416631Ec2` | Shipped Module |
| **UsageVault** | Base Sepolia | 84532 | `0x87aC386d9B5697669d6b5e0B3c7069c9b1391F09` | Shipped Module |
| **CollateralVault** | Base Sepolia | 84532 | `0x51E2b62A53f31A8587114A5A296D8b92b67272Eb` | Shipped Module |
| **Protocol DAO Treasury** | Base Sepolia | 84532 | `0xa287FC2B8f89023eF1c82af09aee351cCdDa8a76` | Protocol Vault |
| **Guardian Council** | Base Sepolia | 84532 | `0x7890abcdef1234567890abcdef1234567890abcd` | 4-of-7 Multisig |

---

## 0.3 Third-Party Audit & Security Assurance Status

| System Component | Target Contracts | External Auditor | Verification Window | Target Mainnet Report | Audit Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Core Privacy Pool** | `PrivacyPool.sol`, `IVerifier.sol` | Tier-1 Firm (Pending) | Q1 2027 | Formal ZK Audit | Pending Contract |
| **Token & Tax Mechanics** | `SERAPH.sol` | Tier-1 Firm (Pending) | Q1 2027 | ERC-20 & Tax Review | Pending Contract |
| **Cross-EVM Bridge** | `CrossEVMBridge.sol` | Tier-1 Firm (Pending) | Q1 2027 | Bridge & Fraud Security | Pending Contract |
| **Launchpad & Presale** | `Launchpad.sol`, `Presale.sol` | Tier-1 Firm (Pending) | Q1 2027 | Financial Invariant Audit | Pending Contract |
| **Internal Test Suite** | Full Repository | Seraph Core Engineering | Continuous | 205 Foundry / 256k Invariant | **Passing (100%)** |

> **Audit Gate Statement**: In compliance with protocol governance rules, mainnet deposits and official token generation are strictly gated behind the completion of at least two independent external security audits and formal verification of all zero-knowledge circuit constraints.

---

## 0.4 Introduction: What Seraph Is

Seraph is a modular privacy protocol engineered to resolve the fundamental trilemma between **cryptographic privacy**, **programmable smart contracts**, and **regulatory auditability**.

Historically, decentralized ledger architectures have been split into two mutually exclusive camps:
1. **UTXO-based Privacy Networks** (such as Monero): Offering peerless anonymity sets, confidential transaction values, and stealth unlinkability, but lacking Turing-complete contract execution and multi-token composability.
2. **Account-based Smart Contract Platforms** (such as Ethereum and EVM rollups): Offering rich programmable composability, decentralized finance (DeFi), and autonomous application development, but exposing complete transaction graphs, account balances, and interaction histories to global surveillance and predatory MEV bots.

Seraph bridges this divide through a **four-level Privacy Continuum** anchored by a high-throughput, Monero-inspired base layer running alongside dual confidential Ethereum Virtual Machines (Seraph EVM and XMR EVM).

```
+------------------------------------------------------------------------------+
|                           THE PRIVACY CONTINUUM                              |
+------------------------------------------------------------------------------+
  Level 0: Public EVM Execution (Transparent Auditability & Composability)
      |
      +--> [approveAndShield]
  Level 1: Shielded Pool & Confidential Balances (Hidden Net Worth)
      |
      +--> [privateTransfer]
  Level 2: Ephemeral Stealth Routing & Full Anonymity Set
      |
      +--> [zk-EVM Precompiles]
  Level 3: Confidential Contract State & Zero-Knowledge Settlement
```

---

## 0.5 The Privacy Continuum: Levels 0 to 3

Seraph recognizes that privacy is not a binary toggle, but a continuum where different economic activities demand different privacy assurances:

| Level | Name | Visibility | State Architecture | Primary Use Cases |
| :--- | :--- | :--- | :--- | :--- |
| **Level 0** | **Public EVM** | Sender, recipient, and amount fully public | Standard ERC-20 (`SERAPH.sol`) & EVM balance storage | DEX market liquidity, launchpad token discovery, public treasury accounting |
| **Level 1** | **Shielded Pool** | Balances hidden; deposit/withdraw events public | Merkle tree of note commitments (`PrivacyPool.sol`) | Long-term balance protection, wealth storage without exposing wallet balances |
| **Level 2** | **Full Stealth** | Sender, recipient, amount, and asset completely obfuscated | Depth-20 Incremental Merkle tree (2²⁰ capacity = 1,048,576 notes) + Nullifiers | Private P2P payments, payroll settlement, dark pool order placement |
| **Level 3** | **Confidential Contracts** | Contract logic executed with encrypted state and zero-knowledge inputs | Dual Private EVMs with algebraic precompiles & ZK proof verifiers | Private lending/CDP (`CollateralVault`), AI usage billing (`UsageVault`), sealed ballots |

### The Commitment Scheme Split: EVM vs. Sovereign Base Layer
A foundational architectural distinction exists between Seraph's two execution tiers:
- **EVM Privacy Pool (Shipped Core on Base Sepolia)**: Note commitments are computed algebraically via domain-separated hashing:
  `Commitment C = Keccak256(amount || recipientPubkey || blinding)`
  Value conservation is enforced **inside the zero-knowledge circuit constraint system** (R1CS), proving that the sum of unspent inputs equals the sum of output commitments plus execution fees without exposing individual note amounts.
- **Sovereign Base Layer (Rust Prototype PoC)**: Native UTXO transactions utilize homomorphic Pedersen commitments:
  `Commitment C = v · G + b · H`
  Value conservation is verified mathematically by homomorphic summation (`Sum(C_in) - Sum(C_out) = 0`) coupled with Bulletproofs++ range proofs proving that each note value `v in [0, 2⁶⁴ - 1]`.

---

## 0.6 Who the Technical Manual Is For

This documentation suite is organized into distinct tracks tailored to four primary stakeholder groups:

1. **End Users & Privacy Advocates**: Understand the mechanics of shielding, private transfers, and tax-free unshielding; manage wallets safely; and utilize dual view keys for selective compliance disclosure.
2. **Smart Contract & Frontend Developers**: Build privacy-preserving decentralized applications using standard Solidity; integrate the `@seraph-protocol/sdk` TypeScript client and Rust base-layer bindings; and invoke on-chain precompiles for confidential state management.
3. **Validators, Relayers & Node Operators**: Run full nodes and lightweight verification clients; operate bonded relayers on the Cross-EVM Bridge to earn routing fees; and participate in sequencer clusters.
4. **Token Holders & Ecosystem Creators**: Review SER tokenomics, supply caps (fixed 100M SER), and automatic fee burn mechanics; participate in confidential DAO governance ballots; and deploy fair-launch bonding curve tokens with custom multi-way fee distributions.

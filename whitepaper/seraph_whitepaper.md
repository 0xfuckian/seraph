# Seraph: A Privacy Continuum Protocol

**Version 2.1 — October 19, 2026**

---

## Abstract

Seraph solves the programmability gap of pure privacy coins and the weak
default privacy of most smart-contract platforms by combining a
Monero-inspired base layer with two specialized private EVMs that share
anonymity sets. Users enjoy strong default privacy for payments while
developers get familiar EVM tooling with private state. Deep XMR support
ensures users never have to leave the privacy set. The continuum model
allows gradual disclosure when required without forcing it on everyone.

---

## 1. Introduction

Current privacy solutions are incomplete:

- **Pure privacy coins** (Monero, Grisade) offer strong default privacy for
  value transfer but lack programmable private execution.
- **Smart-contract platforms** (Ethereum, Solana) provide programmability
  but weak or opt-in privacy, leaking behavior on-chain.
- **Privacy layers** (Aztec, Nocturne) add privacy to existing chains but
  fragment the anonymity set and require users to bridge assets.

Seraph unifies these by building a base layer with Monero-grade default
privacy as a settlement layer, then adding two specialized private EVMs
that share the base layer's anonymity set.

### 1.1 Design Goals

- Default strong privacy for all value movement
- Programmable private smart contracts
- Seamless XMR + SER dual-asset experience
- Progressive privacy levels (transparent → optional → default-strong → private compute)
- Practical usability for normal users and developers

### 1.2 Anti-Goals

- Not a clone of an existing privacy coin
- Not a general-purpose EVM without privacy
- Not a bridge-only privacy layer (we are the base)

---

## 2. Architecture Overview

### 2.1 Layer 1 — Seraph Base Layer

A new Monero-inspired privacy chain providing:

- Native support for SER and XMR
- Stealth addresses (one-time destination keys)
- Confidential amounts (Pedersen commitments)
- Range proofs (Bulletproofs++)
- Full-chain membership proofs (FCMP++)
- Encrypted memos
- Settlement and hard-money layer

### 2.2 Layer 2a — Seraph EVM

A general-purpose EVM with selective-privacy defaults:

- Solidity-compatible
- Gas primarily in SER
- Optional private contract state
- Privacy continuum applied per-transaction

### 2.3 Layer 2b — XMR EVM

A specialized EVM optimized for XMR flows:

- Preferential XMR fee payment
- Tighter coupling to base-layer XMR
- Gas abstraction via relayers

### 2.4 Shared Components

- **Unified Key Hierarchy**: One seed controls accounts on all layers.
- **Shared Anonymity Sets**: Note pools where possible across layers.
- **Trust-Minimized Bridges**: Lock on source, prove, mint on destination.
- **Relayer Network**: Gas abstraction, XMR fee payment, mempool batching.

---

## 3. Cryptographic Foundations

### 3.1 Notes, Commitments, Nullifiers

A **note** represents a private balance. Its structure includes:

- Amount commitment (Pedersen)
- Owner stealth address data
- Blinding factors
- Optional encrypted memo
- Nullifier derived from spend key + note

A **commitment** is published to a Merkle tree. The tree root is updated on each block.

A **nullifier** is derived from the note's blinding factor and a secret spend key. Publishing the nullifier prevents double-spending without revealing which note it came from.

### 3.2 Transaction Flow (Private Spend)

1. Select input notes (proof-of-legitimacy via view key or ownership proof)
2. Generate new output note commitments
3. Construct a zero-knowledge proof showing:
   - Ownership of inputs (nullifier preimage)
   - Balance conservation (inputs == outputs + fee)
   - Amount range (no overflow, > 0)
   - Merkle inclusion for each nullifier
4. Publish nullifiers + new commitments + proof
5. Network verifies proof, checks nullifiers are unspent, updates Merkle root

### 3.3 Membership Proofs (Path to Full-Chain)

Ring signatures provide logarithmic anonymity. Seraph targets FCMP++ (Full
Chain Membership Signatures) for constant-sized proofs with full-chain
anonymity, eliminating the need for mixin selection and addressing
decoy-linkability concerns.

### 3.4 View Keys & Selective Disclosure

- **Incoming View Key**: Allows scanning for received notes
- **Outgoing View Key** (optional): Allows proving that a specific nullifier
  was spent by a specific party

This enables selective disclosure for compliance without breaking default
privacy.

---

## 4. The Privacy Continuum

Seraph introduces a four-level privacy continuum:

| Level | Name | Description |
|-------|------|-------------|
| 0 | Transparent | Public transaction, like Ethereum |
| 1 | Optional Shielding | User chooses when to enter/exit privacy pools |
| 2 | Default Strong | Private transactions by default; user opts out |
| 3 | Private Compute | Confidential contract state + ZK compute |

Users can gradually disclose more information as needed. The continuum
model means privacy is the default, but compliance and auditability paths
exist where explicitly chosen.

---

## 5. Dual EVM Design & Gas Abstraction

### 5.1 Seraph EVM

- Solidity-compatible runtime with precompiles for privacy primitives
- Gas paid in SER by default
- Optional private contract state via ZK state channels
- Bridge to base layer for privacy pool operations

### 5.2 XMR EVM

- Same EVM semantics, XMR-native
- XMR can be used for gas via gas-abstracted relayers
- Tighter integration with XMR-flavored privacy primitives

### 5.3 Gas Abstraction

`GasAbstraction.sol` allows users to pay fees in either SER or XMR:

1. User signs an intent (pay fee in XMR, receive service in SER EVM)
2. Relayer pays gas in the required token
3. Relayer is reimbursed from the user's selected asset
4. Optional privacy on settlement

---

## 6. XMR Integration Philosophy

Seraph integrates XMR at three levels:

1. **Native**: XMR is a first-class asset on the base layer, with the same
   privacy guarantees as SER.
2. **EVM**: XMR can be used in both EVMs via bridged representation.
3. **Wallet**: Unified interface — users can transact in either asset without
   leaving the privacy set.

XMR support does not compromise Seraph's anonymity set because both assets
share the same note pool primitives at the base layer.

---

## 7. First-Party Modules

### 7.1 Private Stablecoins

Over-collateralized stablecoins with private mint/burn:

- `CollateralVault.sol` — manages collateral positions
- `PrivateStableFactory.sol` — deploys new private stable tokens
- `xUSD.sol` — example stablecoin (extendable to xEUR, xJPY, etc.)
- `OracleAdapter.sol` — delay-tolerant oracle design
- `LiquidationEngine.sol` — privacy-preserving liquidations

### 7.2 AI Payments

Unlinkable payments for AI agents and metered services:

- `UsageVault.sol` — holds deposits
- `ZKCreditAuthorizer.sol` — proves credit remaining without revealing balance

### 7.3 Messaging

On-chain verifiable payment requests for private messaging:

- `InvoiceRegistry.sol` — registry of request hashes and fulfillment

### 7.4 RWA Privacy (Future)

- `RWAVault.sol` — private RWA custody
- `ComplianceModule.sol` — view-key-based selective disclosure

---

## 8. Consensus Considerations

The base layer may use:

- **Ouroboros-based PoS** — proven, peer-reviewed
- **Tendermint/HotStuff BFT** — fast finality, good for bridging
- **Hybrid PoS + privacy-poW** — experimental

The final choice will be determined by the research phase. Key requirements:
fast finality for L2 exits, validator anonymity, and resistance to
long-range attacks.

---

## 9. Token Economics

### 9.1 Token

- **Name:** Seraph
- **Ticker:** SER
- **Supply:** 100,000,000 SER (fixed, no inflation)

### 9.2 Allocation

| Recipient | % | Vesting |
|-----------|---|---------|
| Ecosystem & Community | 40% | Gradual (incentives, grants, airdrops) |
| Team & Advisors | 20% | 4-year vesting, 1-year cliff |
| Foundation / Treasury | 15% | Long-term reserves |
| Early Contributors | 15% | Private sale terms |
| Public Sale + Liquidity | 10% | At launch |

### 9.3 Utility

- Gas fees on both EVMs and base layer
- Staking (if PoS)
- Governance voting
- Fee discounts in modules
- Privacy-pool incentive rewards

### 9.4 Fee Model

- Base layer: payable in SER or XMR
- EVMs: primary gas in SER, XMR via gas abstraction/relayers
- A percentage of fees is burned; a percentage goes to treasury and public goods

---

## 10. Security Model & Threat Analysis

### 10.1 Core Assumptions

- Trusted setup is minimized or eliminated (universal circuits)
- Base-layer validators follow BFT assumptions
- Bridges are trust-minimized with fraud proofs

### 10.2 Threat Model

| Threat | Mitigation |
|--------|-----------|
| Anonymity-set depletion | Shared pools, FCMP++ |
| Nullifier guessing | Domain-separated nullifier derivation |
| Amount overflow | Bulletproofs++ range proofs |
| Key reuse | Stealth addresses, one-time keys |
| Bridge theft | Fraud proofs, bond-and-challenge |
| Oracle manipulation | Delay + decentralization |

### 10.3 Audit Requirements

- Two independent security audits before mainnet
- Formal verification of core ZK circuits
- Fuzz testing of all contracts and circuits
- Continuous monitoring post-launch

---

## 11. Development Roadmap

| Phase | Timeline | Deliverables |
|-------|----------|-------------|
| **PoC** | 2–4 months | Note system, CLI wallet, private transfer demo, XMR simulation |
| **MVP** | 4–8 months | Base-layer testnet, one EVM, reference wallet, explorer, bridge, website |
| **Alpha** | 3–6 months | Second EVM, messaging v1, AI payments v1, stablecoin prototype, audits start, incentivized testnet |
| **Beta** | 4–8 months | Mainnet candidate, production modules, multiple audits, full SDKs, liquidity plan |
| **v1.0** | — | Production mainnet launch + stabilization |

---

## 12. Conclusion

Seraph bridges the gap between privacy-first value transfer and programmable
private execution. By starting from a Monero-inspired base layer and adding
two specialized private EVMs, it offers developers the tools they need —
Solidity, familiar EVM semantics — without compromising the user's right to
financial privacy.

The privacy continuum model ensures that privacy is the default, while
selective disclosure paths exist for compliance. Deep XMR integration means
users never leave the privacy set. And the modular architecture ensures
that new use cases — messaging, AI payments, private stablecoins, RWA —
can be built as first-party modules without endangering the core.

---

## References

1. RingCT: https://eprint.iacr.org/2017/497
2. Bulletproofs++: https://eprint.iacr.org/2022/1379
3. FCMP++: https://eprint.iacr.org/2024/1238
4. Serpent: https://github.com/seraph-protocol
5. Seraphis: https://github.com/UkoeHIDX/Seraphis

---

*This is a living document. See [CONTRIBUTING.md](/CONTRIBUTING.md) to suggest edits.*

```text
Seraph Protocol — Privacy Continuum
Version 2.1 | October 19, 2026 | Fixed Supply: 100,000,000 SER
```

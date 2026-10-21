# Seraph: A Privacy Continuum Protocol

**Version 3.0 — 21 October 2026**  
**Status: Research & Design Specification**

---

## Abstract

Existing privacy solutions force an unacceptable trade-off: pure privacy coins such as Monero deliver strong default privacy for value transfer but lack programmability, while smart-contract platforms and most privacy layers offer programmability at the cost of weak or fragmented privacy.

Seraph resolves this tension by introducing a **Privacy Continuum** built on three tightly integrated layers:

1. A Monero-inspired base layer providing default strong privacy and a large shared anonymity set.
2. A general-purpose private EVM (Seraph EVM).
3. An XMR-optimized private EVM (XMR EVM).

Both EVMs inherit and contribute to the base layer’s anonymity set. Deep native XMR support ensures users never need to leave the privacy set. The continuum model makes strong privacy the default while still permitting selective disclosure when explicitly required.

---

## 1. Introduction

### 1.1 The Privacy–Programmability Gap

- **Monero-style systems** excel at untraceable payments but cannot host general smart contracts.
- **Transparent or opt-in smart-contract platforms** (Ethereum, Solana, etc.) leak rich behavioral metadata.
- **Existing privacy layers** (Aztec, Railgun, etc.) improve privacy on top of transparent chains but typically create smaller, fragmented anonymity sets and force users through bridges.

Seraph is designed from the ground up so that **privacy is the base layer**, not an optional overlay.

### 1.2 Design Goals

- Default strong privacy for all value transfers
- Programmable private execution (Solidity-compatible)
- Large, shared anonymity sets across layers
- First-class XMR support without compromising the set
- Progressive privacy levels (the Continuum)
- Practical developer and user experience

### 1.3 Anti-Goals

- Not a pure privacy coin without programmability
- Not a general-purpose EVM with weak privacy
- Not a pure L2/bridge that depends on a transparent base chain for security

---

## 2. System Architecture

### 2.1 Layer 1 — Seraph Base Layer

A purpose-built privacy settlement layer inspired by Monero’s cryptographic primitives, with the following properties:

- Stealth addresses
- Confidential amounts (Pedersen commitments + Bulletproofs++ or successor)
- Nullifiers
- Path toward Full-Chain Membership Proofs (FCMP++)
- Native support for both SERAPH and XMR
- Encrypted memos

This layer serves as the ultimate source of truth and the primary anonymity-set reservoir.

### 2.2 Layer 2a — Seraph EVM

A general-purpose EVM environment with private state capabilities:

- Solidity compatibility
- Client-side or hybrid proving for private transactions and private contract state
- Primary gas token: SERAPH
- Ability to interact with the base-layer privacy pools

### 2.3 Layer 2b — XMR EVM

A specialized EVM optimized for XMR-centric workflows:

- Preferential or native XMR fee payment via gas abstraction
- Tighter coupling to base-layer XMR
- Same privacy guarantees as Seraph EVM

### 2.4 Shared Infrastructure

- **Unified key hierarchy** — one seed controls accounts across all layers
- **Shared note / commitment pools** where cryptographically feasible
- **Trust-minimized bridges** with clear security models
- **Relayer network** for gas abstraction and improved UX

---

## 3. Cryptographic Foundations

### 3.1 Notes and the Privacy Pool

A note represents a private UTXO-like balance and contains:

- Pedersen commitment to the amount
- Stealth address / ownership data
- Blinding factors
- Optional encrypted memo
- Derived nullifier

Notes are inserted into one or more Merkle trees. Spending a note requires a zero-knowledge proof of:

- Knowledge of the note opening
- Correct nullifier derivation
- Merkle inclusion
- Balance conservation
- Valid range

### 3.2 Path to Full-Chain Membership Proofs

Initial implementations may use efficient ring or limited-set membership proofs. The long-term target is FCMP++-class proofs that allow membership against the entire set of eligible outputs, dramatically increasing the anonymity set and eliminating many decoy-selection attacks.

### 3.3 View Keys and Selective Disclosure

- Incoming view keys enable light clients and selective scanning
- Optional outgoing view keys enable proofs of specific spending behavior when the owner chooses to disclose

This design supports legitimate compliance needs without making disclosure the default.

### 3.4 Cross-Layer Anonymity

A core research and engineering challenge is ensuring that notes originating from different layers can meaningfully contribute to and benefit from a common anonymity set. Mechanisms under consideration include shared commitment trees, carefully designed bridging of notes, and unified nullifier spaces where safe.

---

## 4. The Privacy Continuum

Seraph defines four explicit privacy levels:

| Level | Name                  | Characteristics                                      |
|-------|-----------------------|------------------------------------------------------|
| 0     | Transparent           | Fully public (Ethereum-style)                        |
| 1     | Optional Shielding    | User elects when to enter/exit privacy pools         |
| 2     | Default Strong        | Private by default; explicit opt-out required        |
| 3     | Private Compute       | Confidential contract state + private execution      |

The continuum is a first-class protocol feature, not an afterthought. Wallets and SDKs are expected to surface these levels clearly to users.

---

## 5. Dual EVM Design and Gas Abstraction

Both EVMs support private transfers and private contract interactions. Gas abstraction allows users to pay fees in either SERAPH or XMR regardless of which EVM they are using, via a relayer network that settles privately or semi-privately when possible.

---

## 6. XMR Integration

XMR is treated as a first-class asset:

- Native on the base layer with identical privacy guarantees to SERAPH
- Representable and usable inside both EVMs
- Fully supported in the official wallet under a unified interface

The design goal is that moving between SERAPH and XMR never forces a user out of the strong privacy set.

---

## 7. First-Party Modules

Planned modules built on the core protocol:

- **Private Stablecoins** — over-collateralized, private mint/burn
- **AI Agent Payment Rails** — unlinkable, metered payments
- **Private Messaging + Payments** — encrypted messaging with native private tips and invoices
- **RWA Privacy Interfaces** (later) — selective disclosure for regulated assets

These modules are designed to expand the usefulness of the continuum without weakening the base privacy guarantees.

---

## 8. Consensus and Security Considerations

The base layer requires:

- Fast enough finality for practical L2 exits
- Strong resistance to long-range attacks
- Compatibility with privacy-preserving validator or mining participation

Candidate approaches (PoS variants, hybrid designs, etc.) will be evaluated against these criteria during the research phase. Economic security of bridges and relayers is treated as a first-class concern.

---

## 9. Token Economics

- **Token**: SERAPH (SER)
- **Max Supply**: 100,000,000 (fixed)
- **Allocation** (proposed):
  - 40% Ecosystem & Community
  - 20% Team & Advisors (4-year vesting, 1-year cliff)
  - 15% Foundation / Treasury
  - 15% Early Contributors
  - 10% Public Sale + Initial Liquidity

**Utility**: gas, staking (if applicable), governance, module fee discounts, and privacy-pool incentives.

A portion of fees is burned; the remainder supports the treasury and public goods.

---

## 10. Security Model and Threat Analysis

**Primary Security Goals**:
- Transaction unlinkability
- Amount confidentiality
- Non-malleability of transactions
- Integrity of the note set (no inflation)
- Bridge safety under defined trust assumptions

**Key Threats and Mitigations** (summary):

- Small anonymity sets → shared pools + FCMP++ roadmap
- Malicious relayers → economic bonds + fraud proofs where possible
- Bridge attacks → minimized trust + challenge periods
- Cryptographic breaks → conservative primitive choices + upgrade paths
- Long-range attacks → consensus design constraints

Multiple independent audits and formal verification of core circuits are required before mainnet.

---

## 11. Scalability and Performance Considerations

Key metrics to be measured and optimized:

- Client-side proof generation time
- Proof size
- On-chain verification cost
- Note-set growth and sync time for light clients
- Effective throughput under private transaction load

Client-side proving is preferred for maximum privacy; hybrid approaches may be used for better UX where necessary.

---

## 12. Development Roadmap

| Phase   | Duration     | Focus                                      |
|---------|--------------|--------------------------------------------|
| PoC     | 2–4 months   | Core note system, private transfers, demos |
| MVP     | 4–8 months   | Base testnet + one EVM + wallet + bridge   |
| Alpha   | 3–6 months   | Dual EVMs, first modules, audits begin     |
| Beta    | 4–8 months   | Mainnet candidate, production modules      |
| v1.0    | —            | Production mainnet                         |

---

## 13. Conclusion

Seraph aims to be the first system that simultaneously delivers:

- Monero-grade default privacy
- Programmable private execution
- A large shared anonymity set
- Deep XMR integration
- A clear Privacy Continuum for users

By making privacy the foundation rather than an add-on, Seraph seeks to close the long-standing gap between private money and private computation.

---

## References

(Selected)

1. Ring Confidential Transactions – https://eprint.iacr.org/2015/1098
2. Bulletproofs / Bulletproofs++ literature
3. Full-Chain Membership Proofs research (Monero Research Lab / related)
4. Aztec, Railgun, and other private EVM designs (for comparison)
5. Seraphis and related Monero next-generation designs

---

## Glossary

- **Note**: Private UTXO-like balance
- **Nullifier**: Unique tag preventing double-spends
- **Stealth Address**: One-time destination address
- **FCMP++**: Full-Chain Membership Proofs
- **Privacy Continuum**: The four explicit privacy levels defined by the protocol
- **Gas Abstraction**: Ability to pay fees in a different asset than the one required by the execution environment

---


*This is a living document. See [CONTRIBUTING.md](/CONTRIBUTING.md) to suggest edits.*

```text
Seraph Protocol — Privacy Continuum
Version 3.0 | October 21, 2026 | Fixed Supply: 100,000,000 SER
```

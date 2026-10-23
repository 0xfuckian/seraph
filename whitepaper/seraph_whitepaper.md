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

- **Seraph Launchpad** — permissionless multi-chain token launchpad with bonding-curve graduation, locked liquidity, and future privacy-token launches (detailed in Section 7.1)
- **Private Stablecoins** — over-collateralized, private mint/burn
- **AI Agent Payment Rails** — unlinkable, metered payments
- **Private Messaging + Payments** — encrypted messaging with native private tips and invoices
- **RWA Privacy Interfaces** (later) — selective disclosure for regulated assets

These modules are designed to expand the usefulness of the continuum without weakening the base privacy guarantees.

### 7.1 Seraph Launchpad

The **Seraph Launchpad** (`SeraphLaunchpad` and `LaunchToken`) is a permissionless on-chain token creation and liquidity bootstrapping protocol that generates sustainable protocol revenue while enforcing transparent, immutable market rules.

#### Launch Models

Creators select one of three execution models at deployment:

1. **Bonding Curve (Curve-to-Pool Graduation)**: 100% of the token supply is minted directly into a virtual-reserve constant-product bonding curve $(R_{\text{quote}} + Q_{\text{phantom}}) \cdot R_{\text{token}} = k$. A deterministic portion of supply is held back for graduation liquidity (`reservedTokens`). Once the curve collects the target `graduationThreshold` (or `sellableTokens` reaches zero), the launch automatically graduates inside the completing purchase—clamping any excess buy amount, refunding unused quote currency in the same transaction, and unlocking the reserved supply into a permanently locked constant-product pool.
2. **Fixed Supply Pool**: The full supply is minted at launch directly into an instant locked pool with zero pre-allocation or team bags held outside the pool.
3. **Seraph Native Pool**: Trades continuously on a self-contained Seraph constant-product pool where all protocol and creator fees are settled directly in the quote asset on every buy and sell without external DEX router dependencies.

#### Immutable Fee & Split Architecture

Every launch enforces strict, non-upgradeable fee bounds written at token creation:

- **Mandatory Platform Fee (1.0% / 100 bps)**: Charged on every buy and every sell in the quote asset and routed to the Seraph platform fee recipient. Launchers cannot disable or reduce this fee.
- **Creator Buy & Sell Fees (0% to 2.5% / 0 to 250 bps per side)**: Configured at launch and permanently locked. Combined with the 1% platform fee, the maximum total fee any trade can pay is **3.5%**.
- **Five-Way Immutable Fee Split**: The creator fee is partitioned at launch (summing to 100%) across five autonomous on-chain destinations:
  1. **Creator (`creatorShareBps`)** — credited to the creator's designated `feeWallet` via pull-escrow (`claimFees()`) so a reverting recipient contract can never block trading.
  2. **Buyback & Burn (`buybackShareBps`)** — swaps collected quote fee directly against the reserve and permanently burns the acquired tokens (`ERC20Burnable.burn`), reducing total supply.
  3. **Holder Dividends (`dividendsShareBps`)** — distributed in $O(1)$ time to circulating holders via a magnified dividend accumulator (`accDividendPerShare`, excluding the launchpad reserve).
  4. **Auto-LP (`liquidityShareBps`)** — injected directly into `realQuoteReserve`, permanently deepening pool liquidity and raising the floor price.
  5. **Send to Seraph (`platformShareBps`)** — donated to the Seraph protocol treasury alongside the 1% base fee.
- **No Tax Exemptions & Capped Atomic Dev Buy**: No wallet can be exempted from trading fees. Creators may optionally execute an atomic dev buy at launch capped at `10%` (`1000 bps`) of supply (`0%`, `1%`, `2%`, `5%`, or `10%`), paying the exact same fee schedule as public buyers.

#### Multi-Chain Rollout & Privacy Token Launches (Roadmap Integration)

The Launchpad rolls out across three progressive stages aligned with the Privacy Continuum:

- **Stage 1 — Public Multi-Chain Launchpad (Base & Arc → Broader EVM/L1 Expansion)**: Launches initially on **Base** and **Arc**, followed by expansion to additional high-throughput EVM and non-EVM chains. All cross-chain deployments settle platform fees to the Seraph ecosystem treasury to fund core protocol R&D and `SERAPH` buyback/burn.
- **Stage 2 — Optional Shielding Wrapper (`Level 1` Continuum)**: Any graduated Launchpad token can be registered with a companion `PrivacyPool` instance, enabling holders to `shield`, `privateTransfer` (via Groth16 / UltraPlonk ZK proofs over the depth-20 Poseidon Merkle tree), and `unshield` their launched tokens without fragmenting public AMM liquidity.
- **Stage 3 — Native Privacy Token Launches (`Level 2–3` Continuum on Seraph EVM & XMR EVM)**: Once the Seraph Base Layer and private EVMs are live, creators will be able to launch **Native Privacy Tokens** directly from the Launchpad UI—featuring confidential holder balances (Pedersen commitments), stealth recipient addresses, unlinkable dividend claims, and optional view-key disclosure for compliant launches.

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

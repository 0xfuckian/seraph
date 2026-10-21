# Seraph

**Privacy Continuum Protocol**

Monero-grade default privacy + programmable private execution.

Seraph combines a Monero-inspired base layer with two specialized private EVMs that share anonymity sets. Strong privacy is the default. Programmability is native. XMR is first-class.

**Website:** [seraphprotocol.tech](https://seraphprotocol.tech)  
**Whitepaper:** [whitepaper/seraph_whitepaper.md](./whitepaper/seraph_whitepaper.md)

---

## Overview

Most privacy coins lack programmability.  
Most smart-contract platforms lack strong default privacy.  
Most privacy layers fragment the anonymity set.

Seraph is designed to close that gap:

- **Base Layer** — Monero-inspired privacy chain (stealth addresses, confidential amounts, path to FCMP++)
- **Seraph EVM** — General-purpose private EVM (Solidity-compatible)
- **XMR EVM** — XMR-optimized private EVM with gas abstraction
- **Shared components** — Unified key hierarchy, shared note pools where possible, trust-minimized bridges, relayer network

### Privacy Continuum

| Level | Name               | Description                                      |
|-------|--------------------|--------------------------------------------------|
| 0     | Transparent        | Fully public                                     |
| 1     | Optional Shielding | User chooses when to enter/exit privacy pools    |
| 2     | Default Strong     | Private by default (base layer)                  |
| 3     | Private Compute    | Confidential contract state + private execution  |

---

## Current Status

**Phase 0 — Proof of Concept** (in progress)

- Core note system and spend circuit
- CLI wallet
- Private transfer demonstration
- XMR simulation

Nothing is live on mainnet. No public sale is active until contracts are deployed and this repository reflects the live addresses.

---

## Repository Structure

```text
seraph/
├── whitepaper/          # Protocol specification
├── contracts/           # Solidity contracts (PrivacyPool, SERAPH token, bridges, modules…)
├── circuits/            # ZK circuits
├── base-layer/          # Base chain node (research/implementation)
├── wallet/              # Reference wallet
├── sdk/                 # Client libraries
├── docs/                # Documentation
└── scripts/             # Deployment & testing helpers

Key Features

Default strong privacy for value transfer
Programmable private smart contracts
Native SERAPH + first-class XMR support
Shared anonymity set design goal across layers
Gas abstraction (pay fees in SERAPH or XMR)
First-party modules: private stablecoins, AI payment rails, private messaging, etc.
Progressive privacy levels (the Continuum)
Selective disclosure via view keys
Token

Name: SERAPH
Ticker: SER
Max Supply: 100,000,000 (fixed, no inflation)
Allocation follows the whitepaper (Ecosystem 40%, Team 20%, Foundation 15%, Early Contributors 15%, Public + Liquidity 10%).

Documentation

Whitepaper
Website
Contracts and circuit documentation will expand with each phase
Security

Multiple independent audits required before mainnet
Formal verification of core ZK circuits planned
Bug bounty will be opened at Alpha/Beta
No mainnet until security exit criteria are met
This is experimental research software. Do not use with real funds until audits are complete and mainnet is explicitly announced.

Contributing

We welcome research discussion, issue reports, and well-scoped pull requests.

This is a living document. See CONTRIBUTING.md to suggest edits.

Open an issue first for significant changes
Keep cryptographic and consensus changes well-documented
All privacy-critical code requires extra scrutiny
Roadmap (High Level)

Phase	Focus
PoC	Private transfers + core cryptography
MVP	Base testnet + Seraph EVM + wallet
Alpha	Dual EVMs + first modules + audits begin
Beta	Mainnet candidate + production modules
v1.0	Mainnet launch
Detailed exit criteria are listed on the website and in the whitepaper.

Disclaimer

Seraph is a research and development project. The software is provided “as is”, without warranty of any kind. Privacy technology is complex and evolving. Nothing in this repository constitutes financial, legal, or investment advice.


Seraph — Privacy by default. Programmability included.


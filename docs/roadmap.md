# Seraph Protocol — Development Roadmap

> Version 2.1 | October 19, 2026  
> From PoC → v1.0 Mainnet

---

## Phase 0: PoC (Proof of Concept) — 2–4 months

**North star:** *Private transfers work end-to-end.* A user can generate a seed, create private notes, transfer value privately between two parties, and verify that balances are hidden and nullifiers prevent double-spending — all on a local test network.

### Deliverables

| Area | What's built | Key files |
|------|-------------|-----------|
| **Note system** | Minimal note structure: amount commitment, owner key, nullifier, blinding | `circuits/spend.nr` (Noir) |
| **ZK circuit** | Single circuit proving: ownership of nullifier preimage, balance conservation, range proof | `circuits/spend.nr` |
| **CLI wallet** | Generate seed → derive keys → create notes → shield → private transfer → unshield | `base-layer/wallet/src/cli.rs` |
| **Base layer** | Single-node testnet with in-process P2P, block production, transaction validation | `base-layer/src/` |
| **XMR simulation** | XMR represented as a second asset type in the note system (no real Monero node) | `base-layer/src/assets.rs` |
| **Tests** | Private transfer, double-spend rejection, balance conservation, nullifier uniqueness | `tests/poc/` |

### Exit criteria
- ✅ Two users can privately transfer value on a local network
- ✅ Nullifier prevents double-spending (verified by test)
- ✅ Amounts are confidential (range proof passes)
- ✅ XMR can be used as a payment asset in the note system

### NOT in PoC
- No EVM, no second EVM, no bridging, no web wallet

---

## Phase 1: MVP — 4–8 months after PoC

**North star:** *A usable testnet with wallet, explorer, and one EVM. External builders can start experimenting.*

### Deliverables

| Area | What's built | Key files |
|------|-------------|-----------|
| **Base layer testnet** | Multi-node network, libp2p gossip, RPC, light client support | `base-layer/src/`, `base-layer/rpc/` |
| **Seraph EVM (v1)** | Solidity-compatible EVM with privacy-optional transfers | `evm/` |
| **PrivacyPool contract** | Audited shield/private transfer/unshield on EVM | `contracts/core/PrivacyPool.sol` |
| **SER token** | ERC-20 with privacy hooks | `contracts/core/SERAPH.sol` |
| **Reference wallet** | Tauri desktop app: seed, shield/unshield, private send, view-key scanning | `wallet/desktop/`, `wallet/web/` |
| **Explorer** | Next.js: block list, transaction detail, view-key scanner tool | `explorer/` |
| **Bridge** | Base Layer ↔ Seraph EVM (lock/mint with fraud proof) | `contracts/core/bridges/` |
| **Website** | Landing page, docs index, wallet download | `website/app/` |
| **Docs** | Architecture, cryptography, wallet, developer guides | `docs/` |
| **Incentivized testnet** | Small anonymous set, bug reporting channel | `scripts/testnet/` |

### Exit criteria
- ✅ Base layer testnet with ≥3 independent nodes
- ✅ Seraph EVM running Solidity contracts
- ✅ Desktop wallet can shield, transfer, unshield on testnet
- ✅ Explorer shows public data
- ✅ Bridge moves value between base layer and EVM
- ✅ 100+ testnet users, 10K+ transactions

---

## Phase 2: Alpha — 3–6 months after MVP

**North star:** *The full dual-EVM architecture proves out. Modules work. Audits begin.*

### Deliverables

| Area | What's built | Key files |
|------|-------------|-----------|
| **XMR EVM (v1)** | Specialized EVM, XMR gas, tighter base-layer coupling | `evm/xmr-evm/` |
| **Cross-EVM bridge** | Seraph EVM ↔ XMR EVM | `contracts/core/bridges/CrossEVMBridge.sol` |
| **Messaging v1** | InvoiceRegistry + encrypted memos | `contracts/modules/messaging/` |
| **AI Payments v1** | UsageVault + ZKCreditAuthorizer | `contracts/modules/ai_payments/` |
| **Stablecoin prototype** | CollateralVault + xUSD (over-collateralized) | `contracts/modules/stablecoin/` |
| **Gas abstraction** | Pay EVM fees in XMR or SER via relayers | `contracts/core/gas/` |
| **TypeScript SDK** | Wallet integration, bridge calls, proof generation | `sdk/typescript/` |
| **Audits start** | Circuit review, contract review (2 auditors) | `audits/` |
| **Mobile wallet** | React Native light client | `wallet/mobile/` |

### Exit criteria
- ✅ XMR EVM deployed on testnet
- ✅ All three modules deployed and functional
- ✅ Gas abstraction works (pay in XMR on Seraph EVM)
- ✅ TypeScript SDK can create wallets, shield, transfer, bridge
- ✅ Audit reports from 2 firms in progress
- ✅ 500+ testnet users, 100K+ transactions

---

## Phase 3: Beta — 4–8 months after Alpha

**North star:** *Mainnet candidate. Production modules. Liquidity plan in motion.*

### Deliverables

| Area | What's built | Key files |
|------|-------------|-----------|
| **Mainnet candidate** | Genesis config, validator set, production relay schedule | `scripts/genesis/` |
| **Production modules** | All modules hardened, production parameters | `contracts/modules/` |
| **Full SDKs** | TypeScript, Rust, Go | `sdk/{typescript,rust,go}/` |
| **Relayer network** | Gas abstraction relay, intent batching | `relayer/` |
| **Audits (complete)** | 2 independent audits, bug bounty launched | `audits/`, `docs/security/` |
| **Liquidity plan** | DEX listings, bridge liquidity | `scripts/liquidity/` |
| **Governance bootstrap** | Multi-sig → token voting path | `contracts/governance/` |
| **Production wallet** | Desktop, web, mobile all production-ready | `wallet/{desktop,web,mobile}/` |

### Exit criteria
- ✅ All audits complete, critical issues fixed
- ✅ Bug bounty program live ($100K+ pool)
- ✅ Production SDKs published
- ✅ 5+ relayers incentivized and operating
- ✅ Liquidity secured on major DEXes
- ✅ Governance contract deployed with multi-sig

---

## Phase 4: v1.0 Mainnet

**North star:** *Production launch and stabilization. Real value, organic growth.*

### Deliverables

| Area | What's built |
|------|-------------|
| **Full mainnet launch** | Base layer + both EVMs + all bridges |
| **Progressive deposits** | Value ramps up over days/weeks |
| **Production relayers + validators** | Network secured by professional operators |
| **First-party wallet** | Desktop (Tauri), web (Next.js), mobile (React Native) |
| **Explorer v1** | Full transaction history, view-key scanning |
| **Governance transition** | Multi-sig → token voting (6-month timeline) |
| **Monitoring & incident response** | 24/7 ops, alerting, runbooks |

### Exit criteria
- ✅ Mainnet live with ≥20 validators
- ✅ ≥$10M TVL across all layers
- ✅ 5+ independent apps built on Seraph EVM
- ✅ No critical or high-severity incidents
- ✅ Treasury funded for 12+ months of operations

---

## Version-to-Code Mapping

| Phase | Contracts | Circuits | Base Layer | Wallet | Website | SDKs |
|-------|-----------|----------|------------|--------|---------|------|
| PoC | — | spend.nr | single-node testnet | CLI | — | — |
| MVP | PrivacyPool, SER, Bridge | spend circuit verified | multi-node testnet | Desktop + Web | Landing + docs | — |
| Alpha | +Messaging, AI Payments, Stablecoin, GasAbstraction, CrossEVMBridge | +membership/range circuits | hardened | +Mobile | +App | TS SDK |
| Beta | +Governance contracts | audited + verified | production genesis | production | full site | TS + Rust + Go |
| v1.0 | full suite, verified | formal verification | mainnet | production all platforms | production | published |

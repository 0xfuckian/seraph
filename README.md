# Seraph: A Privacy Continuum Protocol

[![Foundry Tests](https://img.shields.io/badge/Foundry-205%2F205%20Passing-brightgreen)](./contracts/test/)
[![Rust Tests](https://img.shields.io/badge/Rust%20Crate-17%2F17%20Passing-blue)](./base-layer/tests/)
[![Node Tests](https://img.shields.io/badge/Node.js%20SDK-59%2F59%20Passing-success)](./sdk/typescript/test/)
[![Relayer Daemon](https://img.shields.io/badge/Relayer%20Daemon-17%2F17%20Passing-teal)](./services/relayer/test/)
[![Total Tests](https://img.shields.io/badge/Total%20Tests-301%2F301%20Passing-darkgreen)](./)
[![Invariants](https://img.shields.io/badge/Stateful%20Invariants-128k%20Calls%20(0%20Reverts)-darkgreen)](./contracts/test/)
[![Base Sepolia](https://img.shields.io/badge/Base%20Sepolia-13%20Contracts%20Deployed-blueviolet)](https://sepolia.basescan.org)
[![Documentation](https://img.shields.io/badge/BookStack-22%20Chapters%20(4%20Books)-orange)](./docs/bookstack/README.md)

**Monero-grade default privacy + programmable confidential smart contracts.**

Seraph is a decentralized Privacy Continuum protocol uniting a sovereign Monero-inspired settlement layer with dual private Ethereum Virtual Machine (EVM) execution environments that share a common cryptographic anonymity set. Strong privacy is the default for value movement. Programmable execution is native. $XMR$ is treated as a first-class citizen.

- **Website**: [seraphprotocol.tech](https://seraphprotocol.tech)
- **Whitepaper**: [whitepaper/seraph_whitepaper.md](./whitepaper/seraph_whitepaper.md)
- **BookStack Documentation**: [docs/bookstack/README.md](./docs/bookstack/README.md)
- **SDK**: [`@seraph-protocol/sdk`](./sdk/typescript/)
- **Live Testnet**: Base Sepolia (`Chain ID 84532`)

---

## 1. Overview & The Privacy Continuum

Most privacy coins lack programmability. Most smart-contract platforms leak comprehensive behavioral metadata. Most layer-2 privacy overlays fragment the anonymity set and remain susceptible to exit-point correlation.

Seraph resolves this tension by treating privacy as a continuous mathematical spectrum:

```
                THE PRIVACY CONTINUUM SPECTRUM
 Level 0                 Level 1               Level 2               Level 3
[ Transparent ] <---> [ Opt-in Shield ] <---> [ Default Strong ] <---> [ Confidential Compute ]
 Ethereum/Base         Shield/Unshield         Base Layer UTXO        Private EVM State
 Public Ledgers        PrivacyPool.sol         Stealth + Commit       ZK Contract Logic
```

| Level | Name | Description | Cryptographic Primitives |
| :--- | :--- | :--- | :--- |
| **0** | **Transparent** | Fully public execution for bridges & auditability | Keccak256, ECDSA, ERC-20 |
| **1** | **Optional Shielding** | Users deposit/withdraw from privacy pools | Incremental Merkle Tree (Depth 20), Ring Buffer |
| **2** | **Default Strong** | Private by default on settlement layer | Pedersen Commitments, Bulletproofs++, Stealth Keys |
| **3** | **Private Compute** | Confidential contract state & ZK execution | zk-SNARKs (Groth16/UltraPlonk), Nullifiers |

---

## 2. Current Implementation Status

**Current Phase: Alpha (Phase 3 of 5) — ~85% Complete**

- [x] **Phase 1: Proof of Concept (PoC)** — 100% Complete (Rust note ledger, Circom circuits, CLI wallet).
- [x] **Phase 2: Minimum Viable Product (MVP)** — 100% Complete (13 contracts deployed on Base Sepolia, interactive Web3 dApp, TypeScript SDK).
- [x] **Phase 3: Alpha** — ~85% Complete (297 total tests passing across Foundry [204], Rust [17], TypeScript SDK [59], and Relayer Daemon [17]; 128,000 handler fuzz calls across invariant test suites with 0 reverts; automated relayer & bridge daemon service; 15 security vulnerabilities resolved; 12-thread promotional media pack and 4 high-res graphics created).
- [ ] **Phase 4: Beta (Mainnet Candidate)** — Upcoming (Client-side WASM ZK proving, Rust `seraphd` node daemon, relayer network, external tier-1 security audit).
- [ ] **Phase 5: v1.0 Production Launch** — Target (Base mainnet deployment, liquidity pools, TGE).

---

## 3. Verified Base Sepolia Deployments (`Chain ID 84532`)

All protocol modules are currently deployed, verified, and operational on Base Sepolia:

| Contract Entity | Verified Address | Description |
| :--- | :--- | :--- |
| **`SeraphToken` ($SER$)** | [`0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F`](https://sepolia.basescan.org/address/0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F) | Fixed 100M cap, EIP-2612 permit, 1% tax (50% burn, 50% treasury), 0% tax privacy hooks. |
| **`PrivacyPool`** | [`0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6`](https://sepolia.basescan.org/address/0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6) | Depth-20 Incremental Merkle Tree (1M notes), 100-root ring buffer, nullifier registry. |
| **`SeraphPresale`** | [`0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE`](https://sepolia.basescan.org/address/0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE) | Multi-tier ($0.02, $0.03, $0.04), multi-currency (USDT, USDC, ETH), 14d cliff, 12mo vesting. |
| **`SeraphLaunchpad`** | [`0xe0349E4cC431329207e98C5205062776e058A846`](https://sepolia.basescan.org/address/0xe0349E4cC431329207e98C5205062776e058A846) | Bonding curve graduation, immutable 5-way fee split, $O(1)$ holder dividends. |
| **`CrossEVMBridge`** | [`0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d`](https://sepolia.basescan.org/address/0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d) | Bonded relayers (1 ETH bond), 1-hour fraud challenge window, Merkle proofs. |
| **`GasRelayer`** | [`0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885`](https://sepolia.basescan.org/address/0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885) | Gas abstraction paying fees in $SER$ or $wXMR$ with nullifier vouchers. |
| **`InvoiceRegistry`** | [`0xF5eC3a1CE0A1e2905401A78984b44631e931A733`](https://sepolia.basescan.org/address/0xF5eC3a1CE0A1e2905401A78984b44631e931A733) | Stealth invoices with encrypted view-key memos and single-use payment receipts. |
| **`UsageVault`** | [`0x455e6fd221f4Eef8a0Eb78307d61Aa87e95F9E90`](https://sepolia.basescan.org/address/0x455e6fd221f4Eef8a0Eb78307d61Aa87e95F9E90) | Blinded micro-payment credit deposits for AI agent compute redemptions. |
| **`CollateralVault`** | [`0xc6031429AAF8BEaB631b75C29f5Bb0D3701169aB`](https://sepolia.basescan.org/address/0xc6031429AAF8BEaB631b75C29f5Bb0D3701169aB) | Over-collateralized CDP vault (150% MCR) minting private $xUSD$ stablecoins. |
| **`PrivateStablecoin` ($xUSD$)** | [`0xC505C55024eD8930c79f153DDbCE2A3224EB48F0`](https://sepolia.basescan.org/address/0xC505C55024eD8930c79f153DDbCE2A3224EB48F0) | Vault-controlled private algorithmic stablecoin. |
| **`Testnet USDT`** | [`0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397`](https://sepolia.basescan.org/address/0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397) | 6-decimal testnet stablecoin with open `faucet(amount)`. |
| **`Testnet USDC`** | [`0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0`](https://sepolia.basescan.org/address/0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0) | 6-decimal testnet stablecoin with open `faucet(amount)`. |
| **`Testnet Wrapped XMR`** | [`0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A`](https://sepolia.basescan.org/address/0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A) | 18-decimal testnet wrapped Monero representation. |

---

## 4. Architecture & Protocol Components

```
                               SERAPH PROTOCOL STACK
+-----------------------------------------------------------------------------------+
|  Level 3: Private Compute EVM (Confidential Contracts, ZK Execution)              |
|  Level 2: Sovereign Base Layer (Pedersen Commitments, Bulletproofs++, Stealth)    |
|  Level 1: Shielded Pools (PrivacyPool.sol, Ring-Buffer Root Accumulator)          |
|  Level 0: Transparent Verification (Public Invariants, Bridge Settlement)         |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------+     +-----------------------+     +-----------------------+
|      Seraph EVM       | <-> |   Shared Note Pool    | <-> |        XMR EVM        |
|  (General Programmable|     |  (Depth-20 Merkle Tree|     | (Native Monero Gas &  |
|   Private Contracts)  |     |   1,048,576 Capacity) |     |  Preferential Settl.) |
+-----------------------+     +-----------------------+     +-----------------------+
```

### 4.1 Smart Contracts (`contracts/`)
- **`contracts/core/SERAPH.sol`**: Fixed 100M supply, EIP-2612 `permit()`, 1.0% sell tax (50% burn, 50% treasury), native `approveAndShield` and `unshield` hooks.
- **`contracts/core/PrivacyPool.sol`**: Incremental Merkle tree with canonical sorted-pair Keccak256 hashing, 100-root ring buffer, and spent nullifier tracking.
- **`contracts/core/Launchpad.sol`**: Three launch models (BondingCurve, FixedPool, SeraphPool), mandatory 1% platform fee, 0-2.5% creator fee with 5-way split (Creator, Buyback/Burn, Holder Dividends, Auto-LP, Treasury), $O(1)$ magnified dividend accumulator.
- **`contracts/core/bridges/CrossEVMBridge.sol`**: Cross-EVM state batch relaying with 1.0 ETH relayer bond and 1-hour challenge window.
- **`contracts/core/gas/GasRelayer.sol`**: Gas abstraction vouchers paying fees in SER or wXMR.

### 4.2 Rust Base Layer (`base-layer/`)
- **`seraph_core`**: In-memory privacy ledger implementing stealth address derivation, Pedersen commitments, 20-level Merkle tree, and view-key cipher.
- Verified against adversarial double-spend, nullifier exhaustion, and asset-isolation attack vectors.

### 4.3 Zero-Knowledge Circuits (`circuits/`)
- **`circuits/spend.circom`**: 1-input 2-output spend circuit enforcing balance conservation ($\sum v_{\text{in}} = \sum v_{\text{out}} + \text{fee}$), 64-bit binary range proofs, nullifier derivation, and 20-level Merkle membership proofs.

### 4.4 TypeScript SDK (`sdk/typescript/`)
- **`@seraph-protocol/sdk`**: Key derivation (`deriveWalletKeys`), note commitments (`computeNoteCommitment`), nullifiers (`deriveNullifier`), view-key memo encryption, and client-side bonding curve mathematics.

### 4.5 Relayer & Bridge Daemon (`services/relayer/`)
- **`@seraph-protocol/relayer`**: Automated cross-chain bridge batcher and zero-gas execution relayer connecting Base Sepolia, Seraph EVM, and XMR EVM.
- **CrossChainBridgeBatcher**: Ingests on-chain `TokensLocked` events, computes binary Merkle trees with orphan promotion, enforces 1 ETH relayer bonds, submits state batches on `CrossEVMBridge`, and produces inclusion proofs for `claimBridged`.
- **GasAbstractionDispatcher**: Solvency verification, anti-drain target protections, double-spend prevention, and transaction dispatch for `GasRelayer.executeWithGasAbstraction`.

### 4.6 Live BookStack Deployment & Sync Suite (`deploy/bookstack/`)
- **`@seraph-protocol/bookstack-deploy`**: Turnkey self-hosted [BookStackApp](https://www.bookstackapp.com/docs/admin/installation/) wiki deployment (Docker Compose or Ubuntu script) with persistent MariaDB storage.
- **Automated Sync Engine (`sync-docs-to-bookstack.mjs`)**: Directly connects to BookStack's REST API (`POST /api/books` and `POST /api/pages`), synchronizing all 4 Books and 22 markdown chapters with idempotent upserting.

---

## 5. Verification & Testing Registry (301 Tests)

Seraph enforces strict mathematical verification across Foundry, Rust, Node.js SDK, the Relayer Daemon, and the BookStack Sync Engine:

```bash
# 1. Run Foundry Smart Contract Suites (205/205 tests + 128,000 invariant handler calls)
forge test -vv

# 2. Run Rust Base-Layer Cryptographic Pentests (17/17 tests)
cargo test --manifest-path base-layer/Cargo.toml

# 3. Run Node.js SDK & Website Security Suites (59/59 tests)
node --test sdk/typescript/test/*.test.mjs

# 4. Run Relayer & Bridge Daemon Suites (17/17 tests)
node --test services/relayer/test/*.test.mjs

# 5. Run BookStack Deployment & Sync Verification Suite (3/3 tests)
npm test --prefix deploy/bookstack

# 6. Run Live Multi-Actor Scenario Script on Base Sepolia Fork
forge script script/LivePrivacyContinuumScenarios.s.sol
```

---

## 6. Web Application & Interactive Privacy Dock

The web application ([`website/index.html`](./website/index.html)) connects live to Base Sepolia via JSON-RPC:
1. **Interactive Privacy Continuum Dock** (`#privacy-pool`):
   - **Shield SER**: Deposits public $SER$ into `PrivacyPool`, generates client-side blinding $r$ and commitment $C$, executing `approveAndShield`.
   - **Private Transfer**: Spends a local shielded note via nullifier $N$, creating an unlinkable commitment for a recipient.
   - **Unshield SER**: Withdraws from the privacy pool back to public circulation with zero trading tax.
   - **Dual EVM & Bridge**: Cross-chain settlement routing between Base Sepolia, Seraph EVM (gas in SER), and XMR EVM (gas in XMR) with bonded relayers.
   - **Encrypted Messaging & Stealth Invoices**: End-to-end encrypted messaging and single-use stealth merchant invoices via `InvoiceRegistry.sol`.
   - **Testnet SER Faucet**: Direct acquisition of liquid testnet $SER$ with Sepolia ETH via `SeraphPresale.sol`.
   - **Encrypted Note Vault**: Displays local notes in browser storage with status badges, backup export, and block explorer links.
2. **BookStack Documentation Suite Explorer** (`#docs`):
   - Interactive chapter deep-dive explorer covering all 22 chapters across 4 books.
3. **Launchpad Feed & Trading Dock** (`#launch`):
   - Reads live on-chain token launches directly from `SeraphLaunchpad`.
   - Live trading dock for Buying, Selling, Claiming Creator/Platform Fees, and Claiming Holder Dividends.
4. **Promotional Media & Growth Suite** ([`promotions/`](./promotions/)):
   - **14 Social Media & Content Documents** (`promotions/posts/`):
     - `01_main_announcement_thread.txt` (10-tweet launch thread)
     - `02_monero_plus_evm_deep_dive.txt` (Technical deep dive)
     - `03_the_privacy_continuum_levels_0_to_3.txt` (4-level continuum guide)
     - `04_launchpad_and_tokenomics_thread.txt` (Bonding curve & fee splits)
     - `05_autonomous_ai_agents_thread.txt` (Autonomous agent micro-billing)
     - `06_compliance_and_view_keys.txt` (Selective disclosure & audit keys)
     - `07_developer_quickstart_guide.txt` (SDK integration tutorial)
     - `08_community_announcements_telegram_discord.txt` (Telegram/Discord announcements)
     - `09_dual_evm_bridge_architecture.txt` (Lock-prove-mint cross-chain thread)
     - `10_relayer_and_gas_abstraction_guide.txt` (Zero-gas relayer operator guide)
     - `11_privacy_continuum_manifesto_longform.txt` (2,490-word longform manifesto)
     - `12_merchant_stealth_invoices_and_ai_billing.txt` (Stealth invoices & AI billing)
     - `13_zero_gas_voucher_abstraction.txt` (Zero-gas voucher deep dive & UX paradox)
     - `14_bookstack_documentation_portal.txt` (22-chapter curriculum & explorer guide)
   - **5 Official 16:9 Promotional Visuals** (`promotions/images/`):
     - `seraph_privacy_continuum_banner.jpg` (Hero visual banner)
     - `seraph_stealth_privacy_pool.jpg` (Stealth routing & shielded pool architecture)
     - `seraph_launchpad_bonding_curve.jpg` (Launchpad bonding curve & fee distribution)
     - `seraph_dual_evm_bridge.jpg` (Dual EVM bridge & relayer network nexus)
     - `seraph_evm_layers_and_messaging.jpg` (Dual EVM execution spheres & zero-knowledge messaging)

---

## 7. License & Security

- **License**: MIT
- **Security Contact**: `security@seraphprotocol.tech`
- **Threat Model**: Comprehensive threat vector analysis and mitigation specifications can be found in [THREAT_MODEL.md](docs/THREAT_MODEL.md).
- **Notice**: All contracts currently deployed on Base Sepolia are for testing and audit validation. Mainnet launch is scheduled following completion of external formal verification and tier-1 audits.

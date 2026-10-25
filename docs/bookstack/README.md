# Seraph Protocol — BookStack Documentation Shelf

Welcome to the official **Seraph Protocol Documentation Shelf**. This documentation suite provides an exhaustive, production-grade technical manual for the Seraph Protocol — a modular privacy continuum combining a Monero-inspired base layer with dual private EVMs.

---

## Shelf Structure

```
docs/bookstack/
├── README.md                                    # Shelf Overview & Navigation Index
├── Book_1_Foundations_and_Cryptography/
│   ├── 00_overview_and_privacy_continuum.md     # What Seraph Is, Continuum L0-L3, Audiences
│   ├── 01_monero_heritage_and_evolution.md      # Ring Signatures, RingCT, Bulletproofs, Key Images
│   ├── 02_seraphis_and_research_horizons.md     # Enotes, Jamtis, Research Directions vs Shipped Tech
│   ├── 03_formal_cryptography_and_primitives.md # Pedersen, Stealth Keys, Nullifiers, Math Proofs
│   └── 04_zk_circuit_pipeline.md                # Groth16/PLONK, Tree Depth 20, Prover Benchmarks
├── Book_2_Core_Architecture_and_Networks/
│   ├── 05_base_layer_protocol.md                # Base Layer State, Dual Fees (SER+XMR), Networking
│   ├── 06_dual_private_evms.md                  # Seraph EVM, XMR EVM, Precompiles, Solidity Parity
│   ├── 07_bridges_and_cross_chain.md            # Lock-Prove-Mint, 1h Challenge Window, Fraud Proofs
│   ├── 08_relayers_and_gas_abstraction.md       # GasRelayer, Gasless tx in SER/XMR, Intent Batches
│   └── 09_sequencer_and_mev_shielding.md        # Encrypted Mempools, Threshold Decryption, MEV Shield
├── Book_3_Applications_and_Tokenomics/
│   ├── 10_wallets_and_key_management.md         # Official Wallets, Scanning, BIP-39, Tax Disclosures
│   ├── 11_first_party_privacy_modules.md        # xUSD CDP, AI Usage Tickets, Stealth Invoicing
│   ├── 12_ecosystem_dex_cex_integrations.md     # DEX Exemption Mapping, CEX Custody, RPC APIs
│   ├── 13_ser_tokenomics_and_burns.md           # 100M Supply, 1% Sell Tax (50% Burn), Deflation Model
│   ├── 14_presale_architecture_and_vesting.md   # Strategic/Private/Public Tiers, 12M Linear Vesting
│   └── 15_launchpad_and_creator_playbook.md     # Bonding Curves, 5-Way Splits, accDividendPerShare
└── Book_4_Operations_Security_and_Reference/
    ├── 16_governance_and_private_ballots.md     # Treasury DAO, Anonymous Ballots, RFC Workflow
    ├── 17_security_model_and_threat_matrix.md   # Threat Matrix, Reentrancy, Sybils, Audit Checklist
    ├── 18_emergency_procedures_and_circuit_breakers.md # Pool & Bridge Pauses, Multisig Quorum, Containment
    ├── 19_protocol_roadmap.md                   # Phases 0 to 4 Exit Criteria & Milestones
    ├── 20_glossary.md                           # 50+ Cryptographic & System Terms Defined
    └── 21_contributing_and_developer_setup.md   # Foundry, Rust, Node.js Environment & PR Standards
```

---

## Live BookStack Instance Deployment & Sync

To run a live, self-hosted [BookStack](https://www.bookstackapp.com/docs/admin/installation/) instance and automatically import all 4 Books and 22 Chapters via REST API:

- **Deployment Directory**: [`deploy/bookstack/`](../../deploy/bookstack/)
- **1-Command Docker Setup**: `docker compose up -d` in `deploy/bookstack/`
- **Native Ubuntu Installer**: `sudo ./install-ubuntu.sh docs.seraphprotocol.tech`
- **Automated Sync Engine**: `npm run sync --prefix deploy/bookstack`

See the [BookStack Deployment Guide](../../deploy/bookstack/README.md) for full setup instructions.

---

## Technical Baseline & Test Matrix

All specifications in this documentation correspond to verifiable, tested implementations in the Seraph monorepo:
- **EVM Smart Contracts**: 205 unit & scenario tests + 128,000 stateful invariant checks in Foundry with 0 reverts.
- **Rust Base Layer**: 17 adversarial pentest and cryptographic property suites in `seraph-base-layer`.
- **TypeScript SDK & UI**: 59 automated Node tests verifying zero XSS, exact Base Sepolia RPC decoding, cryptographic key derivations, and note scanning.
- **Relayer Daemon**: 17 automated unit and integration tests covering cross-chain bridge batching and gas abstraction.
- **BookStack Sync Suite**: 3 automated tests verifying local chapter inventories, markdown extraction, and deployment configs.
- **Deployed Testnet Deployment**: Base Sepolia (`Chain ID 84532`).

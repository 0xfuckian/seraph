# Seraph Protocol — Engineering Progress & Remaining Roadmap Report

**Updated:** October 23, 2026

---

## 1. Completed & Verified in Repository

### A. Seraph Launchpad (Revenue & Token Launch Layer)
- **`contracts/core/Launchpad.sol`**:
  - **`LaunchToken`**: 18-decimal ERC-20 (`ERC20Burnable`) storing on-chain metadata (`description`, `image`, `website`, `twitter`, `telegram`, `creator`) with an $O(1)$ Magnified Dividend Per Share accumulator (`accDividendPerShare`, `1e36` precision) that excludes the launchpad reserve so 100% of holder dividends go to circulating holders via `claimDividends()`.
  - **`SeraphLaunchpad`**:
    - Supports all 3 launch models: `FixedPool` (instant locked pool), `BondingCurve` (virtual-reserve constant-product curve that auto-graduates at `graduationThreshold` into a permanently locked pool, clamping excess final buys and refunding unused ETH), and `SeraphPool` (native Seraph pool).
    - Enforces the mandatory **1.0% (`100 bps`) platform fee** on every buy and sell plus the immutable creator buy/sell fee (**`0` to `250 bps`**, max `3.5%` total per trade).
    - Routes creator fees across the 5-way immutable split (`creatorShareBps`, `buybackShareBps`, `dividendsShareBps`, `liquidityShareBps`, `platformShareBps`).
    - Supports atomic dev buy at launch (`0%`, `1%`, `2%`, `5%`, `10%` max) with no tax exemptions.
- **`script/DeployLaunchpad.s.sol`**: One-command Foundry deployment script for Base and Arc.
- **`contracts/test/Launchpad.t.sol`**: 5 comprehensive end-to-end tests covering all 3 launch models, fee validation bounds, atomic dev buy cap & refund, 5-way fee split accounting, and bonding curve graduation into post-graduation pool trading.
- **`website/index.html` & `whitepaper/seraph_whitepaper.md`**: Added the `Seraph pool` launch model chip, wired `#lpLaunchBtn` form validation + Web3 wallet connection, and documented the Launchpad, multi-chain expansion, and future Privacy Token launches in Section 7.1 of the whitepaper.

### B. Privacy Subsystem & Base Layer (Phase 0 & Phase 1 Core)
- **`contracts/core/PrivacyPool.sol` & `contracts/core/SERAPH.sol`**:
  - Depth-20 Incremental Merkle Tree (`1,048,576` note capacity), 100-root ring buffer, nullifier registry, `shield`, `shieldFor`, `privateTransfer`, and `unshield`, integrated with `SeraphToken.approveAndShield` and tax exemptions.
  - Verified by 10 unit tests in `contracts/test/PrivacyPool.t.sol`.
- **Zero-Knowledge Circuits (`circuits/`)**:
  - `circuits/spend.circom` (1-in-2-out join-split spend circuit), `circuits/membership/merkle_membership.circom` (depth-20 Poseidon Merkle path verifier), and `circuits/range/range_proof.circom` (64-bit binary range proof).
- **Rust Base Layer (`base-layer/`)**:
  - Multi-asset shared anonymity pool (`AssetId::Seraph` and `AssetId::Xmr` in `base-layer/src/assets.rs`), note commitments & nullifier derivation (`note.rs`), depth-20 Incremental Merkle Tree (`tree.rs`), state ledger (`ledger.rs`), view-key derivation + encrypted memo stream cipher + wallet note tracking (`wallet.rs`).
  - Verified by `cargo test` (`test_phase0_end_to_end_privacy_flow` and `test_native_xmr_shared_anonymity_pool_and_view_key_memo`).

### C. Cross-EVM Bridge, Gas Abstraction & First-Party Modules (Phase 1–2)
- **`contracts/core/bridges/CrossEVMBridge.sol`**: Relayer bonding (`MIN_RELAYER_BOND = 1 ether`), state root batch submission, 1-hour fraud-proof challenge window with relayer bond slashing (`challengeBatch`), and Merkle-verified bridged token claims with nullifier replay protection.
- **`contracts/core/gas/GasRelayer.sol`**: Dual-EVM gas abstraction enabling users to fund gas vouchers and pay execution fees in `SER` or `wXMR`.
- **`contracts/modules/messaging/InvoiceRegistry.sol`**: Encrypted view-key messaging and stealth invoice creation/settlement.
- **`contracts/modules/ai_payments/UsageVault.sol`**: Unlinkable AI agent compute credit deposits and nullifier-ticket redemptions.
- **`contracts/modules/stablecoin/CollateralVault.sol`**: Over-collateralized `xUSD` private stablecoin vault enforcing a 150% minimum collateral ratio.
- **`contracts/test/ProtocolModules.t.sol`**: 5 end-to-end tests verifying all bridge, gas abstraction, and first-party module contracts (37/37 total Foundry tests passing).

---

## 2. Still To Do (Next Priorities Before Mainnet)

1. **Live Launchpad Deployment & Indexing (Immediate Revenue Step)**:
   - Run `script/DeployLaunchpad.s.sol` on Base mainnet (and Arc when RPC is configured) with the production multisig/treasury address as `PLATFORM_FEE_RECIPIENT`.
   - Set `LP_CONTRACTS.Base` in `website/index.html` to the deployed `SeraphLaunchpad` address and connect a lightweight event indexer (or `eth_getLogs` reader) to populate `#lpRows` from `TokenLaunched` / `Trade` / `Graduated` events and upload token images to IPFS/R2.
2. **Production ZK Verifier Compilation**:
   - Run `circom circuits/spend.circom --r1cs --wasm` + `snarkjs groth16 setup` (trusted setup / Powers of Tau) to generate the production BN254 Groth16 Solidity verifier contract (`Groth16Verifier.sol`) and plug it into `PrivacyPool.setVerifier()`.
3. **Multi-Node P2P Networking & JSON-RPC for `base-layer/`**:
   - Add `libp2p` gossip and an HTTP/WebSocket JSON-RPC server in `base-layer/` so external wallets and the block explorer can submit transactions to a multi-node testnet.
4. **TypeScript SDK (`sdk/typescript/`) & Security Audits**:
   - Package client-side note encryption, Merkle proof generation, and contract bindings into `sdk/typescript/`, followed by external smart contract and circuit audits.

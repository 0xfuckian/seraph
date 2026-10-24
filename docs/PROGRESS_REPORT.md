# Seraph Protocol — Autonomous Development, Audit & Multi-Agent Pentest Report

**Last Updated**: October 23, 2026 (Milestone 7 — Wave 2 Multi-Agent Pentesting & 896,000 Stateful Invariant Evaluations)  
**Latest Commit**: On `main`  
**Live Testnet**: **Base Sepolia (`Chain ID 84532`)** — All 13 core, launchpad, bridge, gas relayer, and module contracts deployed & verified with live multi-wallet scenarios.

---

## 1. Live Base Sepolia Testnet Registry (`Chain ID 84532`)

| Contract | Base Sepolia Address | Notes |
|---|---|---|
| **Deployer / Treasury** | `0x9C33fFaF37dF553b0E113352e134CA73890fEBa3` | Funded via Ethereum Sepolia → Base Sepolia L1StandardBridge |
| **`SeraphToken (SER)`** | `0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F` | 100M max supply, EIP-2612 Permit, 1% sell tax (50% burn / 50% treasury), pool & presale exempt |
| **`SeraphPresale`** | `0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE` | Strategic (`$0.02`), Private (`$0.03`), Public (`$0.04`); 14-day cliff + 12-mo linear vesting |
| **`PrivacyPool`** | `0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6` | Depth-20 Incremental Merkle Tree (1,048,576 notes), 100-root ring buffer, nullifier registry |
| **`SeraphLaunchpad`** | `0xe0349E4cC431329207e98C5205062776e058A846` | FixedPool, BondingCurve, SeraphPool; 1% platform fee + 0–2.5% creator 5-way split |
| **`LaunchToken #1 ($SALPHA)`** | `0xF7B81dAd075f5aFaB611C9642A2051497aC3463f` | Live BondingCurve token with 2% atomic dev buy + 0.002 ETH public buy |
| **`LaunchToken #2 ($SPRIV)`** | `0xC550998e4c02871612648Cca0B6123F519D752A7` | Multi-actor test token: bought by 2 wallets, sold, dividends claimed, fees claimed |
| **`CrossEVMBridge`** | `0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d` | Bonded relayers (`1 ETH`), 1-hour fraud-proof challenge window, nullifier-tagged Merkle claims |
| **`GasRelayer`** | `0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885` | Gas abstraction paying relayers in `SER` or `wXMR` via nullifier vouchers |
| **`InvoiceRegistry`** | `0xF5eC3a1CE0A1e2905401A78984b44631e931A733` | Stealth invoices & encrypted view-key memos settled in `SER` or `wXMR` |
| **`UsageVault`** | `0x455e6fd221f4Eef8a0Eb78307d61Aa87e95F9E90` | Blinded AI compute credit commitments & unlinkable provider ticket redemptions |
| **`CollateralVault`** | `0xc6031429AAF8BEaB631b75C29f5Bb0D3701169aB` | Over-collateralized CDP vault (`>= 150% CR`) |
| **`PrivateStablecoin (xUSD)`** | `0xC505C55024eD8930c79f153DDbCE2A3224EB48F0` | Minted/burned exclusively by `CollateralVault` |
| **Testnet `tUSDT` (6 dec)** | `0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397` | Public `faucet(uint256)` enabled for presale testing |
| **Testnet `tUSDC` (6 dec)** | `0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0` | Public `faucet(uint256)` enabled for presale testing |
| **Testnet `tWXMR` (18 dec)** | `0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A` | Public `faucet(uint256)` enabled for XMR EVM & gas relayer testing |

---

## 2. Eleven Security Vulnerabilities Discovered & Patched

1. **[HIGH] Repeat-Purchase Vesting Overwrite (`Presale.sol`)**:
   - `_setupVesting` previously overwrote `vesting[buyer][tierId]` on a second purchase in the same tier. Patched to accumulate `v.total += tokensToAdd` and block purchases after `tgeExecuted`.
2. **[CRITICAL] Unbounded Post-Duration Vesting Mint (`Presale.sol`)**:
   - `claimVested` and `getBuyerAllocation` did not cap `elapsed - v.cliffSeconds` at `v.duration` and double-subtracted `tgeAmount`. Patched to cap `vestElapsed <= v.duration` and compute `totalUnlocked = tgeAmount + (vestedTotal * vestElapsed) / v.duration`.
3. **[MEDIUM] Broken `receive()` External Self-Call (`Presale.sol`)**:
   - `receive()` called `this.buyWithETH(3)`, setting `msg.sender = address(presale)`. Refactored into internal `_buyWithETH(msg.sender, 3)`.
4. **[MEDIUM] 2300-Gas `.transfer()` Multisig Failure & Token Supply Cap (`Presale.sol`, `SERAPH.sol`)**:
   - Replaced `.transfer()` with `.call{value: ...}("")` for Gnosis Safe treasury compatibility, and enforced `MAX_SUPPLY = 100_000_000e18` in `SeraphToken.mint` and `receiveFromBridge`.
5. **[CRITICAL] Double-Claim Dividend Drain (`Launchpad.sol`)**:
   - `LaunchToken._checkpoint` did not update `rewardDebt[account] = accumulated` when called directly from `claimDividends()`. Patched to update `rewardDebt` inside `_checkpoint` and guarded `claimDividends` with `nonReentrant`.
6. **[CRITICAL] Arbitrary Call Target & Unbacked Pool Drain (`GasRelayer.sol`)**:
   - `executeWithGasAbstraction` previously allowed calling any `target` (including `seraphToken` or `xmrToken` directly) and did not bound `feeAmount` by funded voucher reserves. Patched with `ForbiddenTarget()` and `voucherPoolBalance[feeToken]` tracking + `SafeERC20`.
7. **[HIGH] Relayer Unbond Slashing Evasion (`CrossEVMBridge.sol`)**:
   - Added `lastBatchSubmittedAt[relayer]` and `unbondRelayer(uint256)` locked during active `CHALLENGE_WINDOW` (1 hour) so a malicious relayer cannot front-run `challengeBatch` by withdrawing their bond, plus `SafeERC20` and zero-value guards.
8. **[HIGH] Unbounded `totalSupply` Arithmetic Overflow (`Launchpad.sol`)**:
   - Enforced `MAX_TOTAL_SUPPLY = 1_000_000_000_000_000e18` (`1e33`) in `SeraphLaunchpad.launch()` so `balanceOf * accDividendPerShare` (`1e33 * 1e36 = 1e69 < 2^256`) and `_quoteBuy` can never overflow `uint256`.
9. **[MEDIUM] 1-Wei Floor-Minus-Floor Dividend Rounding Drift (`Launchpad.sol`)**:
   - Discovered by our 128,000-call stateful invariant fuzzer (`StatefulProtocolInvariants.t.sol`): setting `rewardDebt` with floor division after balance updates allowed $\lfloor A + B \rfloor - \lfloor A \rfloor = \lfloor B \rfloor + 1$ across multi-buy sequences. Patched `_checkpoint` and `_update` to round `rewardDebt` up (`(balance * accDividendPerShare + ACC_PRECISION - 1) / ACC_PRECISION`), making `LaunchToken` 100% solvent across all 128,000 stateful fuzz calls.
10. **[MEDIUM] Cross-Invoice Payment Nullifier Replay & Oracle Zero-Price Guards (`InvoiceRegistry.sol`, `UsageVault.sol`, `CollateralVault.sol`)**:
    - Added `usedPaymentNullifiers` tracking in `InvoiceRegistry`, non-zero ticket/amount checks in `UsageVault`, non-zero oracle price validation in `CollateralVault`, and `SafeERC20` across all modules.
11. **[UI] Removed Shrinking Floating Logo (`website/index.html`)**:
    - Removed `#brandFloat`, `.brand-float` CSS, and `updateBrand()` scroll scaling from `website/index.html` while keeping `#headerBrand` permanently visible in the top navigation bar.

---

## 3. Automated Test & Pentest Summary (`205/205` Tests + `896,000` Invariant Checks Passing)

- **Foundry Smart Contract Suites (`154/154` Passing across 12 Suites)**:
  - [StatefulProtocolInvariants.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/StatefulProtocolInvariants.t.sol): `1/1` stateful invariant suite (`128,000` calls, `384,000` invariant evaluations across `invariant_LaunchpadETHAlwaysSolvent`, `invariant_LaunchTokenDividendsAlwaysSolvent`, and `invariant_TokenReserveMatchesActualBalanceAndSupplyCapped`).
  - [StatefulModulesAndPoolInvariants.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/StatefulModulesAndPoolInvariants.t.sol): `1/1` stateful invariant suite (`128,000` calls, `512,000` invariant evaluations across `invariant_PrivacyPoolBalanceEqualsNetShielded`, `invariant_UsageVaultSolvency`, `invariant_CollateralVaultAndXUSDSolvency`, and `invariant_GasRelayerPoolSolvency`).
  - [DeepPentestLaunchpadPresale.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/DeepPentestLaunchpadPresale.t.sol): `26/26` passed (reentrancy callbacks, flash-loan roundtrip extraction fuzzing across all 3 models, 10-wallet sybil dividend ping-pong loop, `1e33` max supply boundary, presale cliff second-by-second boundaries).
  - [DeepPentestBridgePoolModules.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/DeepPentestBridgePoolModules.t.sol): `29/29` passed (`GasRelayer` forbidden target & pool cap, `CrossEVMBridge` unbond window lock & Merkle proof tampering, `PrivacyPool` duplicate nullifier & signal-binding verifier, `InvoiceRegistry`/`UsageVault`/`CollateralVault` reentrancy & 150% CR fuzzing).
  - [PermitTaxAndPresaleStress.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/PermitTaxAndPresaleStress.t.sol): `18/18` passed (EIP-2612 `permit` cryptographic replay/tamper checks, `SeraphToken` supply conservation fuzzing, and 20-buyer multi-tier/multi-currency presale stress test).
  - [LaunchpadMultiActor.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/LaunchpadMultiActor.t.sol): `20/20` passed.
  - [FullProtocolScenarios.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/FullProtocolScenarios.t.sol): `16/16` passed.
  - [Presale.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/Presale.t.sol): `17/17` passed.
  - [PrivacyPool.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/PrivacyPool.t.sol): `10/10` passed.
  - [SecurityAudit.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/SecurityAudit.t.sol): `6/6` passed.
  - [Launchpad.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/Launchpad.t.sol): `5/5` passed.
  - [ProtocolModules.t.sol](file:///Users/ianmora/Desktop/Projects/seraph/contracts/test/ProtocolModules.t.sol): `5/5` passed.
- **Rust Base-Layer Crate (`17/17` Passing)**:
  - [adversarial_pentest.rs](file:///Users/ianmora/Desktop/Projects/seraph/base-layer/tests/adversarial_pentest.rs) (`15/15` passed) + [lib.rs](file:///Users/ianmora/Desktop/Projects/seraph/base-layer/src/lib.rs) (`2/2` passed).
- **TypeScript SDK & Website Security / E2E (`34/34` Passing)**:
  - [security_pentest.test.mjs](file:///Users/ianmora/Desktop/Projects/seraph/sdk/typescript/test/security_pentest.test.mjs) (`16/16` passed) + [presale_and_router_pentest.test.mjs](file:///Users/ianmora/Desktop/Projects/seraph/sdk/typescript/test/presale_and_router_pentest.test.mjs) (`14/14` passed) + [website_e2e.test.mjs](file:///Users/ianmora/Desktop/Projects/seraph/sdk/typescript/test/website_e2e.test.mjs) (`2/2` passed) + [sdk.test.mjs](file:///Users/ianmora/Desktop/Projects/seraph/sdk/typescript/test/sdk.test.mjs) (`2/2` passed).

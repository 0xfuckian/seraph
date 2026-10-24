# Seraph Protocol — Multi-Agent Stress Test, Live Base Sepolia & Audit Report

**Updated:** October 23, 2026

---

## 1. Test Suite Summary (100% Passing)

- **Foundry Smart Contract Tests:** **79 / 79 passed** across 7 suites (`LaunchpadMultiActorTest`, `FullProtocolScenariosTest`, `SecurityAuditTest`, `LaunchpadTest`, `PrivacyPoolTest`, `PresaleTest`, `ProtocolModulesTest`), including **768 fuzz runs**.
- **Live Base Sepolia Multi-Wallet Scenarios:** **18 / 18 on-chain transactions succeeded** (`script/LiveTestnetScenarios.s.sol` on Chain ID `84532`).
- **Website & TypeScript SDK E2E Tests:** **4 / 4 passed** (`sdk/typescript/test/sdk.test.mjs` and `sdk/typescript/test/website_e2e.test.mjs`).
- **Rust Base Layer Tests:** **2 / 2 passed** (`cargo test` in `base-layer/`).

---

## 2. Six Security Audit Vulnerabilities Found & Patched

1. **Critical — Repeat Purchase Allocation Overwrite (`Presale.sol`)**: `_setupVesting` now accumulates `v.total += tokensToAdd` and blocks post-TGE buys.
2. **Critical — Vesting Over-Mint & TGE Offset (`Presale.sol`)**: Capped `vestElapsed <= v.duration` and computed `totalUnlocked = tgeAmount + (vestedTotal * vestElapsed) / v.duration`.
3. **Critical — Dividend Double-Claim in `LaunchToken._checkpoint` (`Launchpad.sol`)**: Added `rewardDebt[account] = accumulated;` inside `_checkpoint(account)` so claiming dividends without transferring tokens updates `rewardDebt` and prevents re-claiming (`test_Audit6_DoubleClaimDividendsRevertsAndCannotDrainOtherHolders`).
4. **High — `receive()` Fallback `msg.sender` Trap (`Presale.sol`)**: Direct ETH transfers now call internal `_buyWithETH(msg.sender, 3)`.
5. **Medium — Multisig Treasury `.transfer()` Gas Limit & 100M Supply Cap (`Presale.sol`, `SERAPH.sol`)**: Replaced `.transfer()` with `.call{value: ...}("")` and enforced `MAX_SUPPLY = 100_000_000 * 1e18`.
6. **Medium — EIP-170 Bytecode Size Limit (`foundry.toml`)**: Enabled `optimizer = true` and `optimizer_runs = 200`.

---

## 3. Live Base Sepolia Deployed Contracts (`Chain ID 84532`)

- **`SeraphLaunchpad`**: `0xe0349E4cC431329207e98C5205062776e058A846`
- **`SeraphPresale`**: `0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE`
- **`SeraphToken (SER)`**: `0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F`
- **`PrivacyPool`**: `0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6`
- **Launched Token #1 (`$SALPHA`)**: `0xF7B81dAd075f5aFaB611C9642A2051497aC3463f`
- **Launched Token #2 (`$SPRIV`)**: `0xC550998e4c02871612648Cca0B6123F519D752A7`
- **`CrossEVMBridge`**: `0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d`
- **`GasRelayer`**: `0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885`
- **`InvoiceRegistry`**: `0xF5eC3a1CE0A1e2905401A78984b44631e931A733`
- **`UsageVault (AI)`**: `0x455e6fd221f4Eef8a0Eb78307d61Aa87e95F9E90`
- **`CollateralVault`**: `0xc6031429AAF8BEaB631b75C29f5Bb0D3701169aB`
- **`PrivateStablecoin (xUSD)`**: `0xC505C55024eD8930c79f153DDbCE2A3224EB48F0`
- **`tUSDT` (6 dec)**: `0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397`
- **`tUSDC` (6 dec)**: `0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0`
- **`tWXMR` (18 dec)**: `0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A`

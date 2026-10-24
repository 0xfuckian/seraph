# Seraph Protocol — Live Base Sepolia Deployment, Security Audit & Progress Report

**Updated:** October 23, 2026

---

## 1. Live Base Sepolia Testnet Deployment (Chain ID `84532`)

All 13 Seraph Protocol contracts (plus our first launched bonding-curve token `$SALPHA`) are deployed and verified with live transactions on **Base Sepolia**:

| Contract | Base Sepolia Address | Explorer Link |
| :--- | :--- | :--- |
| **Deployer / Treasury** | `0x9C33fFaF37dF553b0E113352e134CA73890fEBa3` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x9C33fFaF37dF553b0E113352e134CA73890fEBa3) |
| **`SeraphToken (SER)`** | `0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F) |
| **`SeraphPresale`** | `0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE) |
| **`PrivacyPool` (Depth 20)** | `0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6) |
| **`SeraphLaunchpad`** | `0xe0349E4cC431329207e98C5205062776e058A846` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xe0349E4cC431329207e98C5205062776e058A846) |
| **First Launched Token (`$SALPHA`)** | `0xF7B81dAd075f5aFaB611C9642A2051497aC3463f` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xF7B81dAd075f5aFaB611C9642A2051497aC3463f) |
| **`CrossEVMBridge`** | `0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d) |
| **`GasRelayer`** | `0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885) |
| **`InvoiceRegistry`** | `0xF5eC3a1CE0A1e2905401A78984b44631e931A733` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xF5eC3a1CE0A1e2905401A78984b44631e931A733) |
| **`UsageVault (AI)`** | `0x455e6fd221f4Eef8a0Eb78307d61Aa87e95F9E90` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x455e6fd221f4Eef8a0Eb78307d61Aa87e95F9E90) |
| **`CollateralVault`** | `0xc6031429AAF8BEaB631b75C29f5Bb0D3701169aB` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xc6031429AAF8BEaB631b75C29f5Bb0D3701169aB) |
| **`PrivateStablecoin (xUSD)`** | `0xC505C55024eD8930c79f153DDbCE2A3224EB48F0` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xC505C55024eD8930c79f153DDbCE2A3224EB48F0) |
| **`tUSDT` (6 dec, open `faucet()`)** | `0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397) |
| **`tUSDC` (6 dec, open `faucet()`)** | `0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0) |
| **`tWXMR` (18 dec, open `faucet()`)** | `0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A) |

### Live Verification Transactions Executed on Base Sepolia
- **Launchpad Token Launch + 1% Atomic Dev Buy + 5-Way Fee Split (`$SALPHA`)**:
  `0x8698de02d73083be85f28bd0989281d9194cd6c6715d98401868c692e3a390de` (block `49474638`)
- **Presale Public Tier Purchase (`99.5 SER` bought with `0.002 ETH`)**:
  `0x276895f749ab3918ed0dafe292d461cc35b19f384ee1794277eaa9152c097d90` (block `49474648`)

---

## 2. Security Audit Findings & Fixes Applied (`42/42` Foundry Tests Passing)

1. **Critical — Repeat Purchase Allocation Overwrite (`Presale.sol`)**: `_setupVesting` now accumulates `v.total += tokensToAdd` and blocks post-TGE buys (`require(!tgeExecuted)`).
2. **Critical — Vesting Over-Mint & Under-Vesting Calculation (`Presale.sol`)**: Capped `vestElapsed <= v.duration` and computed `totalUnlocked = tgeAmount + (vestedTotal * vestElapsed) / v.duration`.
3. **High — `receive()` Fallback `msg.sender` Bug (`Presale.sol`)**: Direct ETH transfers now call internal `_buyWithETH(msg.sender, 3)` instead of external `this.buyWithETH(3)`.
4. **Medium — Multisig Treasury `.transfer()` Gas Limit & `MAX_SUPPLY` Cap (`Presale.sol`, `SERAPH.sol`)**: Replaced `.transfer()` with `.call{value: ...}("")` and enforced `MAX_SUPPLY = 100_000_000 * 1e18`.
5. **Medium — EIP-170 Bytecode Size Limit (`foundry.toml`)**: Enabled `optimizer = true` and `optimizer_runs = 200`.

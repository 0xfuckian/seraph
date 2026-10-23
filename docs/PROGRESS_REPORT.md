# Seraph Protocol — Security Audit, Testnet Launch & Progress Report

**Updated:** October 23, 2026

---

## 1. Security Audit Findings & Fixes Applied (`Presale.sol`, `SERAPH.sol`, `foundry.toml`)

5 vulnerabilities were uncovered during security auditing and fuzzing, patched, and verified in `contracts/test/SecurityAudit.t.sol` (42/42 Foundry tests passing):

1. **Critical — Repeat Purchase Allocation Overwrite (`Presale.sol`)**: `_setupVesting` previously overwrote `vesting[buyer][tierId]` instead of accumulating `v.total += tokensToAdd`. Fixed to accumulate across multiple purchases and block post-TGE buys (`require(!tgeExecuted)`).
2. **Critical — Vesting Over-Mint & Under-Vesting Calculation (`Presale.sol`)**: `claimVested` and `getBuyerAllocation` previously did not cap `elapsed - v.cliffSeconds` at `v.duration` (allowing infinite minting after vesting ended) and subtracted `v.released` (which included `tgeAmount`) from only the vested portion. Fixed by capping `vestElapsed <= v.duration` and computing `totalUnlocked = tgeAmount + (vestedTotal * vestElapsed) / v.duration`.
3. **High — `receive()` Fallback `msg.sender` Bug (`Presale.sol`)**: `this.buyWithETH(3)` made `msg.sender == address(presale)`, trapping direct ETH buyers' allocations inside the contract address. Fixed via internal `_buyWithETH(msg.sender, 3)`.
4. **Medium — Multisig Treasury `.transfer()` Gas Limit & `MAX_SUPPLY` Cap (`Presale.sol`, `SERAPH.sol`)**: Replaced 2300-gas `.transfer()` with `.call{value: ...}("")` so Gnosis Safe multisig treasuries work, and enforced `MAX_SUPPLY = 100_000_000 * 1e18` in `SeraphToken.mint()` and `receiveFromBridge()`.
5. **Medium — EIP-170 Bytecode Size Limit (`foundry.toml`)**: Enabled `optimizer = true` and `optimizer_runs = 200`.

---

## 2. Testnet Coins Needed & Deployment Commands

### What Test Coins Are Needed
- **Base Sepolia ETH (`~0.05 ETH`)**: The **only** external testnet coin required. It covers gas for deploying all 13 contracts (`~21.5M` gas) and executing test presale buys, launchpad launches, curve graduations, and privacy pool shielding.
- **Test Stablecoins & Test XMR (`tUSDT`, `tUSDC`, `tWXMR`)**: Automatically deployed by `script/DeployTestnet.s.sol` via `TestnetFaucetERC20`, which mints `1,000,000 tUSDT`, `1,000,000 tUSDC`, and `10,000 tWXMR` to the deployer and exposes a public `faucet(uint256 amount)` function for any test wallet.

### Public Base Sepolia Command
```bash
export PRIVATE_KEY=0xYourTestnetPrivateKey
export PATH="$HOME/.foundry/bin:$PATH"
forge script script/DeployTestnet.s.sol:DeployTestnet --rpc-url base_sepolia --broadcast -vv
```

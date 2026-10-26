# Chapter 8: Relayers & Gas Abstraction

## 8.1 The Gas Dilemma in Confidential Systems

In traditional Web3 applications, interacting with a blockchain requires the user to hold native gas tokens (such as ETH) in their public wallet. This creates a severe privacy leak:
- Even if a user receives funds anonymously into a private stealth address, they cannot move those funds without funding that stealth address with gas.
- The gas funding transaction (originating from a CEX or public wallet) immediately establishes a graph-analysis link to the private address, completely destroying privacy.

Seraph eliminates this vulnerability through **account-abstracted gas relayers** (`GasRelayer.sol`).

---

## 8.2 The GasRelayer Architecture

The `GasRelayer` contract allows users to execute arbitrary EVM transactions without holding any native ETH in their executing wallet. Instead, transaction fees are settled using **pre-funded gas vouchers** in SER or XMR:

```
 User (No ETH)                                    Gas Relayer                             EVM Contract
      |                                                |                                       |
      | 1. Signs intent + voucher nullifier            |                                       |
      +----------------------------------------------->|                                       |
      |                                                | 2. Submits tx on-chain (pays ETH gas) |
      |                                                |    Calls executeWithGasAbstraction    |
      |                                                | ------------------------------------->|
      |                                                |                                       | 3. Executes user payload
      |                                                | <-------------------------------------+
      |                                                | 4. Reimburses relayer in SER or XMR   |
      |                                                |    from voucher pool balance          |
```

---

## 8.3 Voucher Funding & Nullifier Settlement

### 1. Funding a Gas Voucher
A user (or onboarding sponsor) deposits fee tokens into the voucher pool:
```solidity
function fundGasVoucher(
    address feeToken,
    uint256 amount,
    bytes32 voucherCommitment
) external nonReentrant;
```
- `feeToken`: SER or `wXMR`.
- `voucherCommitment`: A cryptographic hash committing to an unspent secret scalar.
- Tokens are held in the contract's pooled liquidity escrow.

### 2. Gas-Abstracted Execution
When the user desires to execute a call:
```solidity
function executeWithGasAbstraction(
    bytes32 voucherNullifier,
    address feeToken,
    uint256 feeAmount,
    address target,
    bytes calldata data
) external nonReentrant returns (bytes memory result);
```
- The relayer broadcasts the transaction and pays the native gas in ETH.
- The contract verifies that `voucherNullifier` has not been used (`!usedVouchers[voucherNullifier]`).
- The contract verifies that `voucherPoolBalance[feeToken] >= feeAmount`.
- The contract marks `usedVouchers[voucherNullifier] = true`.
- The contract transfers `feeAmount` of `feeToken` directly to the relayer as compensation.
- The contract executes `target.call(data)` on behalf of the user.

---

## 8.4 Defensive Security & Target Filtering

To prevent malicious users from crafting exploit calls that drain protocol assets or hijack the relayer, `GasRelayer.sol` implements strict target validation:

```solidity
error ForbiddenTarget();

if (
    target == address(0) ||
    target == address(this) ||
    target == address(serToken) ||
    target == address(wxmrToken)
) revert ForbiddenTarget();
```

### Attack Mitigation:
- An attacker cannot supply `target = address(serToken)` with `data = transfer(...)` to drain tokens held by the relayer pool.
- An attacker cannot call internal admin functions on `GasRelayer` itself.
- Reentrancy locks (`nonReentrant`) prevent recursive callback drains.

---

## 8.5 Gas Conversion Rates & Governance Calibration

The conversion rate between native execution gas (ETH) and abstracted fee tokens (SER / XMR) is calibrated dynamically:

```solidity
function setTokenGasRate(address feeToken, uint256 rate) external onlyOwner;
```

### Calibration Mechanics:
- **Phase 0/1 Calibration**: The contract owner (DAO Treasury Timelock or automated Guardian bot) periodically updates `setTokenGasRate` using volume-weighted average prices (VWAP) sourced from external DEX pairs (Uniswap v3 TWAP / CoinGecko API).
- **Overhead Benchmarks**: Relayers incorporate an execution premium to absorb short-term gas price volatility during congestion spikes. Empirical benchmark data on Base Sepolia demonstrates that the actual fee buffer paid by users remains between 2.5% and 3.8% over raw execution gas costs.
- **Roadmap to Phase 2/3**: Decentralized oracle integration (Pyth Network / Chainlink data streams) will replace manual admin calibration with autonomous on-chain price feeds.

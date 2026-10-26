# Chapter 14: Presale Architecture & Vesting

## 14.1 Presale Philosophy & Structural Design

The Seraph presale (`Presale.sol`) is designed to distribute early protocol ownership transparently across three tiers while preventing post-TGE dumping through mathematical vesting schedules.

> [!NOTE] Testnet Sandbox Deployment & Security Assurance
> The presale contract is currently deployed in sandbox mode on **Base Sepolia** (`0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE`) for contract testing and community dry-runs. The live production sale will open only following the completion of comprehensive external smart contract audits.

The presale supports multi-currency participation in **ETH**, **USDC**, and **USDT**.

---

## 14.2 Tier Specifications & Allocation Matrix

| Tier ID | Tier Name | Token Price | Allocation Cap | TGE Unlock | Cliff Period | Linear Vesting | Access Gating |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | **Strategic** | **$0.02** | 3,750,000 SER | **25.0%** | 14 Days | 12 Months | Allowlist / Institutional Review |
| **Tier 2** | **Private** | **$0.03** | 11,250,000 SER | **20.0%** | 14 Days | 12 Months | Allowlist / Community Review |
| **Tier 3** | **Public** | **$0.04** | 10,000,000 SER | **100.0%** | None (0 Days) | None (0 Months) | Open to All (No Allowlist) |

### Key Economic Properties:
- **Total Raised Potential**:
  - Strategic: 3.75M * $0.02 = $75,000
  - Private: 11.25M * $0.03 = $337,500
  - Public: 10M * $0.04 = $400,000
  - **Total Presale Target**: $812,500
- **Presale Protocol Fee**: A nominal **0.50% fee** (`PRESALE_FEE_BPS = 50`) is deducted on purchases and routed to the Treasury to offset contract deployment and audit infrastructure costs.

### Allowlist Governance:
For Tier 1 (Strategic) and Tier 2 (Private), participation is gated by an on-chain allowlist mapping:
`whitelist[keccak256(abi.encodePacked(account, tierId))] = true`
The Treasury adds authorized participant addresses via `addToWhitelist(address[] calldata accounts)`. Tier 3 (Public) requires no allowlist and is open to any Web3 wallet.

---

## 14.3 Multi-Currency Payment Engine

Investors can purchase allocations using their preferred asset:
1. **USDC (6 Decimals)**: `buyWithStablecoin(tierId, amount, usdc, referrer)`
2. **USDT (6 Decimals)**: `buyWithStablecoin(tierId, amount, usdt, referrer)`
3. **ETH (18 Decimals)**: `buyWithETH(tierId)` or direct wallet transfer via `receive()` fallback.

### Direct `receive()` Fallback:
If an investor sends ETH directly to the presale contract address from a wallet without calling a specific function, the contract's `receive()` fallback automatically invokes `_buyWithETH(msg.sender, 3)`. The transaction purchases Public Tier 3 tokens at $0.04, applies the 0.5% fee, and credits the allocation directly to `msg.sender`.

### Dynamic ETH/USD Pricing:
The presale contract maintains an on-chain price parameter (`ethUsdPrice`) calibrated by the Treasury:
`Tokens Purchased = (ETH Amount * ethUsdPrice) / Tier Price`
Normalizing 6-decimal stablecoins to 18-decimal token precision is handled automatically with full integer precision and zero truncation loss.

---

## 14.4 Vesting Mathematics & Claim Lifecycle

For an investor with total allocation in Tier 1 or Tier 2:

### Accumulation on Repeat Purchases (`_setupVesting`)
If an investor purchases tokens multiple times across separate transactions prior to TGE, `_setupVesting` smoothly accumulates the new purchase into their existing balance:
```solidity
Vesting storage v = vesting[buyer][tierId];
uint256 newTotal = v.total + tokensToAdd;
```
The locked and vested portions recalculate against `newTotal`, ensuring full consistency.

### Phase 1: TGE Claim (`claimInitialAllocation`)
At Token Generation Event (t >= T_TGE):
`Initial Claimable = TotalAllocation * (LockupBPS / 10,000)`
- Strategic investors claim **25%** immediately.
- Private investors claim **20%** immediately.
- Public investors claim **100%** immediately via `claimInitialAllocation()`.

### Phase 2: The Cliff Period
For the first 14 days following TGE (T_TGE <= t < T_TGE + 14 days):
`Vested Amount = 0`
No additional tokens are releasable during the cliff.

### Phase 3: Continuous Linear Vesting (`claimVested`)
Following the 14-day cliff (t >= T_TGE + 14 days):
`Releasable(t) = (Total - Initial) * min(1, (t - (T_TGE + 14d)) / 365d) - AlreadyReleased`

```
 Releasable Tokens (%)
   100% +-------------------------------------------------------------* Full Unlock
        |                                                          /
        |                                                       /
        |                                                    /
        |                                                 /
        |                                              /  12-Month Linear
    25% |              +------------------------------+   Vesting Curve
        |              | 14-Day Cliff
     0% +---*----------+---------------------------------------------
           TGE     TGE+14d                                          TGE+379d
```

### Zero-Dust Guarantee
Our test suite confirms that after t >= T_TGE + 379 days:
`v.released == v.total` (Exact to the single wei)
No fractional wei is stranded in the contract.

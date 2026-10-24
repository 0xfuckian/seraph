# Chapter 14: Presale Architecture & Vesting

## 14.1 Presale Philosophy & Structural Design

The Seraph presale (`Presale.sol`) is designed to distribute early protocol ownership transparently across three tiers while preventing post-TGE dumping through mathematical vesting schedules.

The presale contract is deployed and verified on Base Sepolia (`0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE`) and supports seamless multi-currency investments in **ETH**, **USDC**, and **USDT**.

---

## 14.2 Tier Specifications & Allocation Matrix

| Tier ID | Tier Name | Token Price | Allocation Cap | TGE Unlock | Cliff Period | Linear Vesting | Access Gating |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | **Strategic** | **$0.02** | 10,000,000 SER | **25.0%** | 14 Days | 12 Months | Whitelist / KYC Required |
| **Tier 2** | **Private** | **$0.03** | 10,000,000 SER | **20.0%** | 14 Days | 12 Months | Whitelist / KYC Required |
| **Tier 3** | **Public** | **$0.04** | 10,000,000 SER | **100.0%** | None (0 Days) | None (0 Months) | Open to All (No KYC) |

### Key Economic Properties:
- **Total Raised Potential**:
  $$\text{Strategic: } 10\text{M} \times \$0.02 = \$200,000$$
  $$\text{Private: } 10\text{M} \times \$0.03 = \$300,000$$
  $$\text{Public: } 10\text{M} \times \$0.04 = \$400,000$$
  $$\text{Total Target Hard Cap} = \$900,000$$
- **Presale Protocol Fee**: A nominal **0.50% fee** (`FEE_BPS = 50`) is deducted on purchases to cover deployment and security audit costs.

---

## 14.3 Multi-Currency Payment Engine

Investors can purchase allocations using their preferred asset:
1. **USDC (6 Decimals)**: `buyWithStablecoin(tierId, amount, usdc, referrer)`
2. **USDT (6 Decimals)**: `buyWithStablecoin(tierId, amount, usdt, referrer)`
3. **ETH (18 Decimals)**: `buyWithETH(tierId)` or direct wallet transfer via `receive()` fallback.

### Dynamic ETH/USD Pricing:
The presale contract maintains an on-chain price parameter (`ethUsdPrice`) updated by the Treasury to mirror real-time market rates:
$$\text{Tokens Purchased} = \frac{\text{ETH Amount} \times \text{ethUsdPrice}}{\text{Tier Price}}$$
Normalizing 6-decimal stablecoins to 18-decimal token precision is handled automatically with full integer precision and zero truncation loss.

---

## 14.4 Vesting Mathematics & Claim Lifecycle

For an investor with total allocation $A$ in Tier 1 or Tier 2:

### Phase 1: TGE Claim (`claimInitialAllocation`)
At Token Generation Event ($t \ge T_{\text{TGE}}$):
$$\text{Initial Claimable} = A \times \frac{\text{UnlockBPS}}{10,000}$$
- Strategic investors claim **25%** immediately.
- Private investors claim **20%** immediately.
- Public investors claim **100%** immediately via `claimInitialAllocation()`.

### Phase 2: The Cliff Period
For the first 14 days following TGE ($T_{\text{TGE}} \le t < T_{\text{TGE}} + 14 \text{ days}$):
$$\text{Vested Amount} = 0$$
No additional tokens are releasable during the cliff.

### Phase 3: Continuous Linear Vesting (`claimVested`)
Following the 14-day cliff ($t \ge T_{\text{TGE}} + 14 \text{ days}$):
$$\text{Releasable}(t) = \left( A - \text{Initial} \right) \times \min\left(1, \frac{t - (T_{\text{TGE}} + 14 \text{ days})}{365 \text{ days}}\right) - \text{AlreadyReleased}$$

```
 Releasable Tokens (%)
   100% ┌─────────────────────────────────────────────────────────────● Full Unlock
        │                                                          ／
        │                                                       ／
        │                                                    ／
        │                                                 ／
        │                                              ／  12-Month Linear
    25% │              ┌──────────────────────────────┘   Vesting Curve
        │              │ 14-Day Cliff
     0% └───●──────────┴─────────────────────────────────────────────
           TGE     TGE+14d                                          TGE+379d
```

### Zero-Dust Guarantee
Our test suite confirms that after $t \ge T_{\text{TGE}} + 379 \text{ days}$:
$$\text{v.released} == \text{v.total} \quad (\text{Exact to the single wei})$$
No fractional wei is permanently stranded in the contract.

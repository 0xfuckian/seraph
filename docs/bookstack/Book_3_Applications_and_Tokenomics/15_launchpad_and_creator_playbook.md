# Chapter 15: Launchpad Mechanics & Creator Playbook

## 15.1 Overview: Fair Launches for the Privacy Era

The Seraph Launchpad (`Launchpad.sol`) enables creators, autonomous agents, and decentralized communities to launch privacy-native ERC-20 tokens with customizable economic flywheels, continuous bonding curves, and automated dividend distributions.

The contract is live on Base Sepolia at `0xe0349E4cC431329207e98C5205062776e058A846`.

```
                        SERAPH LAUNCHPAD ARCHITECTURE
   +------------------------------------------------------------------------+
   |                         THREE LAUNCH MODELS                            |
   |  [0] Fixed Pool       |  [1] Bonding Curve    |  [2] Seraph Pool       |
   |  Equal fixed pricing  |  Constant product     |  Hybrid privacy-routed |
   |  with hard cap        |  x * y = k            |  liquidity model       |
   +-----------------------------------+------------------------------------+
                                       |
                                       v
   +------------------------------------------------------------------------+
   |                       CONFIGURABLE 5-WAY FEE SPLIT                     |
   |  1. Creator Fee Share       ---> Claimed via pull-escrow claimFees     |
   |  2. Holder Dividends        ---> Distributed via accDividendPerShare   |
   |  3. Buyback & Burn          ---> Permanently reduces totalSupply       |
   |  4. Auto-Liquidity (LP)     ---> Deepens real quote reserves           |
   |  5. Optional Platform Share ---> Additional contribution to Treasury   |
   +------------------------------------------------------------------------+
```

---

## 15.2 The Three Launch Models

1. **Fixed Pool (Model 0)**:
   - Fixed token price from launch to graduation.
   - Ideal for predictable public token allocations and community airdrop claims.
2. **Bonding Curve (Model 1)**:
   - Continuous constant-product automated market maker (`x * y = k`).
   - Token price rises monotonically on every buy and falls on every sell.
   - Phantom virtual liquidity (`defaultPhantomQuote = 1.5 ether`) provides initial price stability without requiring upfront creator capital.
3. **Seraph Pool (Model 2)**:
   - Hybrid bonding curve tightly integrated with the `PrivacyPool`.
   - Buyers can opt to shield received tokens directly into private notes in the same transaction.

---

## 15.3 The Dual Fee Model, Anti-Spam Launch Fee & 6 UI Presets

The launchpad implements a clear distinction between **Protocol Platform Fees** and **Creator Fees**:

1. **Anti-Spam Creation Fee**: A flat 0.001 ETH (~$2.50 USD) fee paid at token deployment and routed directly to the Seraph Treasury (`0xa287FC2B8f89023eF1c82af09aee351cCdDa8a76`) to prevent bot flood attacks.
2. **Mandatory Gross Platform Fee**: A flat **1.00% protocol fee** (`PLATFORM_FEE_BPS = 100`) assessed on every buy and sell, credited directly to protocol revenue escrow (`claimableFees[platformFeeRecipient]`).
3. **Creator Trading Fee**: A configurable fee of up to **2.50%** (`buyFeeBps`, `sellFeeBps` <= 250).
4. **Creator Fee Split**: The creator allocates 100% of their trading fee revenue across 5 categories summing to 10,000 bps:
   `creatorShare + buybackShare + dividendsShare + liquidityShare + platformShare = 10,000 bps`

### Worked Numerical Example:
Suppose a user executes a **1.000 ETH** gross buy of a token configured with a **2.00% creator fee** (`buyFeeBps = 200`), with the creator fee split 50% to dividends and 50% to creator:
- **Platform Fee (1.00%)**: `1.000 ETH * 1.00% = 0.010 ETH` (accrues to Platform Treasury).
- **Creator Fee (2.00%)**: `1.000 ETH * 2.00% = 0.020 ETH`.
- **Net ETH into Curve**: `1.000 - 0.010 - 0.020 = 0.970 ETH` (used to mint tokens along the curve).
- **Creator Fee Allocation**:
  - Dividends (50%): `0.020 ETH * 50% = 0.010 ETH` distributed to token holders via `distributeDividends()`.
  - Creator Wallet (50%): `0.020 ETH * 50% = 0.010 ETH` credited to creator `claimFees()`.

### The 6 Creator UI Presets:
1. **Creator-Backed**: 100% of creator fees to creator wallet. Best for artists, builders, and direct venture funding.
2. **Diamond Hands**: 100% of creator fees to holder dividends. Rewards long-term holders with continuous ETH passive yield.
3. **Deflationary**: 100% of creator fees to buyback and burn. Systematically contracts circulating supply on every trade.
4. **Auto-LP**: 100% of creator fees to curve liquidity. Accelerates graduation and builds massive liquidity depth.
5. **Send to Seraph**: 100% of creator fees to the Seraph DAO treasury. Supports protocol development and grant funds.
6. **Custom**: Fully bespoke allocation across all 5 categories.

---

## 15.4 Mathematical Dividend Distribution Algorithm

Tokens launched with dividend splits distribute ETH yields proportionally to all token holders without requiring expensive loop iterations across thousands of addresses.

The algorithm uses a global accumulator:
`accDividendPerShare += (DeltaDividendEth * 10¹⁸) / EligibleTokenSupply`

### Per-User Claim Accounting:
For any token holder u with balance B_u:
`Claimable(u) = (B_u * accDividendPerShare) - rewardDebt_u`

### Secondary Transfer Conservation:
When holder u transfers A tokens to recipient r on secondary markets:
1. Holder u's unclaimed dividends are settled immediately:
   `claimableDividends_u += (B_u * accDividendPerShare) - rewardDebt_u`
2. Recipient r's unclaimed dividends are settled:
   `claimableDividends_r += (B_r * accDividendPerShare) - rewardDebt_r`
3. Balances update:
   `B_u = B_u - A,  B_r = B_r + A`
4. Reward debts update:
   `rewardDebt_u = B_u * accDividendPerShare`
   `rewardDebt_r = B_r * accDividendPerShare`

Our test suite proves that ping-ponging tokens through 10 sybil addresses never increases total claimable dividends by even a single wei.

---

## 15.5 Creator Playbook: Step-by-Step Launch Guide

### Step 1: Formulate Token Configuration
Define metadata, ticker, initial supply, fee caps (<= 2.5%), and select a fee preset.

### Step 2: Atomic Dev Buy (Optional up to 10%)
Creators can atomically purchase up to 10% (`MAX_DEV_BUY_BPS = 1000`) of the token supply in the exact same transaction as the launch. This prevents front-running snipers from buying before the creator.

### Step 3: Broadcast Launch
The creator broadcasts `launch(params)` payable with the required ETH:
```solidity
address tokenAddress = launchpad.launch{value: devBuyEth + launchFee}(params);
```

### Step 4: Community Trading & Pull-Escrow
Traders buy and sell on the curve. Fees accumulate in the contract's pull-escrow balance. Creators claim their ETH anytime via:
```solidity
launchpad.claimFees();
```
Because fees use **pull-escrow** rather than immediate pushes, malicious creator contracts with failing `receive()` fallbacks cannot freeze trading or create honeypots.

### Step 5: Graduation Threshold (`defaultGraduationThreshold = 4.5 ETH`)
When real quote reserves reach **4.5 ETH** (`defaultGraduationThreshold = 4.5 ether`):
- `L.graduated` becomes `true`.
- Trading on the bonding curve completes.
- Reserved tokens unlock from the bonding curve into liquidity escrow.
- The token graduates seamlessly to full pool trading or external AMM migration (Uniswap v3 / Aerodrome).

# Chapter 13: SER Tokenomics, Supply & Burns

## 13.1 Fixed Total Supply & Hard Cap

The native utility and governance token of Seraph Protocol is **SER**. The token is governed by a strictly immutable supply cap enforced at the smart contract level:

`MAX_SUPPLY = 100,000,000 * 10¹⁸ wei (100 Million SER)`

In `contracts/core/SERAPH.sol`:
```solidity
uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;

function mint(address to, uint256 amount) external onlyMinter {
    require(totalSupply() + amount <= MAX_SUPPLY, "SeraphToken: max supply exceeded");
    _mint(to, amount);
}
```
No administrative role, multisig, or governance proposal can ever expand supply beyond 100M tokens.

---

## 13.2 Genesis Token Allocation & Vesting Schedules

The 100,000,000 SER token allocation balances community participation, decentralized bootstrapping, and long-term protocol security:

```
                          100M SER ALLOCATION
   +--------------------------------------------------------------+
   | [====================] Presale & Community Tiers   (30.0%)   |
   | [==============]       Protocol Treasury & DAO     (25.0%)   |
   | [============]         Liquidity & DEX Bootstrapping(20.0%)  |
   | [=========]            Core Contributors & Team    (15.0%)   |
   | [======]               Ecosystem Grants & Research (10.0%)   |
   +--------------------------------------------------------------+
```

| Category | Allocation | Token Amount | Vesting Schedule |
| :--- | :--- | :--- | :--- |
| **Presale (Strategic, Private, Public)** | 30.0% | 30,000,000 SER | Strategic: 25% TGE, 14d cliff, 12m linear<br>Private: 20% TGE, 14d cliff, 12m linear<br>Public: 100% TGE unlock |
| **Protocol Treasury & DAO** | 25.0% | 25,000,000 SER | 5% max quarterly release cap via timelocked DAO vote |
| **Liquidity & DEX Bootstrapping** | 20.0% | 20,000,000 SER | Paired with presale ETH; LP tokens locked 24 months |
| **Core Contributors & Team** | 15.0% | 15,000,000 SER | 12-month cliff, 36-month continuous linear stream |
| **Ecosystem Grants & Research** | 10.0% | 10,000,000 SER | Milestone-gated via DAO proposals |

### Vesting Escrow Rules & Liquidity Locks:
1. **Core Team Escrow**: 15,000,000 SER is held in an on-chain vesting escrow contract. Zero tokens unlock for the first 12 months following TGE. At month 12, tokens begin continuous per-second linear streaming across 36 months (48 months total duration). Unvested tokens cannot be voted in governance.
2. **Treasury Release Governance**: The 25,000,000 SER treasury allocation is managed by the Protocol DAO (`0xa287FC2B8f89023eF1c82af09aee351cCdDa8a76`). A maximum of 5% of the remaining balance may be disbursed in any calendar quarter, requiring a minimum 5-day community vote and a 48-hour timelock execution window.
3. **Liquidity Pool Lock**: The 20,000,000 SER liquidity reserve is paired with presale ETH proceeds to seed the primary AMM pools (Uniswap v3 / Aerodrome). The resulting liquidity provider (LP) tokens are deposited into an immutable third-party lock contract for a minimum of 24 months, with on-chain lock receipts published publicly.
4. **Token Generation Event (TGE)**: Defined as the on-chain initialization event when `setPresale` and initial minting permissions are activated and public trading commences.

---

## 13.3 Multi-Faceted Token Utility

SER powers all economic activity across the Privacy Continuum:
1. **Gas Fee Settlement**: Primary gas asset for executing contracts and state transitions on Seraph EVM.
2. **Privacy Pool Collateral**: Staked or locked in `PrivacyPool` and `CollateralVault` to mint confidential synthetic `xUSD`.
3. **Decentralized Governance**: Token holders vote on protocol parameters, precompile additions, and treasury grants using anonymous zero-knowledge ballots.
4. **Relayer & Sequencer Staking**: Relayers bond SER to earn routing fees on the Cross-EVM Bridge and participate in block sequencing.

---

## 13.4 The Deflationary Sell Tax & Burn Engine

To ensure long-term value accrual and discourage predatory mercenary dumping, `SERAPH.sol` incorporates an automated sell-side fee mechanism:

- **Sell Tax Rate**: 1.00% (`SELL_TAX_BPS = 100`).
- **Burn Split**: 50% permanently burned (`BURN_BPS = 5000`).
- **Treasury Split**: 50% directed to the Protocol Treasury (`toTreasury = tax - burned`, official address: `0xa287FC2B8f89023eF1c82af09aee351cCdDa8a76`).

```
                               1.00% SELL TAX
                                     |
                   +-----------------+-----------------+
                   |                                   |
                   v                                   v
           0.50% PERMANENT BURN               0.50% PROTOCOL TREASURY
       Sent to address(0)                     Funds Ongoing Audits, Grants,
       totalSupply() permanently reduced      and Cross-Chain Infrastructure
```

### Invariant & Mathematical Proofs
Our test suite rigorously verifies two inviolable economic invariants across random fuzz actions (`PermitTaxAndPresaleStress.t.sol`):
1. **Supply Conservation**:
   `totalSupply() + totalBurned == totalMinted`
2. **Absolute Ceiling**:
   `totalSupply() <= MAX_SUPPLY`

### Zero Tax on Shielding & Unshielding:
Transfers into and out of the `PrivacyPool` are strictly exempt from the sell tax:
- `shield()`: 0% Tax.
- `privateTransfer()`: 0% Tax.
- `unshield()`: 0% Tax.
This guarantees that privacy preservation is never penalized with protocol friction.

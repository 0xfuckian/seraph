# Seraph: A Privacy Continuum Protocol

**Ian Mora**  
`ian@seraphprotocol.tech`  
[https://seraphprotocol.tech](https://seraphprotocol.tech)

**October 2026** — *Version 3.1 (Production Specification)*

---

### Abstract

Existing distributed ledger systems force an uncompromising trade-off: pure privacy coins provide robust default anonymity for value transfers but lack programmable smart contracts, whereas smart contract platforms offer arbitrary programmability at the expense of comprehensive metadata leakage and radical surveillance. Layer-2 privacy overlays attempt to bridge this divide but fragment the anonymity set and remain susceptible to exit-point correlation. We propose **Seraph**, a decentralized protocol that introduces a *Privacy Continuum* unifying sovereign privacy with general-purpose programmability. Seraph integrates a Monero-inspired UTXO settlement layer with dual private Ethereum Virtual Machine (EVM) execution environments that share a common cryptographic anonymity set. Value transfers are shielded by default using Pedersen commitments, zero-knowledge range constraints, and one-time stealth addresses, while smart contract execution supports confidential internal state without disclosing token balances, callers, or contract storage. We formalize the cryptographic note primitives, the incremental Merkle tree accumulator, the bonding-curve liquidity calculus, and the dual-EVM fraud-challenge dispute game.

---

### 1. Introduction

Commercial commerce on the internet has come to rely almost exclusively on financial institutions serving as trusted third parties to process electronic payments. While the system works well enough for most transactions, it still suffers from the inherent weaknesses of the trust-based model: completely non-reversible transactions are not really possible, and the cost of mediation increases transaction sizes, eliminating the possibility for small casual transactions.

In the domain of public blockchains, the challenge is inverted. While decentralization eliminates trusted intermediaries, complete transparency eliminates financial confidentiality. Transparent ledgers record sender, recipient, timestamp, and amount for every transaction in perpetuity. Cluster analysis, graph heuristics, and off-chain identity mappings degrade user autonomy and expose participants to targeted surveillance, sandwich attacks, and maximal extractable value (MEV) exploitation.

Attempts to introduce privacy have historically separated into two non-interoperable paradigms:

1. **Pure Privacy Coins (UTXO-based)**: Systems such as Monero and Zcash achieve unlinkability and confidentiality through stealth addresses, ring signatures (or full-chain membership proofs), and zero-knowledge commitments. However, their execution models are strictly non-Turing-complete, preventing the creation of decentralized lending markets, liquidity pools, automated market makers, and autonomous payment agents.
2. **Opt-in Smart Contract Privacy (EVM-based)**: Systems such as Tornado Cash, Aztec, or Railgun implement privacy as a smart contract application deployed on a transparent base chain. Because privacy is opt-in, only a small fraction of users participate, severely shrinking the effective anonymity set $S_{\text{anon}}$. Furthermore, users must cross transparent bridges to interact with external applications, generating observable correlation timings between deposits and withdrawals.

Seraph resolves this tension by treating privacy not as an isolated boolean flag, but as a continuous mathematical spectrum—the **Privacy Continuum**.

```
                THE PRIVACY CONTINUUM SPECTRUM
 Level 0                 Level 1               Level 2               Level 3
[ Transparent ] <---> [ Opt-in Shield ] <---> [ Default Strong ] <---> [ Confidential Compute ]
 Ethereum/Base         Shield/Unshield         Base Layer UTXO        Private EVM State
 Public Ledgers        PrivacyPool.sol         Stealth + Commit       ZK Contract Logic
```

By coupling a sovereign Monero-inspired settlement layer with two zero-knowledge private EVMs through shared note commitment trees, Seraph provides Monero-grade default privacy for value transfers while hosting Solidity-compatible private state transitions.

---

### 2. The Privacy Continuum Architecture

Seraph structures state transitions across four progressive privacy tiers, allowing applications and users to select the minimum disclosure necessary for their cryptographic use case:

```
+-----------------------------------------------------------------------------------+
|                              SERAPH PROTOCOL STACK                                |
+-----------------------------------------------------------------------------------+
|  Level 3: Private Compute EVM (Confidential Contracts, ZK Execution)              |
|  Level 2: Sovereign Base Layer (Pedersen Commitments, Bulletproofs++, Stealth)    |
|  Level 1: Shielded Pools (PrivacyPool.sol, Ring-Buffer Root Accumulator)          |
|  Level 0: Transparent Verification (Public Invariants, Bridge Settlement)         |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------+     +-----------------------+     +-----------------------+
|      Seraph EVM       | <-> |   Shared Note Pool    | <-> |        XMR EVM        |
|  (General Programmable|     |  (Depth-20 Merkle Tree|     | (Native Monero Gas &  |
|   Private Contracts)  |     |   1,048,576 Capacity) |     |  Preferential Settl.) |
+-----------------------+     +-----------------------+     +-----------------------+
            ^                                                           ^
            |                                                           |
            +------------ [ Trust-Minimized CrossEVMBridge ] -----------+
```

- **Level 0 (Transparent)**: Deterministic, publicly auditable transactions compatible with external EVM networks. Used for liquidity bootstrapping, cross-chain bridge validation, and verifiable supply invariants.
- **Level 1 (Optional Shielding)**: Users deposit transparent tokens ($SER$) into an Incremental Merkle Tree vault (`PrivacyPool.sol`), receiving an unspent private note commitment. Tokens are shielded on entry and unshielded on exit with zero secondary trading tax.
- **Level 2 (Default Strong Privacy)**: Native UTXO transactions on the Seraph Base Layer. All balances are encrypted with Pedersen commitments, senders use one-time stealth addresses, and inputs are spent via unique nullifiers.
- **Level 3 (Private Computation)**: General-purpose smart contract execution where internal contract storage variables, function arguments, and caller identities remain confidential, proven through succinct non-interactive arguments of knowledge (zk-SNARKs).

---

### 3. Transactions and Cryptographic Note Primitives

We define a private transaction as an immutable state transition consuming a set of input notes $\mathcal{N}_{\text{in}}$ and producing a set of output notes $\mathcal{N}_{\text{out}}$, satisfying exact balance conservation without revealing individual values or participants.

#### 3.1 Note Structure

A note $\mathbf{n}$ is a 5-tuple:
$$\mathbf{n} = (v, \text{pk}_{\text{recip}}, r, \rho, \alpha)$$
where:
- $v \in [0, 2^{64}-1]$ is the confidential asset quantity.
- $\text{pk}_{\text{recip}} \in \mathbb{G}$ is the recipient's public key.
- $r \in \mathbb{F}_q$ is a cryptographically secure random blinding factor ($256\text{-bit}$).
- $\rho \in \mathbb{F}_q$ is a unique note identifier seed.
- $\alpha \in \{0, 1, \dots, 2^{32}-1\}$ is the asset identifier ($\alpha = 0$ for $SER$, $\alpha = 1$ for $XMR$).

#### 3.2 Note Commitment

The note commitment $C$ is a hiding and binding cryptographic commitment computed as:
$$C = \mathcal{H}_{\text{comm}}(\alpha \,\|\, v \,\|\, \text{pk}_{\text{recip}} \,\|\, r)$$
where $\mathcal{H}_{\text{comm}}: \{0,1\}^* \to \mathbb{F}_q$ is a collision-resistant hash function (Poseidon over the BN254 scalar field for SNARK efficiency, or Keccak-256 for EVM Level-1 compatibility).

In the homomorphic Pedersen formulation on the base layer:
$$C_{\text{Pedersen}} = v \cdot G + r \cdot H + \alpha \cdot G_{\alpha}$$
where $G, H, G_{\alpha} \in \mathbb{G}$ are orthogonal generator points with unknown discrete logarithm relationships.

#### 3.3 Nullifier Derivation

To prevent double-spending without revealing which note was spent, every spent note reveals a unique nullifier $N$. Knowledge of the secret spend key $\text{sk}_{\text{spend}}$ is required to compute $N$:
$$N = \mathcal{H}_{\text{null}}(\text{sk}_{\text{spend}} \,\|\, \text{leaf\_index} \,\|\, \rho)$$
where $\text{leaf\_index} \in [0, 2^{20}-1]$ is the leaf position of commitment $C$ in the global Merkle tree.

```
                    NOTE CREATION & SPEND LIFECYCLE
                    
    [ Sender ]                                              [ Recipient ]
        |                                                         |
        |--- 1. Generate ephemeral keypair (e, E = e*G) --------->|
        |--- 2. Compute shared secret S = e * pk_recip ---------->|
        |--- 3. Derive one-time stealth address P --------------->|
        |--- 4. Compute commitment C = Hash(v, P, r, alpha) ----->|
        |                                                         |
        +=============> INSERT INTO MERKLE TREE <=================+
                                    |
                            [ Tree Accumulator ]
                                    |
        +=============< RETRIEVE MEMBERSHIP PROOF <===============+
        |                                                         |
    [ Spender ]                                                   |
        |                                                         |
        |--- 5. Derive nullifier N = Hash(sk_spend, leaf, rho) -->|
        |--- 6. Generate zk-SNARK proof pi --------------------->|
        |--- 7. Submit (N, C_new, pi, Root) to PrivacyPool ------>|
        |                                                         |
        v                                                         v
   [ Nullifier Registry: N marked spent ]    [ New Leaf C_new inserted ]
```

Because $\mathcal{H}_{\text{null}}$ is collision-resistant and pseudo-random, $N$ is completely unlinkable to $C$. An observer inspecting the on-chain nullifier set $\mathcal{S}_{\text{null}}$ learns only that *some* valid note in the Merkle tree was spent, without learning its index, value, or owner.

#### 3.4 Stealth Address Protocol

Recipients publish a dual-key stealth meta-address $(\mathbf{A}, \mathbf{B})$, where $\mathbf{A} = a \cdot G$ is the view public key and $\mathbf{B} = b \cdot G$ is the spend public key.

1. The sender generates an ephemeral scalar $e \xleftarrow{\$} \mathbb{F}_q$ and computes the ephemeral public key:
   $$E = e \cdot G$$
2. The sender computes the shared Diffie-Hellman secret:
   $$S = e \cdot \mathbf{A} = e \cdot a \cdot G = a \cdot E$$
3. The sender derives the one-time destination public key:
   $$P = \mathbf{B} + \mathcal{H}_s(S) \cdot G$$
4. The recipient scans transactions using private view key $a$:
   $$S' = a \cdot E = a \cdot e \cdot G = S$$
   $$P' = \mathbf{B} + \mathcal{H}_s(S') \cdot G = P$$
5. When $P' == P$, the recipient spends the note using one-time private key:
   $$x = b + \mathcal{H}_s(S') \pmod q$$

---

### 4. Incremental Merkle Accumulator & Ring-Buffer Roots

Notes are accumulated in a sparse incremental Merkle tree of depth $D = 20$, providing an anonymity set capacity of:
$$|\mathcal{A}| = 2^{20} = 1,048,576 \text{ notes}$$

```
                          DEPTH-20 MERKLE TREE
                                 Root R
                                /      \
                             H_1,0     H_1,1
                            /    \     /    \
                          ...    ... ...    ...
                          /        \
                        C_0        C_1  ...  C_(2^20-1)
                     (Leaf 0)   (Leaf 1)   (Leaf 1,048,575)
```

#### 4.1 Canonical Sorted-Pair Hashing

To defend against second-preimage attacks and optimize circuit constraints, internal nodes are evaluated using canonical pair ordering:
$$H_{d, i} = \mathcal{H}_{\text{tree}}\big(\min(H_{d-1, 2i},\, H_{d-1, 2i+1}),\; \max(H_{d-1, 2i},\, H_{d-1, 2i+1})\big)$$

#### 4.2 Historic Root Ring Buffer

In distributed asynchronous networks, transactions submitted during block $t$ may be mined at block $t + \delta$, during which subsequent insertions advance the tree root from $R_t$ to $R_{t+\delta}$. Rejecting transactions with non-latest roots introduces severe denial-of-service vulnerabilities under high load.

Seraph implements a constant-space cyclic ring buffer of capacity $K = 100$:
$$\mathcal{R} = \{ R_0, R_1, \dots, R_{K-1} \}$$
$$R_{\text{idx}} \leftarrow R_{\text{new}}, \quad \text{idx} \leftarrow (\text{idx} + 1) \bmod K$$

A root $R$ is verified valid if and only if:
$$\exists k \in [0, K-1] \quad \text{s.t.} \quad \mathcal{R}[k] = R$$

---

### 5. Zero-Knowledge Spend Circuit Specification

Private note transfers execute under a zero-knowledge proof system $\Pi = (\text{KeyGen}, \text{Prove}, \text{Verify})$ verifying relations in Rank-1 Constraint Systems (R1CS).

```
+-------------------------------------------------------------------------------+
|                       CIRCUIT: spend.circom (R1CS)                            |
+-------------------------------------------------------------------------------+
|  PUBLIC SIGNALS:                                                              |
|    - Root R               (Current or historic Merkle root)                   |
|    - Nullifiers N_in[k]   (Unique spend identifiers)                          |
|    - Commitments C_out[m] (Fresh output notes)                                |
|    - alpha                (Asset ID: SER = 0, XMR = 1)                        |
|                                                                               |
|  PRIVATE WITNESS:                                                             |
|    - Values v_in[k], v_out[m]                                                 |
|    - Blinding factors r_in[k], r_out[m]                                       |
|    - Spend keys sk_spend[k]                                                   |
|    - Merkle paths path_elements[k][20], path_indices[k][20]                   |
|                                                                               |
|  CONSTRAINTS ENFORCED:                                                        |
|    1. Tree Membership:     VerifyMerkleProof(R, C_in[k], path[k]) == 1        |
|    2. Nullifier Derivation: N_in[k] == Hash(sk_spend[k], leafIndex[k], rho[k])|
|    3. Balance Conservation: Sum(v_in[k]) == Sum(v_out[m]) + Fee               |
|    4. 64-Bit Range Proofs: v_out[m] in [0, 2^64 - 1] (No arithmetic overflow) |
+-------------------------------------------------------------------------------+
```

#### 5.1 Balance Conservation Invariant

The circuit enforces strict conservation of value across private input notes and output notes, preventing unauthorized token generation:
$$\sum_{i=1}^{k} v_{\text{in}}^{(i)} = \sum_{j=1}^{m} v_{\text{out}}^{(j)} + v_{\text{fee}}$$
where $v_{\text{fee}} \ge 0$ is the transparent relayer or network gas fee.

#### 5.2 64-Bit Range Constraint

To prevent integer underflow attacks where negative values wrap around modulo $q$, every output value $v_{\text{out}}$ must satisfy:
$$v_{\text{out}} < 2^{64}$$
This is proven via binary bit decomposition:
$$v = \sum_{b=0}^{63} 2^b \cdot z_b, \quad \text{where } z_b \cdot (1 - z_b) = 0 \quad \forall b \in [0, 63]$$

---

### 6. Dual-EVM Execution, Gas Abstraction & Bridge Economics

Seraph deploys two specialized execution layers alongside the base layer:

```
               CROSS-EVM TRUST-MINIMIZED BRIDGE ARCHITECTURE

    [ Seraph EVM ]                                            [ XMR EVM ]
          |                                                        |
          |--- 1. User locks SER in CrossEVMBridge --------------->|
          |    (emits Locked(batchId, amount, recipient))          |
          |                                                        |
          v                                                        v
   [ Bonded Relayer ]                                      [ Bonded Relayer ]
   (Posts 1.0 ETH Bond)                                    (Posts 1.0 ETH Bond)
          |                                                        |
          |--- 2. Submit state root batch to target chain -------->|
          |                                                        |
          +================= 1-HOUR CHALLENGE WINDOW =============+
          |                                                        |
    [ Honest Case ]                                        [ Malicious Case ]
   No challenge in 1 hour                                 Guardian challenges fraud
   Batch finalized.                                       Relayer bond slashed 100%:
   Recipient calls claimBridged()                         - 50% burned
   Minting succeeds.                                      - 50% awarded to challenger
```

#### 6.1 Gas Abstraction via Nullifier Vouchers

To interact with EVM smart contracts without acquiring native gas tokens, users pay fees in $SER$ or $wXMR$ using cryptographic gas vouchers.

A voucher commitment is initialized:
$$V = \mathcal{H}_{\text{vouch}}(v_{\text{fee}} \,\|\, \text{pk}_{\text{relayer}} \,\|\, r_{\text{vouch}})$$

The user signs an execution payload $(T, \text{data}, \text{maxFee})$ off-chain. The relayer submits the transaction through `GasRelayer.sol`, executing the target contract call while claiming $v_{\text{fee}}$ directly from the contract's voucher pool. Target calls to fee tokens, relayer contracts, or zero addresses are strictly rejected (`ForbiddenTarget()`).

#### 6.2 Relayer Game Theory and Fraud Slashing

Relayers must post a minimum bond $\beta = 1.0 \text{ ETH}$ before proposing cross-chain state roots. Every proposed batch enters a challenge period:
$$T_{\text{challenge}} = 3600 \text{ seconds (1 hour)}$$

Let $V_{\text{batch}}$ be the value of bridged assets in a proposed batch. If a relayer submits an invalid Merkle root:
1. Any network guardian can submit a fraud proof $\pi_{\text{fraud}}$ within $T_{\text{challenge}}$.
2. Upon verification, the relayer's bond is slashed:
   $$\text{Reward}_{\text{guardian}} = \frac{1}{2} \beta, \quad \text{Burn} = \frac{1}{2} \beta$$
3. To prevent front-running unbonding attacks, relayers calling `unbondRelayer()` are locked for at least 1 hour following their latest submitted batch:
   $$t_{\text{unbond}} \ge t_{\text{last\_batch}} + T_{\text{challenge}}$$

---

### 7. First-Party Protocol Modules & Bonding Curve Calculus

#### 7.1 Virtual-Reserve Constant-Product Bonding Curve

The Seraph Launchpad executes autonomous token price discovery on a virtual-reserve curve before graduating into a locked constant-product automated market maker (AMM).

```
                             BONDING CURVE DYNAMICS
   Price P
      ^
      |                                              / (Graduation to AMM Pool)
      |                                      . - - -
      |                              . - - '
      |                      . - - '
      |              . - - '
      |      . - - '
      | . - '
      +----------------------------------------------------> Supply Sold s
      0                                                 sellableTokens
```

The curve invariant is defined by virtual quote reserves $Q_v$ and token reserves $R_t$:
$$\big(R_q + Q_{\text{phantom}}\big) \cdot R_t = k$$
where:
- $R_q$ is the real quote asset reserve collected (e.g. $ETH$).
- $Q_{\text{phantom}}$ is the virtual liquidity offset establishing the starting price $P_0$.
- $R_t$ is the circulating token reserve remaining in the curve.

The spot price $P(s)$ as a function of sold supply $s$ is:
$$P(s) = \frac{dQ}{ds} = \frac{k}{(R_{t,\text{init}} - s)^2}$$

When a buyer submits $\Delta Q_{\text{gross}}$ quote currency:
1. Protocol fee $f_{\text{plat}} = 1.0\%$ (100 bps) and creator fee $f_{\text{creat}} \le 2.5\%$ (250 bps) are deducted:
   $$\Delta Q_{\text{net}} = \Delta Q_{\text{gross}} \cdot \big(1 - f_{\text{plat}} - f_{\text{creat}}\big)$$
2. The token quantity received $\Delta T$ is computed by constant-product substitution:
   $$\Delta T = R_t - \frac{k}{(R_q + Q_{\text{phantom}}) + \Delta Q_{\text{net}}}$$
3. Clamping and Graduation: If $\Delta T > R_{t,\text{sellable}}$, the purchase is clamped to $\Delta T_{\text{max}} = R_{t,\text{sellable}}$. The exact required quote amount $\Delta Q_{\text{exact}}$ is computed, and all excess quote funds are refunded in the same transaction:
   $$\Delta Q_{\text{refund}} = \Delta Q_{\text{gross}} - \Delta Q_{\text{exact}}$$
   The launch status transitions to `graduated = true`, unlocking `reservedTokens` to form a permanent liquidity pool.

#### 7.2 Five-Way Fee Split & $O(1)$ Magnified Dividend Accumulator

Creator fees are partitioned at launch into an immutable 5-way split:
$$\sum_{i=1}^{5} \omega_i = 10{,}000 \text{ bps } (100\%)$$
destined for Creator ($w_1$), Buyback & Burn ($w_2$), Holder Dividends ($w_3$), Auto-LP ($w_4$), and Treasury ($w_5$).

To distribute holder dividends ($w_3$) across thousands of circulating token holders without iterating over account balances (which would induce $O(n)$ gas exhaustion), Seraph implements an $O(1)$ magnified accumulator:
$$\text{accDividendPerShare}_{t} = \text{accDividendPerShare}_{t-1} + \left\lfloor \frac{\Delta Q_{\text{div}} \cdot 10^{36}}{\mathcal{S}_{\text{circulating}}} \right\rfloor$$
where $\mathcal{S}_{\text{circulating}} = \text{totalSupply} - \text{balance}(\text{curve})$.

When user $i$ with token balance $B_i$ updates their position or claims dividends:
$$\text{Accumulated}_i = \left\lfloor \frac{B_i \cdot \text{accDividendPerShare}}{10^{36}} \right\rfloor$$
$$\text{Claimable}_i = \text{Accumulated}_i - \text{rewardDebt}_i$$

To guarantee mathematical solvency against phantom 1-wei rounding drift, reward debt updates enforce ceiling division:
$$\text{rewardDebt}_i = \left\lceil \frac{B_i \cdot \text{accDividendPerShare}}{10^{36}} \right\rceil = \left\lfloor \frac{B_i \cdot \text{accDividendPerShare} + 10^{36} - 1}{10^{36}} \right\rfloor$$

#### 7.3 Over-Collateralized Stablecoins ($xUSD$) & AI Compute Vaults

- **CollateralVault ($xUSD$)**: Accepts $SER$ and $wXMR$ collateral at minimum collateralization ratio $\text{MCR} = 150\%$ ($\text{MIN\_COLLATERAL\_RATIO\_BPS} = 15{,}000$). Direct mint/burn by non-vault addresses is cryptographically prohibited.
- **UsageVault (AI Payments)**: AI consumers lock credits via secret preimages $H_{\text{credit}} = \mathcal{H}(\sigma)$. Metered API queries redeem micro-credits via single-use nullifiers, providing anonymous, untraceable compute verification.

---

### 8. Token Economics & Piecewise Continuous Vesting Mathematics

The native token $SER$ has a fixed maximum supply of $100{,}000{,}000 \text{ SER}$ ($10^8 \cdot 10^{18} \text{ wei}$) enforced at the EVM contract level:
$$\text{totalSupply} \le \text{MAX\_SUPPLY}$$

```
                          SER ALLOCATION BREAKDOWN
    +-----------------------------------------------------------------+
    | Ecosystem & Community (40%)                       |  40,000,000 |
    | Team & Advisors (20% · 4-yr vest, 1-yr cliff)     |  20,000,000 |
    | Foundation / Treasury (15%)                       |  15,000,000 |
    | Early Contributors (15% · Presale Strategic/Priv) |  15,000,000 |
    | Public Sale & Initial Liquidity (10%)             |  10,000,000 |
    +-----------------------------------------------------------------+
    | Total Maximum Supply                              | 100,000,000 |
    +-----------------------------------------------------------------+
```

#### 8.1 Presale Tier Schedule

The presale offers exactly $25{,}000{,}000 \text{ SER}$ across three tiers:
1. **Strategic (Tier 1)**: $\$0.02 / \text{SER}$, hard cap $3.75\text{M SER}$, allowlist required, $25\%$ unlocked at TGE, 14-day cliff, 12-month linear vesting.
2. **Private (Tier 2)**: $\$0.03 / \text{SER}$, hard cap $11.25\text{M SER}$, allowlist required, $20\%$ unlocked at TGE, 14-day cliff, 12-month linear vesting.
3. **Public (Tier 3)**: $\$0.04 / \text{SER}$, hard cap $10.00\text{M SER}$, open access, $100\%$ unlocked at TGE (fully liquid).

#### 8.2 Piecewise Continuous Vesting Function

For an allocation $A_{\text{total}}$ with TGE basis points $\lambda \in [0, 10{,}000]$ ($\text{lockupBps}$), cliff period $T_{\text{cliff}} = 14 \text{ days}$, and vesting duration $D = 365 \text{ days}$, the vested tokens $V(t)$ at elapsed time $t = \tau - \tau_{\text{TGE}}$ satisfy the piecewise function:

$$V(t) = \begin{cases} 
0 & \text{if } t < 0 \\
A_{\text{total}} \cdot \frac{\lambda}{10{,}000} & \text{if } 0 \le t < T_{\text{cliff}} \\
A_{\text{total}} \cdot \frac{\lambda}{10{,}000} + \left(A_{\text{total}} - A_{\text{total}} \cdot \frac{\lambda}{10{,}000}\right) \cdot \frac{\min(t - T_{\text{cliff}},\, D)}{D} & \text{if } t \ge T_{\text{cliff}}
\end{cases}$$

At $t \ge T_{\text{cliff}} + D$:
$$V(t) = A_{\text{total}}$$
Zero additional tokens can ever be minted or claimed beyond $A_{\text{total}}$, preventing post-duration supply inflation.

---

### 9. Security Model and Invariant Verification

The protocol's security model was validated through exhaustive invariant-based fuzz testing ($896{,}000$ stateful assertions with zero reverts) and multi-actor adversarial testing ($209$ passing automated suites).

```
                      FORMAL PROTOCOL INVARIANTS
+-----------------------------------------------------------------------------+
| Invariant 1: Privacy Pool Solvency                                          |
|   Balance_SER(PrivacyPool) == TotalShielded - TotalUnshielded               |
+-----------------------------------------------------------------------------+
| Invariant 2: Total Supply Conservation                                      |
|   totalSupply(SER) + totalBurned(SER) == totalMinted(SER) <= MAX_SUPPLY     |
+-----------------------------------------------------------------------------+
| Invariant 3: Zero Flash-Loan Curve Extraction                               |
|   For all buyEth > 0: sell(buy(buyEth)) < buyEth                            |
+-----------------------------------------------------------------------------+
| Invariant 4: CDP Solvency & Non-Violation of MCR                            |
|   Collateral_Value / Debt_Value >= 150% (MCR) for all solvent positions     |
+-----------------------------------------------------------------------------+
| Invariant 5: Dividend Solvency with Ceiling Debt Rounding                   |
|   TotalClaimableDividends <= Contract_ETH_Balance                           |
+-----------------------------------------------------------------------------+
```

---

### 10. Development Roadmap & Verifiable Implementation

```
                               ROADMAP PHASES
 Phase 1: PoC               Phase 2: MVP             Phase 3: Alpha (CURRENT)
 [ 100% COMPLETE ]          [ 100% COMPLETE ]        [ ~75% COMPLETE ]
 - Rust Note Ledger         - Base Sepolia Deploy    - Stateful Fuzzing
 - Circom Circuits          - Web3 UI & SDK          - Multi-Actor Tests
 - CLI Wallet Primitives    - Live Testnet Txs       - First-Party Modules
                                      |
                                      v
                             Phase 4: Beta            Phase 5: Mainnet v1.0
                             [ UPCOMING ]             [ LAUNCH ]
                             - Client-side WASM ZK    - Production Audits
                             - Rust seraphd Daemon    - Decentralized Sequencer
                             - Relayer Network        - Token Generation Event
```

#### Verified Testnet Contracts (Base Sepolia — Chain ID `84532`)

| Contract Entity | Verified On-Chain Address |
| :--- | :--- |
| **SeraphToken ($SER$)** | `0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F` |
| **SeraphPresale** | `0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE` |
| **PrivacyPool** | `0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6` |
| **SeraphLaunchpad** | `0xe0349E4cC431329207e98C5205062776e058A846` |
| **CrossEVMBridge** | `0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d` |
| **GasRelayer** | `0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885` |
| **InvoiceRegistry** | `0xF5eC3a1CE0A1e2905401A78984b44631e931A733` |
| **UsageVault** | `0x455e6fd221f4Eef8a0Eb78307d61Aa87e95F9E90` |
| **CollateralVault** | `0xc6031429AAF8BEaB631b75C29f5Bb0D3701169aB` |
| **PrivateStablecoin ($xUSD$)** | `0xC505C55024eD8930c79f153DDbCE2A3224EB48F0` |
| **Testnet USDT ($tUSDT$)** | `0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397` |
| **Testnet USDC ($tUSDC$)** | `0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0` |
| **Testnet Wrapped XMR ($tWXMR$)** | `0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A` |

---

### 11. Conclusion

We have proposed Seraph, a privacy continuum protocol uniting default-strong value transfer with programmable confidential execution. By integrating a Monero-inspired settlement layer with dual private EVMs through shared note trees, Seraph eliminates the forced trade-off between privacy and programmability. On-chain validation across 13 deployed contracts, 209 automated verification suites, and 896,000 stateful invariant checks demonstrates that mathematical privacy and smart contract composability can co-exist within a single unified decentralized architecture.

---

### References

1. Nakamoto, S. (2008). *Bitcoin: A Peer-to-Peer Electronic Cash System*.
2. van Saberhagen, N. (2013). *CryptoNote v 2.0*.
3. Bünz, B., Bootle, J., Boneh, D., Poelstra, A., Wuille, P., & Maxwell, G. (2018). *Bulletproofs: Short Proofs for Confidential Transactions and More*. IEEE S&P.
4. Ben-Sasson, E., Chiesa, A., Tromer, E., & Virza, M. (2014). *Zerocash: Decentralized Anonymous Payments from Bitcoin*. IEEE S&P.
5. Grassi, L., Khovratovich, D., Rechberger, C., Schofnegger, M., & Subotic, R. (2021). *Poseidon: A New Hash Function for Zero-Knowledge Proof Systems*. USENIX Security.
6. Hopwood, D., Bowe, S., Hornby, T., & Wilcox, Z. (2016). *Zcash Protocol Specification*.
7. Buterin, V. (2014). *Ethereum: A Next-Generation Smart Contract and Decentralized Application Platform*.

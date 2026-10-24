# Chapter 9: Sequencer Architecture & MEV Shielding

## 9.1 The MEV Vulnerability in Transparent Blockchains

On public smart contract networks, transactions wait in a transparent memory pool (mempool) prior to block inclusion. This allows predatory searchers and maximal extractable value (MEV) bots to:
1. **Front-Run**: Detect profitable DEX trades and insert their own transaction ahead by paying higher priority gas.
2. **Sandwich Attack**: Enclose a user's swap between a buy and sell transaction, intentionally extracting slippage from ordinary users.
3. **Censorship & Liquidation Sniping**: Reorder transactions to trigger liquidations or censor privacy transactions.

In a privacy protocol, MEV poses an existential threat: if transaction ordering or metadata leaks before execution, privacy guarantees can be severely compromised.

---

## 9.2 Encrypted Mempool Architecture

Seraph deploys an **Encrypted Mempool with Threshold Cryptography** to eliminate front-running and toxic MEV:

```
 User Client                                     Sequencer Cluster                             Block Proposer
      │                                                  │                                            │
      │ 1. Encrypts tx with threshold public key (T-PK)  │                                            │
      ├─────────────────────────────────────────────────>│                                            │
      │                                                  │ 2. Orders encrypted transactions           │
      │                                                  │    into deterministic sequence batch       │
      │                                                  │ ──────────────────────────────────────────>│
      │                                                  │                                            │ 3. Commits to ordered batch
      │                                                  │                                            │    (Batch Hash recorded on-chain)
      │                                                  │                                            │
      │                                                  │ 4. Sequencer nodes publish threshold       │
      │                                                  │    decryption shares (t-of-n)              │
      │                                                  │ <──────────────────────────────────────────│
      │                                                  │                                            │
      │                                                  │ 5. Transactions decrypted & executed       │
      │                                                  │    in exact committed order                │
```

### Protocol Steps:
1. **Client-Side Encryption**: When a user constructs a transaction, the payload (recipient, function selector, parameters, value) is encrypted using a distributed **Threshold Public Key ($PK_{\text{thresh}}$)**:
   $$C_{\text{tx}} = \text{Encrypt}(PK_{\text{thresh}}, \text{tx})$$
   Only the gas bid and sender's zero-knowledge validity proof are visible to relayers.
2. **Order Commitment**: Sequencer nodes receive $C_{\text{tx}}$ and commit to an immutable ordered sequence:
   $$H_{\text{batch}} = \text{Keccak256}(C_1 \mathbin{\Vert} C_2 \mathbin{\Vert} \dots \mathbin{\Vert} C_k)$$
   Once $H_{\text{batch}}$ is posted to the base layer, the transaction order is mathematically locked and cannot be altered.
3. **Threshold Decryption**: A distributed committee of $n$ validator nodes each release an ephemeral decryption key share. Once $t$ of $n$ shares (e.g., 5-of-7 quorum) are broadcast, the full batch is decrypted simultaneously.
4. **Deterministic Execution**: The decrypted transactions are executed in the exact pre-committed order. Because searchers cannot see trade parameters before the order is fixed, front-running and sandwiching are mathematically impossible.

---

## 9.3 Protection Against Toxic MEV

| Attack Vector | Vulnerability on Public EVMs | Mitigation on Seraph Dual EVMs |
| :--- | :--- | :--- |
| **DEX Sandwich Attacks** | Searchers front-run & back-run slippage | **Impossible**: Swap amounts and paths are hidden inside threshold ciphertext until execution order is locked. |
| **Liquidation Front-Running** | Bots compete for liquidation priority gas | **Fair Ordering**: First-seen encrypted batches are executed sequentially without priority auction bidding. |
| **Statistical Arbitrage** | Bots front-run oracle price updates | **Time-locked Batches**: Price updates and user transactions settle within atomic execution blocks. |
| **Censorship** | Validators selectively exclude privacy txs | **Zero Metadata**: Validators cannot distinguish between privacy pool deposits, transfers, and standard swaps. |

---

## 9.4 Decentralized Sequencer Rotation & Fault Recovery

To prevent single-point-of-failure centralization, Seraph implements a **Decentralized Sequencer Set (DSS)**:
1. **Epoch-Based Rotation**: A new primary sequencer is elected deterministically every 100 blocks based on bonded SER stake.
2. **Slashing for Non-Liveness**: If a sequencer fails to submit a batch within the 2-second block window, the standby backup sequencer immediately takes over, and the inactive sequencer's stake is slashed.
3. **Equivocation Slashing**: If a sequencer signs two conflicting batch orders for the same block height, an automated fraud proof slashes 100% of their bonded stake.

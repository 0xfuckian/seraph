# Chapter 5: Base Layer Protocol & State Machine

## 5.1 Protocol Architecture & Design Goals

The Seraph base layer is a custom high-performance blockchain node built in Rust (`seraph-base-layer`). It serves as the sovereign settlement substrate and shared anonymity pool for the entire Seraph ecosystem.

Unlike traditional EVM chains which record account balances directly in world state tries, the Seraph base layer maintains state purely through:
1. **The Global Commitment Tree**: An incremental Merkle tree accumulating all minted note commitments.
2. **The Nullifier Accumulator**: An append-only cryptographic registry of consumed nullifiers.

```
                           SERAPH BASE LAYER NODE
   +------------------------------------------------------------------+
   |  P2P Gossip Network (libp2p, Noise protocol, Tor/I2P routing)    |
   +------------------------------------------------------------------+
   |  Dual-Fee Engine (Native SER & Native XMR Settlement)            |
   +------------------------------------------------------------------+
   |  State Machine:                                                  |
   |    * Incremental Merkle Tree (2^20 Capacity per tree level)      |
   |    * Nullifier Double-Spend Prevention Engine                    |
   |    * Multi-Asset Domain Isolation (SER, XMR, Custom Tokens)      |
   +------------------------------------------------------------------+
   |  Storage Engine (RocksDB / Sled persistent embedded key-value)   |
   +------------------------------------------------------------------+
```

---

## 5.2 Block Structure, Consensus & Emergency Halt

### Block Header Specification
Every block header on the Seraph base layer contains:
- `version`: Protocol version integer (32-bit, default `1`).
- `previous_block_hash`: 32-byte cryptographic hash of parent block.
- `merkle_root`: Root of the transaction inclusion Merkle tree.
- `state_root`: Root of the active note commitment tree after processing all transactions.
- `nullifier_root`: Root of the newly consumed nullifiers batch.
- `timestamp`: 64-bit UTC UNIX timestamp.
- `height`: Monotonically increasing block index.
- `nonce`: Proof-of-work / validator signature depending on network phase.

### Consensus Specification Across Phases:
- **Phase 0 & Phase 1 (Core EVM & Devnet)**: Authority-validated sequencing with deterministic consensus for rapid integration and zero latency on Base Sepolia.
- **Phase 2 (Multi-Node Sovereign Testnet)**: Transition to a hybrid Proof-of-Stake / RandomX-variant checkpointing engine:
  - **Validator Selection**: Proportional to bonded SER stake (minimum 50,000 SER bond). Proposers are elected via verifiable random function (VRF) per slot.
  - **Fork Choice & Finality**: LMD-GHOST fork choice with Casper-FFG checkpoint finality every 32 slots (6.4-minute epochs).
  - **Slashing Penalties**: Equivocation (proposing two distinct blocks at the same height) triggers an immediate 100% bond slash. Inactivity results in a linear quadratic leak.
  - **Emergency Protocol Halt**: If a consensus vulnerability is detected, an emergency halt can be triggered by a 2/3 stake supermajority or the Guardian Council multisig, pausing block progression until a security patch lands.

---

## 5.3 Transactions and Enotes

In the Seraph base layer, transactions are strictly balance-conserving transitions consuming input notes and producing new output notes:

```rust
// Core Base-Layer Transaction Representation (base-layer/src/ledger.rs)
pub struct Transaction {
    pub inputs: Vec<[u8; 32]>,       // Spent note nullifiers
    pub outputs: Vec<Note>,          // New confidential notes
    pub fee_ser: u64,                // Fee paid in SER units
    pub fee_xmr: u64,                // Fee paid in atomic XMR units
    pub public_inputs: Vec<u8>,      // Merkle roots and public inputs
    pub proof: Vec<u8>,              // Cryptographic ZK spend proof
}
```

### Transaction Validation Rules:
1. **Nullifier Uniqueness**: Every input nullifier must not currently exist in the ledger's `nullifiers` set:
   `For all N_i in inputs: N_i not in Ledger.nullifiers`
2. **Atomic Nullifier Consumption**: All input nullifiers are inserted into `Ledger.nullifiers` within an atomic database transaction. If any nullifier fails, the entire transaction reverts.
3. **Commitment Insertion**: All output commitments `C_j = output_j.commitment()` are inserted sequentially into the commitment tree.
4. **Conservation of Value**: The sum of inputs must equal the sum of outputs plus specified fees across each distinct asset class.

---

## 5.4 Dual-Fee Engine: Native SER and Native XMR

A signature innovation of the Seraph base layer is its native **dual-currency fee engine**. Transactions can pay inclusion fees in either:
1. **SER (Native Protocol Token)**: Supporting deflationary burning and treasury allocation.
2. **XMR (Native Monero)**: Bridged or natively integrated, allowing Monero holders to settle transactions directly without holding secondary gas tokens.

### Fee Settlement Flow:
- When a user submits a transaction specifying `fee_xmr`, the transaction inputs consume atomic XMR enotes.
- Relayers or block proposers can receive fees in XMR directly into their private stealth addresses.
- Multi-asset isolation ensures that XMR and SER amounts never mix or cause rounding errors.

---

## 5.5 Multi-Asset Domain Isolation

Seraph avoids token cross-contamination by binding the `AssetId` directly into the leaf commitment hash:

```rust
// base-layer/src/assets.rs
pub enum AssetId {
    Seraph = 0,
    Xmr = 1,
    Custom(u32),
}

impl Note {
    pub fn commitment(&self) -> [u8; 32] {
        let mut hasher = Keccak256::new();
        hasher.update(self.asset.domain_tag());
        hasher.update(self.amount.to_be_bytes());
        hasher.update(self.recipient_pubkey);
        hasher.update(self.blinding);
        hasher.finalize().into()
    }
}
```

Even if an attacker crafts an XMR note with identical amount, recipient key, and blinding scalar as a SER note, the resulting commitments and nullifiers are cryptographically isolated.

---

## 5.6 Networking & P2P Topology

The networking stack scales through three distinct milestones:
1. **Phase 0 (In-Process PoC)**: Validated in Rust via multi-actor test harnesses (`tests/adversarial_pentest.rs`) confirming state transitions, mempool double-spend rejections, and ring buffer evictions.
2. **Phase 1 (Single-Node Devnet)**: Local RPC node exposing JSON-RPC over HTTP and WebSocket, integrated with the `@seraph-protocol/sdk`.
3. **Phase 2 (Multi-Node Testnet)**: Fully decentralized libp2p gossip mesh with:
   - Dandelion++ transaction dissemination to prevent IP address triangulation.
   - Built-in Tor and I2P daemon proxies for complete network-layer anonymity.

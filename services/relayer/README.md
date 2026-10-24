# Seraph Protocol Relayer Daemon

Automated Cross-Chain Bridge Batcher and Gas Abstraction Relayer Daemon for the **Seraph Protocol** ecosystem (connecting Seraph Base Layer, Seraph EVM, and XMR EVM).

---

## Overview

The `SeraphRelayerDaemon` runs as a high-throughput, fault-tolerant background service with two primary subsystems:

1. **Cross-Chain Bridge Batcher**:
   - Collects outbound bridge requests (`BridgeOut` items or `TokensLocked` on-chain event logs).
   - Constructs depth-appropriate binary Merkle trees using sorted-pair hashing with canonical `keccak256` or `sha256Tag("seraph_bridge_leaf_v1", ...)`.
   - Verifies relayer bond balances (`MIN_RELAYER_BOND >= 1 ether`) on `CrossEVMBridge`.
   - Submits `submitStateBatch(sourceChainId, stateRoot)` on-chain.
   - Generates and verifies cryptographic Merkle inclusion proofs for recipient cross-chain claims (`claimBridged`).

2. **Gas Abstraction Dispatcher**:
   - Accepts anonymous user execution vouchers (`voucherNullifier`, `feeToken`, `feeAmount`, `target`, `callData`).
   - Performs strict solvency verification (verifying voucher commitment pool reserves and anti-drain target protections).
   - Submits `executeWithGasAbstraction` on `GasRelayer` to execute user calls on-chain while collecting subsidy tokens (e.g., SERAPH or wXMR).
   - Prevents nullifier double-spends locally and against on-chain contract state.

```
+-------------------------------------------------------------------------+
|                        Seraph Relayer Daemon                            |
+------------------------------------+------------------------------------+
|     Cross-Chain Bridge Batcher     |     Gas Abstraction Dispatcher     |
+------------------------------------+------------------------------------+
| 1. Ingest TokensLocked events      | 1. Receive voucher execution req   |
| 2. Accumulate pending queue        | 2. Solvency & target check         |
| 3. Construct Merkle tree           | 3. Anti-double spend protection    |
| 4. Verify relayer bond (>= 1 ETH)  | 4. Dispatch executeWithGasAbstr    |
| 5. Submit submitStateBatch on EVM  | 5. Collect gas subsidy tokens      |
| 6. Serve Merkle claim proofs       | 6. Update accounting & history     |
+------------------------------------+------------------------------------+
                                    |
                                    v
     +-------------------------------------------------------------+
     |                 EVM Network (JSON-RPC)                      |
     |   - CrossEVMBridge (0x10f135b8004fB99eec3d7e7E4f652b477A14) |
     |   - GasRelayer     (0x8b5F2A84c7E1a37c0245a4944c6691c94488) |
     +-------------------------------------------------------------+
```

---

## Directory Structure

```
services/relayer/
├── package.json         # Package configuration & test scripts
├── tsconfig.json        # TypeScript configuration
├── README.md            # Operator & architectural documentation
├── src/
│   ├── index.ts         # Module exports & CLI bootstrap runner
│   ├── relayer.ts       # SeraphRelayerDaemon orchestrator
│   ├── bridgeBatcher.ts # Queue, Merkle tree construction & claim proofs
│   ├── gasDispatcher.ts # Solvency checks & gas subsidy dispatch
│   ├── merkle.ts        # Sorted-pair binary Merkle tree engine
│   ├── provider.ts      # EVM JSON-RPC provider & Mock provider
│   ├── types.ts         # TypeScript interfaces & types
│   └── crypto.ts        # Keccak256, sha256Tag, ABI codecs & selectors
└── test/
    └── relayer.test.mjs # 17 comprehensive unit & integration tests
```

---

## Configuration & Environment Variables

Configure the daemon using environment variables or programmatic options:

| Variable | Type | Default | Description |
|---|---|---|---|
| `RPC_URL` | string | `http://127.0.0.1:8545` | EVM JSON-RPC endpoint |
| `RELAYER_PRIVATE_KEY` | hex string | *(optional)* | Relayer private key for signing transactions |
| `RELAYER_ADDRESS` | address | `0x1111...1111` | Relayer EVM address |
| `CROSS_EVM_BRIDGE_ADDRESS` | address | `0x10f135b8...` | Deployed `CrossEVMBridge` contract address |
| `GAS_RELAYER_ADDRESS` | address | `0x8b5F2A84...` | Deployed `GasRelayer` contract address |
| `SOURCE_CHAIN_ID` | string | `seraph_evm` | Local chain identifier (or 32-byte hex) |
| `TARGET_CHAIN_ID` | string | `xmr_evm` | Target chain identifier (or 32-byte hex) |
| `BATCH_INTERVAL_MS` | number | `10000` (10s) | Interval between automated batch submissions |
| `MAX_BATCH_SIZE` | number | `64` | Maximum bridge items per single Merkle batch |
| `MIN_RELAYER_BOND` | bigint (wei) | `1000000000000000000` | Minimum bond required (1 ETH) |
| `MIN_FEE_THRESHOLD` | bigint (wei) | `0` | Minimum fee subsidy to accept gas voucher requests |
| `LEAF_HASHER` | `"keccak256"` \| `"sha256Tag"` | `"keccak256"` | Bridge leaf hashing algorithm |

---

## Quick Start

### 1. Run Tests

All tests run natively with zero external npm dependencies:

```bash
cd services/relayer
node --test test/*.test.mjs
```

### 2. Run the Daemon (CLI)

```bash
# Export environment variables
export RPC_URL="http://127.0.0.1:8545"
export RELAYER_ADDRESS="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
export CROSS_EVM_BRIDGE_ADDRESS="0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF"
export GAS_RELAYER_ADDRESS="0x8b5F2A84c7E1a37c0245a4944c6691c94488b394"
export BATCH_INTERVAL_MS="5000"

# Launch daemon
node src/index.ts
```

---

## Programmatic Usage

### Initializing the Daemon

```typescript
import { SeraphRelayerDaemon, HttpEVMProvider } from "@seraph-protocol/relayer";

const daemon = new SeraphRelayerDaemon({
  rpcUrl: "https://sepolia.seraph.network/rpc",
  relayerAddress: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  bridgeAddress: "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF",
  gasRelayerAddress: "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394",
  batchIntervalMs: 15_000,
  maxBatchSize: 64,
  minRelayerBond: 10n ** 18n, // 1 ETH
});

// Subscribe to daemon telemetry
daemon.on("batchSubmitted", (batch) => {
  console.log(`[Bridge] Batch #${batch.batchId} submitted! Root: ${batch.merkleRoot}`);
});

daemon.on("voucherDispatched", (rec) => {
  console.log(`[Gas] Executed call for target ${rec.target}. Subsidy: ${rec.feeAmount}`);
});

// Start background workers
await daemon.start();
```

### Ingesting Bridge Items & Querying Claims

```typescript
// Enqueue an outbound bridge transfer
daemon.ingestBridgeOut({
  nullifier: "0xabcdef...", // 32-byte nullifier
  recipient: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
  amount: 2500n * 10n ** 18n,
  destChainId: "xmr_evm",
});

// Flush or wait for automatic interval batching
const batch = await daemon.submitPendingBatch();

// Retrieve claim inclusion proof for recipient
const claim = daemon.getProofForClaim(batch.batchId, {
  recipient: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
});

console.log("Claim Merkle Proof:", claim.merkleProof);
console.log("Pre-encoded calldata for claimBridged:", claim.calldata);
```

### Relaying Transactions via Gas Abstraction

```typescript
// User submits an execution request paying 1 SERAPH for gas
const execution = await daemon.dispatchGasVoucher({
  voucherNullifier: "0x12345678...", // 32-byte unique voucher nullifier
  feeToken: "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F", // SERAPH
  feeAmount: 1n * 10n ** 18n,
  target: "0x5FbDB2315678afecb367f032d93F642f64180aa3", // e.g. InvoiceRegistry
  callData: "0x4e94e35b...", // Encoded function payload
});

console.log("Execution mined on-chain:", execution.txHash);
console.log("Subsidy collected:", execution.feeAmount);
```

### Health & Metrics Status

```typescript
const status = await daemon.status();
console.log({
  isRunning: status.isRunning,
  relayerBond: status.relayerBond.toString(),
  isBondSufficient: status.isBondSufficient,
  pendingBridgeItems: status.pendingBridgeItems,
  totalBatchesSubmitted: status.totalBatchesSubmitted,
  totalVouchersExecuted: status.totalVouchersExecuted,
  feesEarned: status.totalFeesEarned,
  uptimeSeconds: status.uptimeSeconds,
});
```

---

## Security Model & Invariants

1. **Relayer Bond Verification**:
   - `CrossEVMBridge` enforces `MIN_RELAYER_BOND = 1 ether`.
   - The daemon checks on-chain bonded status before attempting `submitStateBatch`.
   - Unbonded relayers are stopped before incurring on-chain gas revert penalties with `InsufficientRelayerBondError`.

2. **Merkle Tree Proof Verification**:
   - Leaves are computed as `keccak256(abi.encodePacked(nullifier, recipient, amount, localChainId))` (116 bytes), matching the Solidity contract byte-for-byte.
   - Merkle pair hashing uses commutative sorted order: `_hashSortedPair(a, b) = a <= b ? keccak256(a || b) : keccak256(b || a)`.
   - Any tampering with recipient, amount, nullifier, or proof elements causes verification failure.

3. **Gas Abstraction Solvency Protection**:
   - Every voucher execution verifies `voucherPoolBalance[feeToken] >= feeAmount`.
   - Double-spends are prevented both in-memory and against the contract's `usedVouchers` mapping.
   - Targets pointing to `address(0)`, `GasRelayer` itself, or the `feeToken` contract are rejected to prevent protocol drain attacks.

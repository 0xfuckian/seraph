import { pathToFileURL } from "node:url";
import { SeraphRelayerDaemon, InsufficientRelayerBondError } from "./relayer.ts";
import { CrossChainBridgeBatcher } from "./bridgeBatcher.ts";
import { GasAbstractionDispatcher } from "./gasDispatcher.ts";
import { MerkleTree } from "./merkle.ts";
import { HttpEVMProvider, MockEVMProvider } from "./provider.ts";
import {
  keccak256,
  keccak256Hex,
  sha256Tag,
  computeBridgeLeaf,
  computeBridgeLeafKeccak,
  computeBridgeLeafSha256,
  hashSortedPair,
  cleanHex,
  padHex64,
  toBuffer32,
  toAddressBuffer,
  toAddressHex,
  encodeSubmitStateBatch,
  encodeExecuteWithGasAbstraction,
  encodeClaimBridged,
  encodeBondRelayer,
  SELECTORS,
  EVENT_TOPICS,
} from "./crypto.ts";
import type { RelayerConfig } from "./types.ts";

export * from "./types.ts";
export {
  SeraphRelayerDaemon,
  InsufficientRelayerBondError,
  CrossChainBridgeBatcher,
  GasAbstractionDispatcher,
  MerkleTree,
  HttpEVMProvider,
  MockEVMProvider,
  keccak256,
  keccak256Hex,
  sha256Tag,
  computeBridgeLeaf,
  computeBridgeLeafKeccak,
  computeBridgeLeafSha256,
  hashSortedPair,
  cleanHex,
  padHex64,
  toBuffer32,
  toAddressBuffer,
  toAddressHex,
  encodeSubmitStateBatch,
  encodeExecuteWithGasAbstraction,
  encodeClaimBridged,
  encodeBondRelayer,
  SELECTORS,
  EVENT_TOPICS,
};

/**
 * Creates a SeraphRelayerDaemon from environment variables
 */
export function createRelayerFromEnv(): SeraphRelayerDaemon {
  const bridgeAddress =
    process.env.CROSS_EVM_BRIDGE_ADDRESS ||
    process.env.BRIDGE_ADDRESS ||
    "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF";
  const gasRelayerAddress =
    process.env.GAS_RELAYER_ADDRESS ||
    "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394";

  const config: RelayerConfig = {
    rpcUrl: process.env.RPC_URL || "http://127.0.0.1:8545",
    privateKey: process.env.RELAYER_PRIVATE_KEY,
    relayerAddress: process.env.RELAYER_ADDRESS,
    bridgeAddress,
    gasRelayerAddress,
    sourceChainId: process.env.SOURCE_CHAIN_ID || "seraph_evm",
    targetChainId: process.env.TARGET_CHAIN_ID || "xmr_evm",
    batchIntervalMs: process.env.BATCH_INTERVAL_MS ? parseInt(process.env.BATCH_INTERVAL_MS, 10) : 10_000,
    maxBatchSize: process.env.MAX_BATCH_SIZE ? parseInt(process.env.MAX_BATCH_SIZE, 10) : 64,
    minRelayerBond: process.env.MIN_RELAYER_BOND ? BigInt(process.env.MIN_RELAYER_BOND) : 10n ** 18n,
    minFeeThreshold: process.env.MIN_FEE_THRESHOLD ? BigInt(process.env.MIN_FEE_THRESHOLD) : 0n,
    leafHasher: (process.env.LEAF_HASHER as any) || "keccak256",
  };

  return new SeraphRelayerDaemon(config);
}

// Auto-run if executed as standalone CLI process
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const daemon = createRelayerFromEnv();

  console.log("==================================================================");
  console.log("Starting Seraph Protocol Relayer Daemon");
  console.log("Bridge Address:", daemon.config.bridgeAddress);
  console.log("Gas Relayer:", daemon.config.gasRelayerAddress);
  console.log("Relayer Address:", daemon.relayerAddress);
  console.log("Batch Interval:", daemon.config.batchIntervalMs, "ms");
  console.log("Leaf Hasher:", daemon.config.leafHasher);
  console.log("==================================================================");

  daemon.on("started", (info) => {
    console.log("[RelayerDaemon] Service active:", info);
  });

  daemon.on("batchSubmitted", (batch) => {
    console.log(`[RelayerDaemon] Batch #${batch.batchId} submitted! Root: ${batch.merkleRoot} Tx: ${batch.txHash}`);
  });

  daemon.on("voucherDispatched", (rec) => {
    console.log(`[RelayerDaemon] Gas voucher dispatched for target ${rec.target}. Nullifier: ${rec.voucherNullifier}`);
  });

  daemon.on("error", (err) => {
    console.error("[RelayerDaemon] Error:", err.message);
  });

  daemon.start().catch((err) => {
    console.error("[RelayerDaemon] Fatal startup failure:", err);
    process.exit(1);
  });

  const shutdown = () => {
    console.log("\n[RelayerDaemon] Shutting down gracefully...");
    daemon.stop();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

/**
 * Seraph Protocol Relayer Daemon - Type Definitions
 */

export type HasherType = "keccak256" | "sha256Tag";

export interface RelayerConfig {
  /** RPC URL of the EVM chain */
  rpcUrl?: string;
  /** Relayer private key (hex string) */
  privateKey?: string;
  /** Relayer wallet address */
  relayerAddress?: string;
  /** Address of CrossEVMBridge contract */
  bridgeAddress: string;
  /** Address of GasRelayer contract */
  gasRelayerAddress: string;
  /** Source chain identifier (e.g., 'seraph_evm' or bytes32 hex) */
  sourceChainId?: string | Uint8Array;
  /** Target chain identifier (e.g., 'xmr_evm' or bytes32 hex) */
  targetChainId?: string | Uint8Array;
  /** Batching interval in milliseconds (default: 10000ms) */
  batchIntervalMs?: number;
  /** Maximum number of items in a single bridge batch (default: 64) */
  maxBatchSize?: number;
  /** Minimum required relayer bond in wei (default: 1 ether = 10^18) */
  minRelayerBond?: bigint;
  /** Minimum fee tokens required to accept a gas abstraction request */
  minFeeThreshold?: bigint;
  /** List of permitted fee token addresses */
  supportedFeeTokens?: string[];
  /** Leaf hashing strategy: "keccak256" (EVM contract parity) or "sha256Tag" (base-layer) */
  leafHasher?: HasherType;
  /** Automatically start the batching and polling background timers */
  autoStart?: boolean;
}

export interface BridgeOutItem {
  /** Optional unique identifier */
  id?: string;
  /** Nonce emitted on-chain */
  nonce?: bigint | number;
  /** Sender address */
  sender?: string;
  /** Nullifier preventing cross-chain double spend */
  nullifier: string | Uint8Array;
  /** Recipient address on destination chain */
  recipient: string;
  /** Bridged amount in token base units */
  amount: bigint;
  /** Destination chain identifier */
  destChainId: string | Uint8Array;
  /** Timestamp when item was enqueued */
  timestamp?: number;
  /** Precomputed leaf hash if already calculated */
  leafHash?: string | Uint8Array;
}

export interface BridgeBatchRecord {
  /** Unique sequential batch ID */
  batchId: number;
  /** Source chain bytes32 */
  sourceChainId: string;
  /** Computed Merkle root */
  merkleRoot: string;
  /** Hash of state batch data */
  stateDataHash: string;
  /** List of bridge items included in this batch */
  items: BridgeOutItem[];
  /** Hex-encoded leaves of the Merkle tree */
  leaves: string[];
  /** Inclusion proofs for each leaf */
  proofs: string[][];
  /** Batch status */
  status: "pending" | "submitted" | "confirmed" | "challenged";
  /** Timestamp when batch was constructed */
  createdAt: number;
  /** Timestamp when batch was submitted on-chain */
  submittedAt?: number;
  /** On-chain transaction hash */
  txHash?: string;
  /** Relayer address that submitted this batch */
  relayer?: string;
}

export interface BridgeClaimProof {
  /** Batch ID in which the leaf was included */
  batchId: number;
  /** Leaf index in the batch Merkle tree */
  index: number;
  /** Nullifier used for claiming */
  nullifier: string;
  /** Recipient address */
  recipient: string;
  /** Amount to claim */
  amount: bigint;
  /** Destination chain identifier */
  destChainId: string;
  /** Leaf hash (hex) */
  leaf: string;
  /** Array of sibling hashes forming the Merkle inclusion proof */
  merkleProof: string[];
  /** Merkle root of the batch */
  merkleRoot: string;
  /** Pre-encoded claimBridged calldata ready for execution */
  calldata: string;
}

export interface BridgeBatchSubmissionResult {
  batchId: number;
  merkleRoot: string;
  stateDataHash: string;
  sourceChainId: string;
  txHash: string;
  itemCount: number;
}

export interface GasVoucherExecutionRequest {
  /** Unique 32-byte nullifier for the gas voucher */
  voucherNullifier: string | Uint8Array;
  /** Fee token address (e.g. SERAPH or wXMR) */
  feeToken: string;
  /** Fee amount offered for subsidizing the gas execution */
  feeAmount: bigint;
  /** Target contract address to call */
  target: string;
  /** Calldata payload to execute on target */
  callData: string | Uint8Array;
  /** Optional cryptographic signature authorizing the voucher */
  userSignature?: string;
}

export interface GasVoucherValidationResult {
  isValid: boolean;
  errorCode?: string;
  errorMessage?: string;
}

export interface RelayedExecutionRecord {
  /** Nullifier used */
  voucherNullifier: string;
  /** Target contract */
  target: string;
  /** Fee token paid to relayer */
  feeToken: string;
  /** Fee amount collected */
  feeAmount: bigint;
  /** Transaction hash on-chain */
  txHash: string;
  /** Execution status (1 = success, 0 = revert) */
  status: number;
  /** Timestamp of dispatch */
  timestamp: number;
  /** Calldata payload executed */
  callData: string;
  /** Call return data from target */
  returnData?: string;
}

export interface EVMLog {
  address: string;
  topics: string[];
  data: string;
  blockNumber?: bigint | number;
  transactionHash?: string;
  logIndex?: number;
}

export interface DaemonStatus {
  isRunning: boolean;
  relayerAddress: string;
  relayerBond: bigint;
  isBondSufficient: boolean;
  minRelayerBond: bigint;
  pendingBridgeItems: number;
  totalBatchesSubmitted: number;
  totalVouchersExecuted: number;
  totalFeesEarned: Record<string, bigint>;
  lastBatchTimestamp: number | null;
  uptimeSeconds: number;
}

export interface IEVMProvider {
  call(to: string, data: string): Promise<string>;
  getBalance(address: string): Promise<bigint>;
  getBlockNumber(): Promise<bigint>;
  getLogs(filter: {
    address?: string;
    topics?: (string | null)[];
    fromBlock?: bigint | string;
    toBlock?: bigint | string;
  }): Promise<EVMLog[]>;
  sendTransaction(tx: {
    to: string;
    data: string;
    value?: bigint;
    from?: string;
    gasLimit?: bigint;
  }): Promise<{ txHash: string; status: number; returnData?: string }>;
}

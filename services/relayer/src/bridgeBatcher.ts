import {
  computeBridgeLeaf,
  cleanHex,
  toAddressHex,
  toBuffer32,
  padHex64,
  keccak256Hex,
  encodeClaimBridged,
  encodeSubmitStateBatch,
  EVENT_TOPICS,
} from "./crypto.ts";
import { MerkleTree } from "./merkle.ts";
import type {
  BridgeOutItem,
  BridgeBatchRecord,
  BridgeClaimProof,
  EVMLog,
  HasherType,
} from "./types.ts";

export class CrossChainBridgeBatcher {
  private readonly hasher: HasherType;
  private readonly defaultSourceChain: string;
  private pendingQueue: BridgeOutItem[] = [];
  private batches = new Map<number, BridgeBatchRecord>();
  private nullifierToBatch = new Map<string, { batchId: number; leafIndex: number }>();
  private nextBatchId = 0;

  constructor(options: { hasher?: HasherType; defaultSourceChain?: string } = {}) {
    this.hasher = options.hasher || "keccak256";
    this.defaultSourceChain = options.defaultSourceChain || "seraph_evm";
  }

  public get pendingCount(): number {
    return this.pendingQueue.length;
  }

  public getPendingQueue(): BridgeOutItem[] {
    return [...this.pendingQueue];
  }

  public getBatch(batchId: number): BridgeBatchRecord | undefined {
    return this.batches.get(batchId);
  }

  public getAllBatches(): BridgeBatchRecord[] {
    return Array.from(this.batches.values());
  }

  /**
   * Ingest a bridge out item into the queue
   */
  public enqueue(item: BridgeOutItem): void {
    const nullClean = cleanHex(typeof item.nullifier === "string" ? item.nullifier : Buffer.from(item.nullifier).toString("hex")).toLowerCase();
    const recipClean = toAddressHex(item.recipient);
    const destChainClean = typeof item.destChainId === "string" ? item.destChainId : "0x" + Buffer.from(item.destChainId).toString("hex");

    const leafBytes = computeBridgeLeaf(
      item.nullifier,
      recipClean,
      item.amount,
      destChainClean,
      this.hasher
    );
    const leafHash = "0x" + Buffer.from(leafBytes).toString("hex");

    const normalized: BridgeOutItem = {
      ...item,
      nullifier: "0x" + nullClean,
      recipient: recipClean,
      destChainId: destChainClean,
      timestamp: item.timestamp || Date.now(),
      leafHash,
    };

    this.pendingQueue.push(normalized);
  }

  public enqueueMany(items: BridgeOutItem[]): void {
    for (const it of items) {
      this.enqueue(it);
    }
  }

  /**
   * Parses an on-chain TokensLocked / BridgeOut event log and enqueues the item
   */
  public ingestLog(log: EVMLog): BridgeOutItem | null {
    if (!log.topics || log.topics.length === 0) return null;
    const topic0 = log.topics[0]?.toLowerCase();

    // Check if it's TokensLocked event
    if (topic0 !== EVENT_TOPICS.TokensLocked.toLowerCase()) {
      return null;
    }

    try {
      const nonce = BigInt(log.topics[1]);
      const sender = "0x" + log.topics[2].slice(-40);
      const recipient = "0x" + log.topics[3].slice(-40);

      const dataClean = cleanHex(log.data);
      const amount = BigInt("0x" + dataClean.slice(0, 64));
      const destChainHex = "0x" + dataClean.slice(64, 128);

      // Create deterministic nullifier from transaction and log index or nonce
      const nullifierPreimage = `${log.transactionHash || ""}_${log.logIndex || nonce.toString()}_${nonce}`;
      const nullifier = keccak256Hex(Buffer.from(nullifierPreimage, "utf8"));

      const item: BridgeOutItem = {
        nonce,
        sender,
        recipient,
        amount,
        destChainId: destChainHex,
        nullifier,
      };

      this.enqueue(item);
      return item;
    } catch {
      return null;
    }
  }

  public ingestLogs(logs: EVMLog[]): BridgeOutItem[] {
    const ingested: BridgeOutItem[] = [];
    for (const log of logs) {
      const item = this.ingestLog(log);
      if (item) ingested.push(item);
    }
    return ingested;
  }

  /**
   * Builds a depth-appropriate Merkle tree from accumulated pending items
   * and creates a new batch record
   */
  public buildBatch(options: {
    sourceChainId?: string;
    maxBatchSize?: number;
  } = {}): BridgeBatchRecord {
    if (this.pendingQueue.length === 0) {
      throw new Error("Cannot build batch: pending queue is empty");
    }

    const maxItems = options.maxBatchSize || 64;
    const items = this.pendingQueue.splice(0, maxItems);
    const leaves: string[] = [];

    for (const it of items) {
      if (it.leafHash) {
        leaves.push(it.leafHash);
      } else {
        const l = computeBridgeLeaf(it.nullifier, it.recipient, it.amount, it.destChainId, this.hasher);
        leaves.push("0x" + Buffer.from(l).toString("hex"));
      }
    }

    // Build binary Merkle tree
    const tree = new MerkleTree(leaves, this.hasher);
    const merkleRoot = tree.getRootHex();

    // Compute stateDataHash over batch leaf commitments
    const leavesCombined = Buffer.concat(leaves.map((l) => toBuffer32(l)));
    const stateDataHash = keccak256Hex(leavesCombined);

    const batchId = this.nextBatchId++;
    const sourceChain = options.sourceChainId || this.defaultSourceChain;

    const proofs: string[][] = [];
    for (let i = 0; i < leaves.length; i++) {
      const p = tree.getProofHex(i);
      proofs.push(p);

      const nullClean = cleanHex(typeof items[i].nullifier === "string" ? items[i].nullifier : Buffer.from(items[i].nullifier).toString("hex")).toLowerCase();
      this.nullifierToBatch.set(nullClean, { batchId, leafIndex: i });
    }

    const batchRecord: BridgeBatchRecord = {
      batchId,
      sourceChainId: sourceChain,
      merkleRoot,
      stateDataHash,
      items,
      leaves,
      proofs,
      status: "pending",
      createdAt: Date.now(),
    };

    this.batches.set(batchId, batchRecord);
    return batchRecord;
  }

  /**
   * Retrieves Merkle inclusion proof for a claim request
   */
  public getClaimProof(
    batchId: number,
    query: { index?: number; nullifier?: string | Uint8Array; recipient?: string }
  ): BridgeClaimProof {
    const batch = this.batches.get(batchId);
    if (!batch) {
      throw new Error(`Batch ID ${batchId} not found`);
    }

    let leafIndex = -1;
    if (query.index !== undefined) {
      leafIndex = query.index;
    } else if (query.nullifier) {
      const cleanNull = cleanHex(typeof query.nullifier === "string" ? query.nullifier : Buffer.from(query.nullifier).toString("hex")).toLowerCase();
      leafIndex = batch.items.findIndex(
        (it) => cleanHex(typeof it.nullifier === "string" ? it.nullifier : Buffer.from(it.nullifier).toString("hex")).toLowerCase() === cleanNull
      );
    } else if (query.recipient) {
      const cleanRecip = toAddressHex(query.recipient).toLowerCase();
      leafIndex = batch.items.findIndex((it) => it.recipient.toLowerCase() === cleanRecip);
    }

    if (leafIndex < 0 || leafIndex >= batch.items.length) {
      throw new Error(`Item not found in batch ${batchId} for provided claim query`);
    }

    const item = batch.items[leafIndex];
    const leaf = batch.leaves[leafIndex];
    const merkleProof = batch.proofs[leafIndex];
    const nullStr = typeof item.nullifier === "string" ? item.nullifier : "0x" + Buffer.from(item.nullifier).toString("hex");
    const destStr = typeof item.destChainId === "string" ? item.destChainId : "0x" + Buffer.from(item.destChainId).toString("hex");

    const calldata = encodeClaimBridged(batchId, nullStr, item.recipient, item.amount, merkleProof);

    return {
      batchId,
      index: leafIndex,
      nullifier: nullStr,
      recipient: item.recipient,
      amount: item.amount,
      destChainId: destStr,
      leaf,
      merkleProof,
      merkleRoot: batch.merkleRoot,
      calldata,
    };
  }

  /**
   * Verifies the cryptographic validity of a BridgeClaimProof
   */
  public verifyClaimProof(claim: BridgeClaimProof): boolean {
    // 1. Verify that computed leaf from parameters matches claimed leaf
    const computedLeafBytes = computeBridgeLeaf(
      claim.nullifier,
      claim.recipient,
      claim.amount,
      claim.destChainId,
      this.hasher
    );
    const computedLeafHex = "0x" + Buffer.from(computedLeafBytes).toString("hex");
    if (computedLeafHex.toLowerCase() !== claim.leaf.toLowerCase()) {
      return false;
    }

    // 2. Verify Merkle proof against root
    return MerkleTree.verify(claim.leaf, claim.merkleProof, claim.merkleRoot, this.hasher);
  }

  /**
   * Encodes calldata for submitting state batch to CrossEVMBridge contract
   */
  public encodeBatchSubmission(
    batchId: number,
    paramMapping: "sourceChainAndRoot" | "rootAndDataHash" = "sourceChainAndRoot"
  ): { data: string; batch: BridgeBatchRecord } {
    const batch = this.batches.get(batchId);
    if (!batch) {
      throw new Error(`Batch ID ${batchId} not found`);
    }

    const p1 = paramMapping === "rootAndDataHash" ? batch.merkleRoot : batch.sourceChainId;
    const p2 = paramMapping === "rootAndDataHash" ? batch.stateDataHash : batch.merkleRoot;

    const data = encodeSubmitStateBatch(p1, p2);
    return { data, batch };
  }

  /**
   * Marks a batch as submitted with transaction hash
   */
  public markBatchSubmitted(batchId: number, txHash: string, relayer?: string): void {
    const batch = this.batches.get(batchId);
    if (!batch) return;
    batch.status = "submitted";
    batch.txHash = txHash;
    batch.submittedAt = Date.now();
    if (relayer) batch.relayer = relayer;
  }
}

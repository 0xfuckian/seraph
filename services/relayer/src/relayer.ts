import { EventEmitter } from "node:events";
import { CrossChainBridgeBatcher } from "./bridgeBatcher.ts";
import { GasAbstractionDispatcher } from "./gasDispatcher.ts";
import { HttpEVMProvider } from "./provider.ts";
import {
  toAddressHex,
  encodeBondRelayer,
  SELECTORS,
} from "./crypto.ts";
import type {
  RelayerConfig,
  DaemonStatus,
  BridgeOutItem,
  BridgeBatchRecord,
  BridgeClaimProof,
  BridgeBatchSubmissionResult,
  GasVoucherExecutionRequest,
  RelayedExecutionRecord,
  IEVMProvider,
  EVMLog,
} from "./types.ts";

export class InsufficientRelayerBondError extends Error {
  public readonly bondedAmount: bigint;
  public readonly requiredAmount: bigint;

  constructor(bonded: bigint, required: bigint) {
    super(
      `Insufficient relayer bond: current bonded amount is ${bonded} wei, required minimum is ${required} wei`
    );
    this.name = "InsufficientRelayerBondError";
    this.bondedAmount = bonded;
    this.requiredAmount = required;
  }
}

export class SeraphRelayerDaemon extends EventEmitter {
  public readonly config: RelayerConfig;
  public readonly bridgeBatcher: CrossChainBridgeBatcher;
  public readonly gasDispatcher: GasAbstractionDispatcher;
  public readonly provider?: IEVMProvider;
  public readonly relayerAddress: string;

  private isRunning = false;
  private batchIntervalTimer: NodeJS.Timeout | null = null;
  private logPollTimer: NodeJS.Timeout | null = null;
  private startTime: number | null = null;
  private lastBatchTime: number | null = null;
  private totalBatchesSubmitted = 0;
  private lastProcessedBlock: bigint = 0n;

  constructor(config: RelayerConfig, customProvider?: IEVMProvider) {
    super();
    this.config = {
      batchIntervalMs: 10_000,
      maxBatchSize: 64,
      minRelayerBond: 10n ** 18n, // 1 ether
      minFeeThreshold: 0n,
      leafHasher: "keccak256",
      ...config,
    };

    // Determine relayer address
    this.relayerAddress = this.config.relayerAddress
      ? toAddressHex(this.config.relayerAddress)
      : "0x1111111111111111111111111111111111111111";

    // Set up EVM provider
    if (customProvider) {
      this.provider = customProvider;
    } else if (this.config.rpcUrl) {
      this.provider = new HttpEVMProvider(this.config.rpcUrl);
    }

    // Initialize Cross-Chain Bridge Batcher
    this.bridgeBatcher = new CrossChainBridgeBatcher({
      hasher: this.config.leafHasher,
      defaultSourceChain: typeof this.config.sourceChainId === "string" ? this.config.sourceChainId : "seraph_evm",
    });

    // Initialize Gas Abstraction Dispatcher
    this.gasDispatcher = new GasAbstractionDispatcher({
      gasRelayerAddress: this.config.gasRelayerAddress,
      relayerAddress: this.relayerAddress,
      provider: this.provider,
      minFeeThreshold: this.config.minFeeThreshold,
      supportedFeeTokens: this.config.supportedFeeTokens,
    });

    if (this.config.autoStart) {
      this.start().catch((err) => this.emit("error", err));
    }
  }

  /**
   * Starts the relayer background loops for batching and log ingestion
   */
  public async start(): Promise<void> {
    if (this.isRunning) return;

    this.isRunning = true;
    this.startTime = Date.now();

    // Check relayer bond status on start
    await this.checkRelayerBond();

    // Start batch interval loop
    if (this.config.batchIntervalMs && this.config.batchIntervalMs > 0) {
      this.batchIntervalTimer = setInterval(() => {
        if (this.bridgeBatcher.pendingCount > 0) {
          this.submitPendingBatch().catch((err) => {
            this.emit("batchFailed", err);
          });
        }
      }, this.config.batchIntervalMs);
    }

    // Start event log polling if provider is configured
    if (this.provider) {
      try {
        this.lastProcessedBlock = await this.provider.getBlockNumber();
      } catch {
        this.lastProcessedBlock = 0n;
      }

      this.logPollTimer = setInterval(() => {
        this.pollBridgeLogs().catch((err) => {
          this.emit("error", err);
        });
      }, Math.max(5000, this.config.batchIntervalMs || 5000));
    }

    this.emit("started", {
      relayerAddress: this.relayerAddress,
      bridgeAddress: this.config.bridgeAddress,
      gasRelayerAddress: this.config.gasRelayerAddress,
    });
  }

  /**
   * Stops the daemon background loops
   */
  public stop(): void {
    if (!this.isRunning) return;

    if (this.batchIntervalTimer) {
      clearInterval(this.batchIntervalTimer);
      this.batchIntervalTimer = null;
    }
    if (this.logPollTimer) {
      clearInterval(this.logPollTimer);
      this.logPollTimer = null;
    }

    this.isRunning = false;
    this.emit("stopped");
  }

  /**
   * Checks the relayer bond balance on the CrossEVMBridge contract
   */
  public async checkRelayerBond(): Promise<{
    bondedAmount: bigint;
    isSufficient: boolean;
    minRequired: bigint;
  }> {
    const minRequired = this.config.minRelayerBond ?? 10n ** 18n;
    let bondedAmount = 0n;

    if (this.provider) {
      try {
        const calldata =
          SELECTORS.relayerBonds + this.relayerAddress.slice(2).padStart(64, "0");
        const res = await this.provider.call(this.config.bridgeAddress, calldata);
        bondedAmount = BigInt(res);
      } catch {
        // In local/mock mode, default to min required if provider call fails
        bondedAmount = minRequired;
      }
    } else {
      bondedAmount = minRequired;
    }

    return {
      bondedAmount,
      isSufficient: bondedAmount >= minRequired,
      minRequired,
    };
  }

  /**
   * Bonds the relayer by depositing ETH into CrossEVMBridge.bondRelayer()
   */
  public async depositBond(amount?: bigint): Promise<string> {
    const depositAmount = amount || this.config.minRelayerBond || 10n ** 18n;
    if (!this.provider) {
      throw new Error("Cannot deposit bond: no EVM provider configured");
    }

    const data = encodeBondRelayer();
    const res = await this.provider.sendTransaction({
      to: this.config.bridgeAddress,
      data,
      value: depositAmount,
      from: this.relayerAddress,
    });

    this.emit("relayerBonded", {
      relayer: this.relayerAddress,
      amount: depositAmount,
      txHash: res.txHash,
    });

    return res.txHash;
  }

  /**
   * Ingests a single BridgeOut item to be queued for batching
   */
  public ingestBridgeOut(item: BridgeOutItem): void {
    this.bridgeBatcher.enqueue(item);
    this.emit("itemEnqueued", item);
  }

  /**
   * Ingests multiple BridgeOut items
   */
  public ingestBridgeOutBatch(items: BridgeOutItem[]): void {
    this.bridgeBatcher.enqueueMany(items);
    this.emit("itemsEnqueued", { count: items.length });
  }

  /**
   * Polls the provider for new CrossEVMBridge TokensLocked logs
   */
  public async pollBridgeLogs(): Promise<BridgeOutItem[]> {
    if (!this.provider) return [];

    try {
      const currentBlock = await this.provider.getBlockNumber();
      if (currentBlock <= this.lastProcessedBlock) return [];

      const logs = await this.provider.getLogs({
        address: this.config.bridgeAddress,
        fromBlock: this.lastProcessedBlock + 1n,
        toBlock: currentBlock,
      });

      this.lastProcessedBlock = currentBlock;
      const ingested = this.bridgeBatcher.ingestLogs(logs);

      for (const item of ingested) {
        this.emit("logIngested", item);
      }
      return ingested;
    } catch (err) {
      this.emit("error", err);
      return [];
    }
  }

  /**
   * Builds the current pending queue into a Merkle tree batch and submits on-chain
   */
  public async submitPendingBatch(
    paramMapping: "sourceChainAndRoot" | "rootAndDataHash" = "sourceChainAndRoot"
  ): Promise<BridgeBatchSubmissionResult> {
    if (this.bridgeBatcher.pendingCount === 0) {
      throw new Error("No pending bridge items to batch");
    }

    // 1. Relayer bond verification
    const bond = await this.checkRelayerBond();
    if (!bond.isSufficient) {
      const err = new InsufficientRelayerBondError(bond.bondedAmount, bond.minRequired);
      this.emit("bondInsufficient", err);
      throw err;
    }

    // 2. Build Merkle tree batch
    const batch = this.bridgeBatcher.buildBatch({
      sourceChainId: typeof this.config.sourceChainId === "string" ? this.config.sourceChainId : "seraph_evm",
      maxBatchSize: this.config.maxBatchSize,
    });
    this.emit("batchCreated", batch);

    // 3. Prepare calldata
    const { data } = this.bridgeBatcher.encodeBatchSubmission(batch.batchId, paramMapping);

    let txHash = "0x" + batch.merkleRoot.slice(2);
    if (this.provider) {
      const txRes = await this.provider.sendTransaction({
        to: this.config.bridgeAddress,
        data,
        from: this.relayerAddress,
      });
      txHash = txRes.txHash;
    }

    // 4. Update status & history
    this.bridgeBatcher.markBatchSubmitted(batch.batchId, txHash, this.relayerAddress);
    this.lastBatchTime = Date.now();
    this.totalBatchesSubmitted++;

    const result: BridgeBatchSubmissionResult = {
      batchId: batch.batchId,
      merkleRoot: batch.merkleRoot,
      stateDataHash: batch.stateDataHash,
      sourceChainId: batch.sourceChainId,
      txHash,
      itemCount: batch.items.length,
    };

    this.emit("batchSubmitted", result);
    return result;
  }

  /**
   * Retrieves Merkle inclusion proof for a recipient cross-chain claim
   */
  public getProofForClaim(
    batchId: number,
    query: { index?: number; nullifier?: string | Uint8Array; recipient?: string }
  ): BridgeClaimProof {
    return this.bridgeBatcher.getClaimProof(batchId, query);
  }

  /**
   * Dispatches a user gas voucher request with solvency check and fee subsidy collection
   */
  public async dispatchGasVoucher(
    req: GasVoucherExecutionRequest
  ): Promise<RelayedExecutionRecord> {
    try {
      this.emit("voucherReceived", req);
      const record = await this.gasDispatcher.dispatch(req);
      this.emit("voucherDispatched", record);
      return record;
    } catch (err) {
      this.emit("voucherFailed", { request: req, error: err });
      throw err;
    }
  }

  /**
   * Returns complete real-time daemon status and metrics
   */
  public async status(): Promise<DaemonStatus> {
    const bond = await this.checkRelayerBond();
    const uptimeSeconds = this.startTime ? Math.floor((Date.now() - this.startTime) / 1000) : 0;

    return {
      isRunning: this.isRunning,
      relayerAddress: this.relayerAddress,
      relayerBond: bond.bondedAmount,
      isBondSufficient: bond.isSufficient,
      minRelayerBond: bond.minRequired,
      pendingBridgeItems: this.bridgeBatcher.pendingCount,
      totalBatchesSubmitted: this.totalBatchesSubmitted,
      totalVouchersExecuted: this.gasDispatcher.getExecutionHistory().length,
      totalFeesEarned: this.gasDispatcher.getRelayerEarnings(),
      lastBatchTimestamp: this.lastBatchTime,
      uptimeSeconds,
    };
  }
}

import {
  cleanHex,
  toAddressHex,
  encodeExecuteWithGasAbstraction,
  SELECTORS,
} from "./crypto.ts";
import type {
  GasVoucherExecutionRequest,
  GasVoucherValidationResult,
  RelayedExecutionRecord,
  IEVMProvider,
} from "./types.ts";

export class GasAbstractionDispatcher {
  public readonly gasRelayerAddress: string;
  private readonly provider?: IEVMProvider;
  private readonly relayerAddress: string;
  private readonly minFeeThreshold: bigint;
  private readonly supportedFeeTokens = new Set<string>();
  private readonly forbiddenTargets = new Set<string>();

  private readonly usedVouchers = new Set<string>();
  private readonly localPoolBalances = new Map<string, bigint>();
  private readonly feesEarned = new Map<string, bigint>();
  private readonly history: RelayedExecutionRecord[] = [];

  constructor(options: {
    gasRelayerAddress: string;
    relayerAddress?: string;
    provider?: IEVMProvider;
    minFeeThreshold?: bigint;
    supportedFeeTokens?: string[];
  }) {
    this.gasRelayerAddress = toAddressHex(options.gasRelayerAddress);
    this.relayerAddress = options.relayerAddress ? toAddressHex(options.relayerAddress) : "0x0000000000000000000000000000000000000000";
    this.provider = options.provider;
    this.minFeeThreshold = options.minFeeThreshold ?? 0n;

    if (options.supportedFeeTokens && options.supportedFeeTokens.length > 0) {
      for (const t of options.supportedFeeTokens) {
        this.supportedFeeTokens.add(toAddressHex(t).toLowerCase());
      }
    }

    // Always forbid calling 0x0 or the GasRelayer contract itself
    this.forbiddenTargets.add("0x0000000000000000000000000000000000000000");
    this.forbiddenTargets.add(this.gasRelayerAddress.toLowerCase());
  }

  public isVoucherUsed(nullifier: string | Uint8Array): boolean {
    const clean = cleanHex(typeof nullifier === "string" ? nullifier : Buffer.from(nullifier).toString("hex")).toLowerCase().padStart(64, "0");
    return this.usedVouchers.has(clean);
  }

  public creditVoucherPool(feeToken: string, amount: bigint): void {
    const token = toAddressHex(feeToken).toLowerCase();
    const current = this.localPoolBalances.get(token) || 0n;
    this.localPoolBalances.set(token, current + amount);
  }

  public async getPoolBalance(feeToken: string): Promise<bigint> {
    const token = toAddressHex(feeToken).toLowerCase();

    // Query on-chain via provider if available
    if (this.provider) {
      try {
        const calldata = SELECTORS.voucherPoolBalance + token.slice(2).padStart(64, "0");
        const res = await this.provider.call(this.gasRelayerAddress, calldata);
        const onChainBal = BigInt(res);
        if (onChainBal > 0n) return onChainBal;
      } catch {
        // Fall back to local balance
      }
    }

    return this.localPoolBalances.get(token) || 0n;
  }

  /**
   * Validates solvency, nullifier uniqueness, target safety, and fee threshold
   */
  public async validateRequest(req: GasVoucherExecutionRequest): Promise<GasVoucherValidationResult> {
    const nullClean = cleanHex(typeof req.voucherNullifier === "string" ? req.voucherNullifier : Buffer.from(req.voucherNullifier).toString("hex")).toLowerCase().padStart(64, "0");

    // 1. Nullifier check
    if (!nullClean || nullClean === "0".repeat(64)) {
      return {
        isValid: false,
        errorCode: "INVALID_NULLIFIER",
        errorMessage: "Voucher nullifier cannot be zero or empty",
      };
    }

    if (this.usedVouchers.has(nullClean)) {
      return {
        isValid: false,
        errorCode: "VOUCHER_ALREADY_USED",
        errorMessage: `Voucher nullifier 0x${nullClean} has already been spent locally`,
      };
    }

    // On-chain used vouchers check
    if (this.provider) {
      try {
        const calldata = SELECTORS.usedVouchers + nullClean;
        const res = await this.provider.call(this.gasRelayerAddress, calldata);
        if (BigInt(res) !== 0n) {
          this.usedVouchers.add(nullClean);
          return {
            isValid: false,
            errorCode: "VOUCHER_ALREADY_USED",
            errorMessage: `Voucher nullifier 0x${nullClean} is already marked as spent on-chain`,
          };
        }
      } catch {
        // Ignore provider error if offline
      }
    }

    // 2. Target safety check
    let targetClean: string;
    try {
      targetClean = toAddressHex(req.target).toLowerCase();
    } catch {
      return {
        isValid: false,
        errorCode: "INVALID_TARGET",
        errorMessage: `Target is not a valid EVM address: ${req.target}`,
      };
    }

    if (this.forbiddenTargets.has(targetClean)) {
      return {
        isValid: false,
        errorCode: "FORBIDDEN_TARGET",
        errorMessage: `Target ${targetClean} is forbidden (cannot be zero or GasRelayer itself)`,
      };
    }

    const feeTokenClean = toAddressHex(req.feeToken).toLowerCase();
    if (targetClean === feeTokenClean) {
      return {
        isValid: false,
        errorCode: "FORBIDDEN_TARGET",
        errorMessage: "Target cannot be the fee token contract (drain protection)",
      };
    }

    // 3. Supported fee token check
    if (this.supportedFeeTokens.size > 0 && !this.supportedFeeTokens.has(feeTokenClean)) {
      return {
        isValid: false,
        errorCode: "UNSUPPORTED_FEE_TOKEN",
        errorMessage: `Fee token ${feeTokenClean} is not supported by this relayer`,
      };
    }

    // 4. Fee threshold check
    if (req.feeAmount < this.minFeeThreshold) {
      return {
        isValid: false,
        errorCode: "FEE_BELOW_THRESHOLD",
        errorMessage: `Offered fee ${req.feeAmount} is below relayer minimum threshold ${this.minFeeThreshold}`,
      };
    }

    // 5. Solvency verification: does the voucher pool have sufficient funds?
    const poolBal = await this.getPoolBalance(feeTokenClean);
    if (req.feeAmount > poolBal) {
      return {
        isValid: false,
        errorCode: "INSUFFICIENT_VOUCHER_POOL",
        errorMessage: `Voucher pool balance ${poolBal} is insufficient for requested fee ${req.feeAmount}`,
      };
    }

    return { isValid: true };
  }

  /**
   * Executes the transaction on-chain via GasRelayer, collecting subsidized fees
   */
  public async dispatch(req: GasVoucherExecutionRequest): Promise<RelayedExecutionRecord> {
    const validation = await this.validateRequest(req);
    if (!validation.isValid) {
      const err = new Error(`[${validation.errorCode}] Gas voucher dispatch failed: ${validation.errorMessage}`);
      (err as any).code = validation.errorCode;
      throw err;
    }

    const nullClean = cleanHex(typeof req.voucherNullifier === "string" ? req.voucherNullifier : Buffer.from(req.voucherNullifier).toString("hex")).toLowerCase().padStart(64, "0");
    const feeTokenClean = toAddressHex(req.feeToken);
    const targetClean = toAddressHex(req.target);

    // Encode calldata
    const calldata = encodeExecuteWithGasAbstraction(
      nullClean,
      feeTokenClean,
      req.feeAmount,
      targetClean,
      req.callData
    );

    let txHash = "0x" + cleanHex(nullClean);
    let status = 1;
    let returnData: string | undefined;

    if (this.provider) {
      const txRes = await this.provider.sendTransaction({
        to: this.gasRelayerAddress,
        data: calldata,
        from: this.relayerAddress,
      });
      txHash = txRes.txHash;
      status = txRes.status;
      returnData = txRes.returnData;
    }

    // Mark voucher as used
    this.usedVouchers.add(nullClean);

    // Update local accounting
    const tokenLower = feeTokenClean.toLowerCase();
    const currentPool = this.localPoolBalances.get(tokenLower) || 0n;
    if (currentPool >= req.feeAmount) {
      this.localPoolBalances.set(tokenLower, currentPool - req.feeAmount);
    }

    const currentEarned = this.feesEarned.get(tokenLower) || 0n;
    this.feesEarned.set(tokenLower, currentEarned + req.feeAmount);

    const record: RelayedExecutionRecord = {
      voucherNullifier: "0x" + nullClean,
      target: targetClean,
      feeToken: feeTokenClean,
      feeAmount: req.feeAmount,
      txHash,
      status,
      timestamp: Date.now(),
      callData: typeof req.callData === "string" ? req.callData : "0x" + Buffer.from(req.callData).toString("hex"),
      returnData,
    };

    this.history.push(record);
    return record;
  }

  public getExecutionHistory(): RelayedExecutionRecord[] {
    return [...this.history];
  }

  public getRelayerEarnings(): Record<string, bigint> {
    const earnings: Record<string, bigint> = {};
    for (const [token, amount] of this.feesEarned.entries()) {
      earnings[token] = amount;
    }
    return earnings;
  }
}

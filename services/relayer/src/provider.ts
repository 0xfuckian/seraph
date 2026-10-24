import type { IEVMProvider, EVMLog } from "./types.ts";
import { cleanHex, toAddressHex, SELECTORS } from "./crypto.ts";

/**
 * Standard HTTP JSON-RPC EVM Provider
 */
export class HttpEVMProvider implements IEVMProvider {
  private readonly rpcUrl: string;
  private requestId = 0;

  constructor(rpcUrl: string) {
    this.rpcUrl = rpcUrl;
  }

  private async request<T = any>(method: string, params: any[] = []): Promise<T> {
    const id = ++this.requestId;
    const body = JSON.stringify({
      jsonrpc: "2.0",
      id,
      method,
      params,
    });

    const res = await fetch(this.rpcUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });

    if (!res.ok) {
      throw new Error(`HTTP error ${res.status}: ${res.statusText}`);
    }

    const json = (await res.json()) as any;
    if (json.error) {
      throw new Error(`RPC Error (${json.error.code}): ${json.error.message}`);
    }

    return json.result as T;
  }

  public async call(to: string, data: string): Promise<string> {
    const res = await this.request<string>("eth_call", [
      { to: toAddressHex(to), data: "0x" + cleanHex(data) },
      "latest",
    ]);
    return res || "0x";
  }

  public async getBalance(address: string): Promise<bigint> {
    const hex = await this.request<string>("eth_getBalance", [toAddressHex(address), "latest"]);
    return BigInt(hex);
  }

  public async getBlockNumber(): Promise<bigint> {
    const hex = await this.request<string>("eth_blockNumber", []);
    return BigInt(hex);
  }

  public async getLogs(filter: {
    address?: string;
    topics?: (string | null)[];
    fromBlock?: bigint | string;
    toBlock?: bigint | string;
  }): Promise<EVMLog[]> {
    const rpcFilter: any = {};
    if (filter.address) rpcFilter.address = toAddressHex(filter.address);
    if (filter.topics) rpcFilter.topics = filter.topics;
    if (filter.fromBlock !== undefined) {
      rpcFilter.fromBlock = typeof filter.fromBlock === "bigint" ? "0x" + filter.fromBlock.toString(16) : filter.fromBlock;
    }
    if (filter.toBlock !== undefined) {
      rpcFilter.toBlock = typeof filter.toBlock === "bigint" ? "0x" + filter.toBlock.toString(16) : filter.toBlock;
    }

    const logs = await this.request<any[]>("eth_getLogs", [rpcFilter]);
    return logs.map((l) => ({
      address: l.address,
      topics: l.topics,
      data: l.data,
      blockNumber: l.blockNumber ? BigInt(l.blockNumber) : undefined,
      transactionHash: l.transactionHash,
      logIndex: l.logIndex ? parseInt(l.logIndex, 16) : undefined,
    }));
  }

  public async sendTransaction(tx: {
    to: string;
    data: string;
    value?: bigint;
    from?: string;
    gasLimit?: bigint;
  }): Promise<{ txHash: string; status: number; returnData?: string }> {
    const txObj: any = {
      to: toAddressHex(tx.to),
      data: "0x" + cleanHex(tx.data),
    };
    if (tx.from) txObj.from = toAddressHex(tx.from);
    if (tx.value !== undefined) txObj.value = "0x" + tx.value.toString(16);
    if (tx.gasLimit !== undefined) txObj.gas = "0x" + tx.gasLimit.toString(16);

    const txHash = await this.request<string>("eth_sendTransaction", [txObj]);
    return { txHash, status: 1 };
  }
}

/**
 * In-memory Mock EVM Provider for deterministic testing and local verification
 */
export class MockEVMProvider implements IEVMProvider {
  public relayerBonds = new Map<string, bigint>();
  public voucherPoolBalances = new Map<string, bigint>();
  public usedVouchers = new Set<string>();
  public tokenGasRates = new Map<string, bigint>();
  public balances = new Map<string, bigint>();
  public mockLogs: EVMLog[] = [];
  public sentTransactions: Array<{
    to: string;
    data: string;
    value?: bigint;
    from?: string;
    txHash: string;
    timestamp: number;
  }> = [];

  public customHandlers = new Map<string, (to: string, data: string) => string>();
  public blockNumber = 1000n;
  public txCounter = 0;

  constructor() {
    // Default setup
  }

  public setRelayerBond(relayer: string, amount: bigint): void {
    this.relayerBonds.set(toAddressHex(relayer).toLowerCase(), amount);
  }

  public getRelayerBond(relayer: string): bigint {
    return this.relayerBonds.get(toAddressHex(relayer).toLowerCase()) || 0n;
  }

  public setVoucherPoolBalance(token: string, amount: bigint): void {
    this.voucherPoolBalances.set(toAddressHex(token).toLowerCase(), amount);
  }

  public getVoucherPoolBalance(token: string): bigint {
    return this.voucherPoolBalances.get(toAddressHex(token).toLowerCase()) || 0n;
  }

  public setVoucherUsed(nullifier: string, used = true): void {
    const clean = cleanHex(nullifier).toLowerCase().padStart(64, "0");
    if (used) {
      this.usedVouchers.add(clean);
    } else {
      this.usedVouchers.delete(clean);
    }
  }

  public isVoucherUsed(nullifier: string): boolean {
    const clean = cleanHex(nullifier).toLowerCase().padStart(64, "0");
    return this.usedVouchers.has(clean);
  }

  public setTokenGasRate(token: string, rate: bigint): void {
    this.tokenGasRates.set(toAddressHex(token).toLowerCase(), rate);
  }

  public setBalance(address: string, balance: bigint): void {
    this.balances.set(toAddressHex(address).toLowerCase(), balance);
  }

  public addLog(log: EVMLog): void {
    this.mockLogs.push(log);
  }

  public async call(to: string, data: string): Promise<string> {
    const clean = cleanHex(data);
    const selector = "0x" + clean.slice(0, 8);
    const body = clean.slice(8);

    if (this.customHandlers.has(selector)) {
      return this.customHandlers.get(selector)!(to, data);
    }

    // relayerBonds(address)
    if (selector === SELECTORS.relayerBonds) {
      const address = "0x" + body.slice(24, 64).toLowerCase();
      const bond = this.getRelayerBond(address);
      return "0x" + bond.toString(16).padStart(64, "0");
    }

    // voucherPoolBalance(address)
    if (selector === SELECTORS.voucherPoolBalance) {
      const token = "0x" + body.slice(24, 64).toLowerCase();
      const bal = this.getVoucherPoolBalance(token);
      return "0x" + bal.toString(16).padStart(64, "0");
    }

    // usedVouchers(bytes32)
    if (selector === SELECTORS.usedVouchers) {
      const nullifier = body.slice(0, 64).toLowerCase();
      const isUsed = this.usedVouchers.has(nullifier);
      return "0x" + (isUsed ? "1" : "0").padStart(64, "0");
    }

    // tokenGasRate(address)
    if (selector === SELECTORS.tokenGasRate) {
      const token = "0x" + body.slice(24, 64).toLowerCase();
      const rate = this.tokenGasRates.get(token) || 1000000000000000000n; // Default 1:1
      return "0x" + rate.toString(16).padStart(64, "0");
    }

    return "0x" + "0".repeat(64);
  }

  public async getBalance(address: string): Promise<bigint> {
    return this.balances.get(toAddressHex(address).toLowerCase()) || 10000000000000000000n; // 10 ETH default
  }

  public async getBlockNumber(): Promise<bigint> {
    return this.blockNumber;
  }

  public async getLogs(filter: {
    address?: string;
    topics?: (string | null)[];
    fromBlock?: bigint | string;
    toBlock?: bigint | string;
  }): Promise<EVMLog[]> {
    return this.mockLogs.filter((log) => {
      if (filter.address && log.address.toLowerCase() !== filter.address.toLowerCase()) {
        return false;
      }
      if (filter.topics && filter.topics.length > 0) {
        for (let i = 0; i < filter.topics.length; i++) {
          const reqTopic = filter.topics[i];
          if (reqTopic !== null && log.topics[i] !== reqTopic) {
            return false;
          }
        }
      }
      return true;
    });
  }

  public async sendTransaction(tx: {
    to: string;
    data: string;
    value?: bigint;
    from?: string;
    gasLimit?: bigint;
  }): Promise<{ txHash: string; status: number; returnData?: string }> {
    const txHash = "0x" + (++this.txCounter).toString(16).padStart(64, "0");
    this.sentTransactions.push({
      ...tx,
      txHash,
      timestamp: Date.now(),
    });

    const clean = cleanHex(tx.data);
    const selector = "0x" + clean.slice(0, 8);

    // If bondRelayer, credit bond
    if (selector === SELECTORS.bondRelayer && tx.from && tx.value) {
      const current = this.getRelayerBond(tx.from);
      this.setRelayerBond(tx.from, current + tx.value);
    }

    // If executeWithGasAbstraction, mark voucher as used and deduct pool balance
    if (selector === SELECTORS.executeWithGasAbstraction) {
      const nullifier = clean.slice(8, 72).toLowerCase();
      const token = "0x" + clean.slice(72 + 24, 72 + 64).toLowerCase();
      const feeAmount = BigInt("0x" + clean.slice(136, 200));

      this.setVoucherUsed(nullifier, true);
      const currentPool = this.getVoucherPoolBalance(token);
      if (currentPool >= feeAmount) {
        this.setVoucherPoolBalance(token, currentPool - feeAmount);
      }
    }

    return { txHash, status: 1 };
  }
}

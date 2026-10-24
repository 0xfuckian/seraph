import { createHash } from "node:crypto";
import type { HasherType } from "./types.ts";

/**
 * Computes standard Ethereum Keccak-256 hash
 */
export function keccak256(data: Uint8Array | string): Uint8Array {
  const buf = typeof data === "string" ? Buffer.from(cleanHex(data), "hex") : Buffer.from(data);
  return new Uint8Array(createHash("keccak-256").update(buf).digest());
}

export function keccak256Hex(data: Uint8Array | string): string {
  return "0x" + Buffer.from(keccak256(data)).toString("hex");
}

/**
 * Domain-tagged SHA-256 hash matching Seraph base-layer protocol
 */
export function sha256Tag(tag: string, ...chunks: Uint8Array[]): Uint8Array {
  const h = createHash("sha256");
  h.update(Buffer.from(tag, "utf8"));
  for (const c of chunks) {
    h.update(Buffer.from(c));
  }
  return new Uint8Array(h.digest());
}

export function cleanHex(hex: string): string {
  return hex.startsWith("0x") || hex.startsWith("0X") ? hex.slice(2) : hex;
}

export function padHex64(val: string | bigint | number): string {
  let hex: string;
  if (typeof val === "bigint" || typeof val === "number") {
    hex = val.toString(16);
  } else {
    hex = cleanHex(val);
  }
  return hex.padStart(64, "0");
}

export function toBuffer32(val: string | Uint8Array | bigint | number): Buffer {
  if (typeof val === "bigint" || typeof val === "number") {
    const hex = val.toString(16).padStart(64, "0");
    return Buffer.from(hex, "hex");
  }
  if (typeof val === "string") {
    const clean = cleanHex(val);
    if (clean.length === 64) {
      return Buffer.from(clean, "hex");
    }
    // If it's an ASCII chain identifier or string, convert or right-pad to 32 bytes
    const buf = Buffer.alloc(32);
    buf.write(val, "utf8");
    return buf;
  }
  if (val.length === 32) {
    return Buffer.from(val);
  }
  const buf = Buffer.alloc(32);
  Buffer.from(val).copy(buf);
  return buf;
}

export function toAddressBuffer(val: string): Buffer {
  const clean = cleanHex(val).toLowerCase();
  if (clean.length !== 40) {
    throw new Error(`Invalid EVM address length: ${val}`);
  }
  return Buffer.from(clean, "hex");
}

export function toAddressHex(val: string | Uint8Array | Buffer): string {
  if (typeof val === "string") {
    const clean = cleanHex(val).toLowerCase();
    return "0x" + clean.padStart(40, "0").slice(-40);
  }
  const hex = Buffer.from(val).toString("hex").toLowerCase();
  return "0x" + hex.padStart(40, "0").slice(-40);
}

/**
 * Computes CrossEVMBridge leaf hash matching Solidity contract:
 * keccak256(abi.encodePacked(nullifier, recipient, amount, localChainId))
 * Total packed size = 32 + 20 + 32 + 32 = 116 bytes
 */
export function computeBridgeLeafKeccak(
  nullifier: string | Uint8Array,
  recipient: string,
  amount: bigint,
  chainId: string | Uint8Array
): Uint8Array {
  const nullBuf = toBuffer32(nullifier);
  const recipBuf = toAddressBuffer(recipient); // 20 bytes
  const amtBuf = toBuffer32(amount); // 32 bytes
  const chainBuf = toBuffer32(chainId); // 32 bytes

  const packed = Buffer.concat([nullBuf, recipBuf, amtBuf, chainBuf]);
  return keccak256(packed);
}

/**
 * Computes CrossEVMBridge leaf hash matching SDK / base-layer tagged hash:
 * sha256Tag("seraph_bridge_leaf_v1", nullifier, recipBuf (32 bytes), amtBuf (32 bytes), destChainId (32 bytes))
 */
export function computeBridgeLeafSha256(
  nullifier: string | Uint8Array,
  recipient: string,
  amount: bigint,
  chainId: string | Uint8Array
): Uint8Array {
  const nullBuf = toBuffer32(nullifier);
  const recipBuf = Buffer.alloc(32);
  recipBuf.set(toAddressBuffer(recipient), 12);
  const amtBuf = toBuffer32(amount);
  const chainBuf = toBuffer32(chainId);

  return sha256Tag("seraph_bridge_leaf_v1", nullBuf, recipBuf, amtBuf, chainBuf);
}

/**
 * Unified leaf computation helper supporting both keccak256 (default) and sha256Tag
 */
export function computeBridgeLeaf(
  nullifier: string | Uint8Array,
  recipient: string,
  amount: bigint,
  chainId: string | Uint8Array,
  hasher: HasherType = "keccak256"
): Uint8Array {
  return hasher === "sha256Tag"
    ? computeBridgeLeafSha256(nullifier, recipient, amount, chainId)
    : computeBridgeLeafKeccak(nullifier, recipient, amount, chainId);
}

/**
 * Hashes a pair of nodes in sorted order matching OpenZeppelin / Seraph verification
 */
export function hashSortedPair(
  a: Uint8Array,
  b: Uint8Array,
  hasher: HasherType = "keccak256"
): Uint8Array {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  const cmp = Buffer.compare(bufA, bufB);

  const [first, second] = cmp <= 0 ? [bufA, bufB] : [bufB, bufA];
  const combined = Buffer.concat([first, second]);

  if (hasher === "sha256Tag") {
    return sha256Tag("seraph_bridge_node_v1", combined);
  }
  return keccak256(combined);
}

// =========================================================================
// Method Selectors & ABI Calldata Encoders
// =========================================================================

export const SELECTORS = {
  submitStateBatch: "0x69f589b0", // submitStateBatch(bytes32,bytes32)
  executeWithGasAbstraction: "0xf289b0a9", // executeWithGasAbstraction(bytes32,address,uint256,address,bytes)
  claimBridged: "0x9a670cd4", // claimBridged(uint256,bytes32,address,uint256,bytes32[])
  bondRelayer: "0xe4f60588", // bondRelayer()
  unbondRelayer: "0x62a4d339", // unbondRelayer(uint256)
  relayerBonds: "0x8d8c8956", // relayerBonds(address)
  voucherPoolBalance: "0x27752752", // voucherPoolBalance(address)
  usedVouchers: "0xbfa556e4", // usedVouchers(bytes32)
  voucherCommitments: "0xe2709c31", // voucherCommitments(bytes32)
  tokenGasRate: "0xf68a1b24", // tokenGasRate(address)
  bridgeOut: "0x9d10f39d", // bridgeOut(address,uint256,bytes32)
} as const;

export const EVENT_TOPICS = {
  TokensLocked: "0xa4be094914a85cba3c86e743880b4e94448959c3d16e0a0129074ee43215beec",
  BatchSubmitted: "0xf8bdcb220bb33287ecae1559d7d4b321695f12f68ec2ae16f201bcb76e51d09e",
  RelayedCall: "0x336c120340709b0ecd2d2fd46910bdef06033e7a1f58cd963b15f0ee99180c87",
  RelayerBonded: "0x58bce3aa73b75c871ef396fce6471e8ba804beee4f553ff8ba1a88b56d091216",
} as const;

/**
 * Encodes calldata for CrossEVMBridge.submitStateBatch(bytes32, bytes32)
 */
export function encodeSubmitStateBatch(
  sourceChainOrRoot: string | Uint8Array,
  stateRootOrDataHash: string | Uint8Array
): string {
  const p1 = Buffer.from(toBuffer32(sourceChainOrRoot)).toString("hex");
  const p2 = Buffer.from(toBuffer32(stateRootOrDataHash)).toString("hex");
  return SELECTORS.submitStateBatch + p1 + p2;
}

/**
 * Encodes calldata for GasRelayer.executeWithGasAbstraction(bytes32, address, uint256, address, bytes)
 */
export function encodeExecuteWithGasAbstraction(
  voucherNullifier: string | Uint8Array,
  feeToken: string,
  feeAmount: bigint,
  target: string,
  callData: string | Uint8Array
): string {
  const nullHex = Buffer.from(toBuffer32(voucherNullifier)).toString("hex");
  const tokenHex = padHex64(toAddressHex(feeToken));
  const amtHex = padHex64(feeAmount.toString(16));
  const targetHex = padHex64(toAddressHex(target));

  const rawData = typeof callData === "string" ? Buffer.from(cleanHex(callData), "hex") : Buffer.from(callData);
  const dataLen = rawData.length;
  const paddedLen = Math.ceil(dataLen / 32) * 32;
  const hexData = rawData.toString("hex").padEnd(paddedLen * 2, "0");

  // Head is 5 words = 160 bytes (0xa0) offset for dynamic bytes
  return (
    SELECTORS.executeWithGasAbstraction +
    nullHex +
    tokenHex +
    amtHex +
    targetHex +
    padHex64("a0") +
    padHex64(dataLen.toString(16)) +
    hexData
  );
}

/**
 * Encodes calldata for CrossEVMBridge.claimBridged(uint256, bytes32, address, uint256, bytes32[])
 */
export function encodeClaimBridged(
  batchId: bigint | number,
  nullifier: string | Uint8Array,
  recipient: string,
  amount: bigint,
  proof: (string | Uint8Array)[]
): string {
  const batchHex = padHex64(batchId.toString(16));
  const nullHex = Buffer.from(toBuffer32(nullifier)).toString("hex");
  const recipHex = padHex64(toAddressHex(recipient));
  const amtHex = padHex64(amount.toString(16));

  let proofWords = padHex64(proof.length.toString(16));
  for (const p of proof) {
    proofWords += Buffer.from(toBuffer32(p)).toString("hex");
  }

  // Head is 5 words = 160 bytes (0xa0) offset for dynamic bytes32[]
  return (
    SELECTORS.claimBridged +
    batchHex +
    nullHex +
    recipHex +
    amtHex +
    padHex64("a0") +
    proofWords
  );
}

/**
 * Encodes call to bondRelayer()
 */
export function encodeBondRelayer(): string {
  return SELECTORS.bondRelayer;
}

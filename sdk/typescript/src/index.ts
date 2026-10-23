import { createHash, randomBytes } from "node:crypto";

export enum AssetId {
  Seraph = 0,
  Xmr = 1,
}

export enum LaunchModel {
  FixedPool = 0,
  BondingCurve = 1,
  SeraphPool = 2,
}

export interface ShieldedNote {
  asset: AssetId;
  amount: bigint;
  recipientPubkey: Uint8Array;
  blinding: Uint8Array;
}

export interface LaunchConfig {
  name: string;
  symbol: string;
  description?: string;
  image?: string;
  website?: string;
  twitter?: string;
  telegram?: string;
  model: LaunchModel;
  totalSupply: bigint;
  feeWallet: string;
  buyFeeBps: number;
  sellFeeBps: number;
  creatorShareBps: number;
  buybackShareBps: number;
  dividendsShareBps: number;
  liquidityShareBps: number;
  platformShareBps: number;
  devBuyBps: number;
}

export const PLATFORM_FEE_BPS = 100;
export const MAX_CREATOR_FEE_BPS = 250;
export const MAX_DEV_BUY_BPS = 1000;
export const BPS = 10_000;

export const SERAPH_LAUNCHPAD_ABI = [
  "function launch((string name,string symbol,string description,string image,string website,string twitter,string telegram,uint8 model,uint256 totalSupply,address feeWallet,uint16 buyFeeBps,uint16 sellFeeBps,uint16 creatorShareBps,uint16 buybackShareBps,uint16 dividendsShareBps,uint16 liquidityShareBps,uint16 platformShareBps,uint16 devBuyBps) p) payable returns (address token)",
  "function buy(address token, uint256 minTokensOut, address recipient) payable returns (uint256 tokensOut)",
  "function sell(address token, uint256 tokenAmount, uint256 minQuoteOut, address recipient) returns (uint256 netQuoteOut)",
  "function graduate(address token)",
  "function claimFees() returns (uint256 amount)",
  "function quoteBuy(address token, uint256 grossQuoteIn) view returns (uint256 tokensOut, uint256 platformFee, uint256 creatorFee, uint256 refund)",
  "function quoteSell(address token, uint256 tokenAmount) view returns (uint256 netQuoteOut, uint256 platformFee, uint256 creatorFee)",
  "function quoteDevBuy(uint256 totalSupply, uint16 buyFeeBps, uint16 devBuyBps) view returns (uint256 ethRequired)",
  "function getLaunch(address token) view returns ((address token,address creator,address feeWallet,uint8 model,bool graduated,uint16 buyFeeBps,uint16 sellFeeBps,uint16 creatorShareBps,uint16 buybackShareBps,uint16 dividendsShareBps,uint16 liquidityShareBps,uint16 platformShareBps,uint16 devBuyBps,uint64 launchedAt,uint256 initialSupply,uint256 realQuoteReserve,uint256 phantomQuote,uint256 tokenReserve,uint256 reservedTokens,uint256 graduationThreshold))",
  "function totalLaunches() view returns (uint256)",
  "function allTokens(uint256 index) view returns (address)",
] as const;

export const PRIVACY_POOL_ABI = [
  "function shield(uint256 amount, bytes32 commitment, bytes encryptedNote) returns (uint32 leafIndex)",
  "function privateTransfer(bytes32[2] inputNullifiers, bytes32[2] outputCommitments, bytes32 root, bytes proof, bytes[2] encryptedNotes)",
  "function unshield(bytes32 nullifier, uint256 amount, address recipient, bytes32 root, bytes proof)",
  "function getLastRoot() view returns (bytes32)",
  "function isKnownRoot(bytes32 root) view returns (bool)",
] as const;

function sha256Tag(tag: string, ...chunks: Uint8Array[]): Uint8Array {
  const h = createHash("sha256");
  h.update(Buffer.from(tag, "utf8"));
  for (const c of chunks) h.update(c);
  return new Uint8Array(h.digest());
}

export function deriveWalletKeys(spendKey: Uint8Array): {
  spendKey: Uint8Array;
  viewKey: Uint8Array;
  pubkey: Uint8Array;
} {
  if (spendKey.length !== 32) throw new Error("spendKey must be 32 bytes");
  return {
    spendKey,
    viewKey: sha256Tag("seraph_viewkey_derive", spendKey),
    pubkey: sha256Tag("seraph_pubkey_derive", spendKey),
  };
}

export function computeNoteCommitment(note: ShieldedNote): Uint8Array {
  const amtBuf = Buffer.alloc(8);
  amtBuf.writeBigUInt64BE(note.amount);
  const assetBuf = new Uint8Array([note.asset]);
  return sha256Tag(
    "seraph_note_commitment_v1",
    assetBuf,
    amtBuf,
    note.recipientPubkey,
    note.blinding
  );
}

export function deriveNullifier(spendKey: Uint8Array, leafIndex: number): Uint8Array {
  const idxBuf = Buffer.alloc(4);
  idxBuf.writeUInt32BE(leafIndex >>> 0);
  return sha256Tag("seraph_nullifier_v1", spendKey, idxBuf);
}

export function validateLaunchConfig(cfg: LaunchConfig): void {
  if (!cfg.name || cfg.name.length > 32) throw new Error("Invalid token name (1..32 chars)");
  if (!cfg.symbol || cfg.symbol.length > 10) throw new Error("Invalid token symbol (1..10 chars)");
  if (cfg.description && cfg.description.length > 280) throw new Error("Description exceeds 280 chars");
  if (cfg.totalSupply < 10n ** 18n) throw new Error("totalSupply must be >= 1e18");
  if (cfg.buyFeeBps < 0 || cfg.buyFeeBps > MAX_CREATOR_FEE_BPS) {
    throw new Error("buyFeeBps exceeds 250 bps (2.5%) cap");
  }
  if (cfg.sellFeeBps < 0 || cfg.sellFeeBps > MAX_CREATOR_FEE_BPS) {
    throw new Error("sellFeeBps exceeds 250 bps (2.5%) cap");
  }
  const splitSum =
    cfg.creatorShareBps +
    cfg.buybackShareBps +
    cfg.dividendsShareBps +
    cfg.liquidityShareBps +
    cfg.platformShareBps;
  if (splitSum !== BPS) {
    throw new Error(`Fee split must sum to 10000 bps (got ${splitSum})`);
  }
  if (cfg.devBuyBps < 0 || cfg.devBuyBps > MAX_DEV_BUY_BPS) {
    throw new Error("devBuyBps exceeds 1000 bps (10%) cap");
  }
}

export function randomBytes32(): Uint8Array {
  return new Uint8Array(randomBytes(32));
}

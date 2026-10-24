import { createHash, randomBytes } from "node:crypto";

export const AssetId = {
  Seraph: 0,
  Xmr: 1,
} as const;
export type AssetId = (typeof AssetId)[keyof typeof AssetId];

export const LaunchModel = {
  FixedPool: 0,
  BondingCurve: 1,
  SeraphPool: 2,
} as const;
export type LaunchModel = (typeof LaunchModel)[keyof typeof LaunchModel];

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
  "function shield(uint256 amount, bytes32 commitment, bytes proof) returns (uint32 leafIndex)",
  "function shieldFor(address depositor, uint256 amount, bytes32 commitment, bytes proof) returns (uint32 leafIndex)",
  "function privateTransfer(bytes32[] nullifiers, bytes32[] commitments, bytes32 root, bytes proof)",
  "function unshield(bytes32 nullifier, uint256 amount, address recipient, bytes32 root, bytes proof)",
  "function getLastRoot() view returns (bytes32)",
  "function isKnownRoot(bytes32 root) view returns (bool)",
] as const;

export const CROSS_EVM_BRIDGE_ABI = [
  "function bondRelayer() payable",
  "function unbondRelayer(uint256 amount)",
  "function submitStateBatch(bytes32 sourceChainId, bytes32 stateRoot) returns (uint256 batchId)",
  "function challengeBatch(uint256 batchId, address challenger)",
  "function bridgeOut(address recipient, uint256 amount, bytes32 destChainId) returns (uint256 nonce)",
  "function claimBridged(uint256 batchId, bytes32 nullifier, address recipient, uint256 amount, bytes32[] merkleProof)",
] as const;

export const GAS_RELAYER_ABI = [
  "function fundGasVoucher(address feeToken, uint256 amount, bytes32 voucherCommitment)",
  "function executeWithGasAbstraction(bytes32 voucherNullifier, address feeToken, uint256 feeAmount, address target, bytes data) returns (bytes result)",
  "function setTokenGasRate(address feeToken, uint256 rate)",
] as const;

export const INVOICE_REGISTRY_ABI = [
  "function sendEncryptedMessage(bytes32 recipientPubkey, bytes32 ephemeralPubkey, bytes ciphertext)",
  "function createInvoice(bytes32 invoiceId, bytes32 stealthRecipient, address claimAddr, address token, uint256 amount, bytes encryptedMemo)",
  "function settleInvoice(bytes32 invoiceId, bytes32 paymentNullifier)",
] as const;

export const USAGE_VAULT_ABI = [
  "function depositCredits(bytes32 commitment, uint256 amount)",
  "function redeemUsageTicket(bytes32 commitment, bytes32 ticketNullifier, uint256 amount, bytes32 secretPreimage)",
  "function claimEarnings() returns (uint256 amount)",
] as const;

export const COLLATERAL_VAULT_ABI = [
  "function depositAndMint(uint256 collateralAmount, uint256 mintAmount)",
  "function burnAndWithdraw(uint256 burnAmount, uint256 withdrawCollateral)",
  "function setCollateralPrice(uint256 newPriceUsd)",
  "function positions(address user) view returns (uint256 collateral, uint256 debt)",
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

/**
 * Encrypts/decrypts a view-key memo using stream cipher matching base-layer Rust note::xor_memo
 */
export function xorViewKeyMemo(viewKey: Uint8Array, blinding: Uint8Array, data: Uint8Array): Uint8Array {
  if (viewKey.length !== 32 || blinding.length !== 32) {
    throw new Error("viewKey and blinding must be 32 bytes each");
  }
  const pad = sha256Tag("seraph_memo_stream", viewKey, blinding);
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) {
    out[i] = data[i] ^ pad[i % 32];
  }
  return out;
}

/**
 * Pure client-side constant-product bonding curve buy quote calculator
 */
export function estimateBondingCurveBuy(
  realQuoteReserve: bigint,
  phantomQuote: bigint,
  tokenReserve: bigint,
  reservedTokens: bigint,
  grossQuoteIn: bigint,
  buyFeeBps: number,
  graduated = false
): {
  tokensOut: bigint;
  platformFee: bigint;
  creatorFee: bigint;
  netQuoteIn: bigint;
  refund: bigint;
  graduates: boolean;
} {
  const quoteReserve = realQuoteReserve + phantomQuote;
  const platformFee = (grossQuoteIn * BigInt(PLATFORM_FEE_BPS)) / BigInt(BPS);
  const creatorFee = (grossQuoteIn * BigInt(buyFeeBps)) / BigInt(BPS);
  let netQuoteIn = grossQuoteIn - platformFee - creatorFee;

  let tokensOut = (tokenReserve * netQuoteIn) / (quoteReserve + netQuoteIn);
  const available = graduated
    ? tokenReserve
    : tokenReserve > reservedTokens
    ? tokenReserve - reservedTokens
    : 0n;

  let refund = 0n;
  const completesCurve = !graduated && tokensOut >= available;

  if (tokensOut > available) {
    tokensOut = available;
    const denom = tokenReserve - tokensOut;
    netQuoteIn = (quoteReserve * tokensOut + denom - 1n) / denom;
    const netBps = BigInt(BPS - PLATFORM_FEE_BPS - buyFeeBps);
    let grossUsed = (netQuoteIn * BigInt(BPS) + netBps - 1n) / netBps;
    if (grossUsed > grossQuoteIn) grossUsed = grossQuoteIn;
    refund = grossQuoteIn - grossUsed;
  }

  return {
    tokensOut,
    platformFee,
    creatorFee,
    netQuoteIn,
    refund,
    graduates: completesCurve,
  };
}

/**
 * Pure client-side constant-product bonding curve sell quote calculator
 */
export function estimateBondingCurveSell(
  realQuoteReserve: bigint,
  phantomQuote: bigint,
  tokenReserve: bigint,
  tokenAmount: bigint,
  sellFeeBps: number
): {
  netQuoteOut: bigint;
  platformFee: bigint;
  creatorFee: bigint;
} {
  const quoteReserve = realQuoteReserve + phantomQuote;
  let grossQuoteOut = (quoteReserve * tokenAmount) / (tokenReserve + tokenAmount);
  if (grossQuoteOut > realQuoteReserve) grossQuoteOut = realQuoteReserve;

  const platformFee = (grossQuoteOut * BigInt(PLATFORM_FEE_BPS)) / BigInt(BPS);
  const creatorFee = (grossQuoteOut * BigInt(sellFeeBps)) / BigInt(BPS);
  const netQuoteOut = grossQuoteOut - platformFee - creatorFee;

  return {
    netQuoteOut,
    platformFee,
    creatorFee,
  };
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

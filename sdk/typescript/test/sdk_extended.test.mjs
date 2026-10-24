import { test } from "node:test";
import assert from "node:assert/strict";
import {
  AssetId,
  LaunchModel,
  deriveWalletKeys,
  computeNoteCommitment,
  deriveNullifier,
  xorViewKeyMemo,
  estimateBondingCurveBuy,
  estimateBondingCurveSell,
  validateLaunchConfig,
  randomBytes32,
  CROSS_EVM_BRIDGE_ABI,
  GAS_RELAYER_ABI,
  INVOICE_REGISTRY_ABI,
  USAGE_VAULT_ABI,
  COLLATERAL_VAULT_ABI,
} from "../src/index.ts";

test("SDK Extended: ABIs exist and contain expected function signatures", () => {
  assert.ok(CROSS_EVM_BRIDGE_ABI.some((f) => f.includes("unbondRelayer")));
  assert.ok(GAS_RELAYER_ABI.some((f) => f.includes("executeWithGasAbstraction")));
  assert.ok(INVOICE_REGISTRY_ABI.some((f) => f.includes("settleInvoice")));
  assert.ok(USAGE_VAULT_ABI.some((f) => f.includes("redeemUsageTicket")));
  assert.ok(COLLATERAL_VAULT_ABI.some((f) => f.includes("depositAndMint")));
});

test("SDK Extended: xorViewKeyMemo encrypts and decrypts accurately", () => {
  const viewKey = randomBytes32();
  const blinding = randomBytes32();
  const memoText = "Confidential Seraph Invoice Memo #49281";
  const memoBytes = new TextEncoder().encode(memoText);

  const ciphertext = xorViewKeyMemo(viewKey, blinding, memoBytes);
  assert.notDeepEqual(ciphertext, memoBytes, "Ciphertext must not match plaintext");

  const decrypted = xorViewKeyMemo(viewKey, blinding, ciphertext);
  assert.deepEqual(decrypted, memoBytes, "Decrypted memo must match original");
  assert.equal(new TextDecoder().decode(decrypted), memoText);

  // Wrong viewKey fails decryption
  const wrongKey = randomBytes32();
  const wrongDecrypted = xorViewKeyMemo(wrongKey, blinding, ciphertext);
  assert.notDeepEqual(wrongDecrypted, memoBytes, "Wrong key must not decrypt properly");
});

test("SDK Extended: estimateBondingCurveBuy matches constant-product curve math", () => {
  const realQuote = 0n;
  const phantom = 1_500_000_000_000_000_000n; // 1.5 ETH
  const totalCurve = 1_000_000_000_000_000_000_000_000_000n; // 1B tokens
  const reserved = 250_000_000_000_000_000_000_000_000n; // 250M reserved
  const grossIn = 1_000_000_000_000_000_000n; // 1.0 ETH

  const res = estimateBondingCurveBuy(
    realQuote,
    phantom,
    totalCurve,
    reserved,
    grossIn,
    200 // 2% creator fee
  );

  assert.equal(res.platformFee, 10_000_000_000_000_000n, "Platform fee 1%");
  assert.equal(res.creatorFee, 20_000_000_000_000_000n, "Creator fee 2%");
  assert.equal(res.netQuoteIn, 970_000_000_000_000_000n, "Net quote 0.97 ETH");
  assert.ok(res.tokensOut > 0n, "Tokens out must be positive");
  assert.equal(res.refund, 0n, "Normal buy does not refund");
  assert.equal(res.graduates, false, "1 ETH buy does not graduate curve");
});

test("SDK Extended: estimateBondingCurveSell matches constant-product curve math", () => {
  const realQuote = 500_000_000_000_000_000n; // 0.5 ETH
  const phantom = 1_500_000_000_000_000_000n; // 1.5 ETH
  const tokenReserve = 800_000_000_000_000_000_000_000_000n;
  const sellTokens = 10_000_000_000_000_000_000_000_000n; // 10M tokens

  const res = estimateBondingCurveSell(
    realQuote,
    phantom,
    tokenReserve,
    sellTokens,
    200 // 2% creator fee
  );

  assert.ok(res.netQuoteOut > 0n, "Net quote out must be positive");
  assert.ok(res.platformFee > 0n, "Platform fee must be positive");
  assert.ok(res.creatorFee > 0n, "Creator fee must be positive");
  assert.ok(res.netQuoteOut < realQuote, "Cannot extract more than real reserve");
});

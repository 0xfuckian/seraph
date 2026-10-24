import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  CrossEVMBridgeClient,
  GasRelayerClient,
  InvoiceRegistryClient,
  randomBytes32,
  CROSS_EVM_BRIDGE_ABI,
  GAS_RELAYER_ABI,
  INVOICE_REGISTRY_ABI,
} from "../src/index.ts";

function parseEVMCalldata(hex) {
  const raw = hex.startsWith("0x") ? hex.slice(2) : hex;
  const selector = "0x" + raw.slice(0, 8);
  const body = raw.slice(8);
  const words = [];
  for (let i = 0; i < body.length; i += 64) {
    words.push(body.slice(i, i + 64));
  }
  return { selector, words };
}

test("1. CrossEVMBridgeClient: computeBridgeLeaf cryptographic binding and domain isolation", () => {
  const bridgeAddr = "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF";
  const bridge = new CrossEVMBridgeClient(bridgeAddr);
  assert.equal(bridge.bridgeAddress, bridgeAddr);

  const nullifier = randomBytes32();
  const recip = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const amount = 1000n * 10n ** 18n;
  const destChain = Buffer.alloc(32);
  destChain.write("seraph_evm");

  const leaf1 = bridge.computeBridgeLeaf(nullifier, recip, amount, destChain);
  assert.equal(leaf1.length, 32);

  // Determinism
  const leaf1Dup = bridge.computeBridgeLeaf(nullifier, recip, amount, destChain);
  assert.deepEqual(leaf1, leaf1Dup);

  // Address case insensitivity
  const leafLower = bridge.computeBridgeLeaf(nullifier, recip.toLowerCase(), amount, destChain);
  assert.deepEqual(leaf1, leafLower);

  // Domain isolation: altering nullifier
  const nullifier2 = randomBytes32();
  const leaf2 = bridge.computeBridgeLeaf(nullifier2, recip, amount, destChain);
  assert.notDeepEqual(leaf1, leaf2);

  // Domain isolation: altering amount
  const leaf3 = bridge.computeBridgeLeaf(nullifier, recip, amount + 1n, destChain);
  assert.notDeepEqual(leaf1, leaf3);

  // Domain isolation: altering destination chain
  const destChainXmr = Buffer.alloc(32);
  destChainXmr.write("xmr_evm");
  const leaf4 = bridge.computeBridgeLeaf(nullifier, recip, amount, destChainXmr);
  assert.notDeepEqual(leaf1, leaf4);
});

test("2. CrossEVMBridgeClient: encodeBridgeOut ABI layout and exact Solc selector match", () => {
  const bridge = new CrossEVMBridgeClient("0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF");
  const recip = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const amount = 500n * 10n ** 18n;
  const destChain = Buffer.alloc(32);
  destChain.write("xmr_evm");

  const call = bridge.encodeBridgeOut(recip, amount, destChain);
  assert.equal(call.to, bridge.bridgeAddress);
  assert.ok(call.data.startsWith("0x9d10f39d"), "Must match Solc bridgeOut selector");

  // Calldata length: 4 bytes selector + 3 * 32 bytes = 100 bytes (202 chars with 0x)
  assert.equal(call.data.length, 2 + 8 + 3 * 64);

  const parsed = parseEVMCalldata(call.data);
  assert.equal(parsed.selector, "0x9d10f39d");
  assert.equal(parsed.words.length, 3);
  assert.equal("0x" + parsed.words[0].slice(24), recip.toLowerCase());
  assert.equal(BigInt("0x" + parsed.words[1]), amount);
  assert.equal(parsed.words[2], Buffer.from(destChain).toString("hex"));
});

test("3. CrossEVMBridgeClient: encodeClaimBridged dynamic array offset and proof serialization", () => {
  const bridge = new CrossEVMBridgeClient("0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF");
  const batchId = 17n;
  const nullifier = randomBytes32();
  const recip = "0x90F79bf6EB2c4f870365E785982E1f101E93b906";
  const amount = 750n * 10n ** 18n;

  // 4-element Merkle proof
  const proof = [randomBytes32(), randomBytes32(), randomBytes32(), randomBytes32()];
  const call = bridge.encodeClaimBridged(batchId, nullifier, recip, amount, proof);

  assert.equal(call.to, bridge.bridgeAddress);
  assert.ok(call.data.startsWith("0x9a670cd4"), "Must match Solc claimBridged selector");

  const parsed = parseEVMCalldata(call.data);
  assert.equal(parsed.selector, "0x9a670cd4");
  // 5 head words + 1 length word + 4 proof words = 10 words
  assert.equal(parsed.words.length, 10);
  assert.equal(BigInt("0x" + parsed.words[0]), batchId);
  assert.equal(parsed.words[1], Buffer.from(nullifier).toString("hex"));
  assert.equal("0x" + parsed.words[2].slice(24), recip.toLowerCase());
  assert.equal(BigInt("0x" + parsed.words[3]), amount);
  // Offset to dynamic bytes32[] array: 5 words * 32 = 160 (0xa0)
  assert.equal(parseInt(parsed.words[4], 16), 160);
  assert.equal(parseInt(parsed.words[5], 16), 4, "Proof length must be 4");

  for (let i = 0; i < 4; i++) {
    assert.equal(parsed.words[6 + i], Buffer.from(proof[i]).toString("hex"));
  }
});

test("4. GasRelayerClient: createVoucher commitment binding and domain isolation", () => {
  const relayer = new GasRelayerClient("0x8b5F2A84c7E1a37c0245a4944c6691c94488b394");
  const feeToken = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const amount = 250000000000000000n; // 0.25 SER

  const v1 = relayer.createVoucher(feeToken, amount);
  assert.equal(v1.secret.length, 32);
  assert.equal(v1.commitment.length, 32);

  // Deterministic secret parameter
  const customSecret = new Uint8Array(32).fill(42);
  const v2 = relayer.createVoucher(feeToken, amount, customSecret);
  assert.deepEqual(v2.secret, customSecret);

  const v2Dup = relayer.createVoucher(feeToken, amount, customSecret);
  assert.deepEqual(v2.commitment, v2Dup.commitment);

  // Altering fee token alters commitment
  const diffToken = "0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A";
  const v3 = relayer.createVoucher(diffToken, amount, customSecret);
  assert.notDeepEqual(v2.commitment, v3.commitment);
});

test("5. GasRelayerClient: encodeFundGasVoucher layout and selector match", () => {
  const relayer = new GasRelayerClient("0x8b5F2A84c7E1a37c0245a4944c6691c94488b394");
  const feeToken = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const amount = 1000000000000000000n;
  const commitment = randomBytes32();

  const call = relayer.encodeFundGasVoucher(feeToken, amount, commitment);
  assert.equal(call.to, relayer.relayerAddress);
  assert.ok(call.data.startsWith("0x74629578"), "Must match Solc fundGasVoucher selector");

  const parsed = parseEVMCalldata(call.data);
  assert.equal(parsed.selector, "0x74629578");
  assert.equal(parsed.words.length, 3);
  assert.equal("0x" + parsed.words[0].slice(24), feeToken.toLowerCase());
  assert.equal(BigInt("0x" + parsed.words[1]), amount);
  assert.equal(parsed.words[2], Buffer.from(commitment).toString("hex"));
});

test("6. GasRelayerClient: encodeExecuteWithGasAbstraction arbitrary calldata packaging", () => {
  const relayer = new GasRelayerClient("0x8b5F2A84c7E1a37c0245a4944c6691c94488b394");
  const nullifier = randomBytes32();
  const feeToken = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const feeAmt = 50000000000000000n;
  const target = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const innerCall = Buffer.from("deadbeefcafebabe010203040506070809", "hex"); // 17 bytes

  const call = relayer.encodeExecuteWithGasAbstraction(nullifier, feeToken, feeAmt, target, innerCall);
  assert.equal(call.to, relayer.relayerAddress);
  assert.ok(call.data.startsWith("0xf289b0a9"), "Must match Solc executeWithGasAbstraction selector");

  const parsed = parseEVMCalldata(call.data);
  assert.equal(parsed.selector, "0xf289b0a9");
  // 5 head words + 1 length word + 1 word for 17 bytes (padded to 32) = 7 words
  assert.equal(parsed.words.length, 7);
  assert.equal(parsed.words[0], Buffer.from(nullifier).toString("hex"));
  assert.equal("0x" + parsed.words[1].slice(24), feeToken.toLowerCase());
  assert.equal(BigInt("0x" + parsed.words[2]), feeAmt);
  assert.equal("0x" + parsed.words[3].slice(24), target.toLowerCase());
  assert.equal(parseInt(parsed.words[4], 16), 160, "Dynamic bytes offset must be 160 (0xa0)");
  assert.equal(parseInt(parsed.words[5], 16), 17, "Bytes length must be 17");
  assert.ok(parsed.words[6].startsWith(innerCall.toString("hex")), "Payload must be preserved with right zero-padding");
});

test("7. InvoiceRegistryClient: stream cipher encryption, decryption, and entropy", () => {
  const registry = new InvoiceRegistryClient("0x5FbDB2315678afecb367f032d93F642f64180aa3");
  const recipientKey = randomBytes32();

  const originalMsg = "Private payment memo for Seraph GPU cluster inference invoice #90124";
  const enc = registry.encryptMessage(recipientKey, originalMsg);

  assert.equal(enc.ephemeralSecret.length, 32);
  assert.equal(enc.ephemeralPubkey.length, 32);
  assert.equal(enc.ciphertext.length, Buffer.from(originalMsg).length);
  assert.notDeepEqual(enc.ciphertext, Buffer.from(originalMsg), "Ciphertext must have high entropy");

  // Accurate decryption
  const decrypted = registry.decryptMessage(recipientKey, enc.ephemeralPubkey, enc.ciphertext);
  assert.equal(decrypted, originalMsg);

  // Wrong key corrupts plaintext
  const wrongKey = randomBytes32();
  const corrupted = registry.decryptMessage(wrongKey, enc.ephemeralPubkey, enc.ciphertext);
  assert.notEqual(corrupted, originalMsg);

  // Bit flip in ciphertext affects only that single character
  const tamperedCipher = new Uint8Array(enc.ciphertext);
  tamperedCipher[0] ^= 0x01; // flip 1 bit
  const tamperedDec = registry.decryptMessage(recipientKey, enc.ephemeralPubkey, tamperedCipher);
  assert.notEqual(tamperedDec[0], originalMsg[0]);
  assert.equal(tamperedDec.slice(1), originalMsg.slice(1), "Subsequent characters must remain intact");
});

test("8. InvoiceRegistryClient: encodeSendMessage layout and dynamic padding", () => {
  const registry = new InvoiceRegistryClient("0x5FbDB2315678afecb367f032d93F642f64180aa3");
  const recipPub = randomBytes32();
  const ephPub = randomBytes32();
  const cipher = Buffer.from("encrypted stealth payload (28 bytes)");

  const call = registry.encodeSendMessage(recipPub, ephPub, cipher);
  assert.equal(call.to, registry.registryAddress);
  assert.ok(call.data.startsWith("0x4e94e35b"), "Must match Solc sendEncryptedMessage selector");

  const parsed = parseEVMCalldata(call.data);
  assert.equal(parsed.selector, "0x4e94e35b");
  // 3 head words + 1 length word + 2 words for 36 bytes (padded to 64) = 6 words
  assert.equal(parsed.words.length, 6);
  assert.equal(parsed.words[0], Buffer.from(recipPub).toString("hex"));
  assert.equal(parsed.words[1], Buffer.from(ephPub).toString("hex"));
  assert.equal(parseInt(parsed.words[2], 16), 96, "Offset to bytes must be 96 (0x60)");
  assert.equal(parseInt(parsed.words[3], 16), 36, "Cipher length must match bytes");

  // Also verify single-word padding boundary with exactly 28 bytes
  const cipher28 = Buffer.from("encrypted stealth payload 28");
  assert.equal(cipher28.length, 28);
  const call28 = registry.encodeSendMessage(recipPub, ephPub, cipher28);
  const parsed28 = parseEVMCalldata(call28.data);
  assert.equal(parsed28.words.length, 5); // 3 head + 1 length + 1 word (padded to 32)
  assert.equal(parseInt(parsed28.words[3], 16), 28);
});

test("9. InvoiceRegistryClient: encodeCreateInvoice and encodeSettleInvoice calldata verification", () => {
  const registry = new InvoiceRegistryClient("0x5FbDB2315678afecb367f032d93F642f64180aa3");
  const invId = randomBytes32();
  const stealthRecip = randomBytes32();
  const claimAddr = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const token = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const amount = 1000n * 10n ** 18n;
  const memo = Buffer.from("Invoice for 100 Seraph compute units");

  const createCall = registry.encodeCreateInvoice(invId, stealthRecip, claimAddr, token, amount, memo);
  assert.equal(createCall.to, registry.registryAddress);
  assert.ok(createCall.data.startsWith("0x4bba01b6"), "Must match Solc createInvoice selector");

  const pCreate = parseEVMCalldata(createCall.data);
  assert.equal(pCreate.selector, "0x4bba01b6");
  // 6 head words + 1 length word + 2 words for memo (36 bytes padded to 64) = 9 words
  assert.equal(pCreate.words.length, 9);
  assert.equal(pCreate.words[0], Buffer.from(invId).toString("hex"));
  assert.equal(pCreate.words[1], Buffer.from(stealthRecip).toString("hex"));
  assert.equal("0x" + pCreate.words[2].slice(24), claimAddr.toLowerCase());
  assert.equal("0x" + pCreate.words[3].slice(24), token.toLowerCase());
  assert.equal(BigInt("0x" + pCreate.words[4]), amount);
  assert.equal(parseInt(pCreate.words[5], 16), 192, "Offset to encryptedMemo must be 192 (0xc0)");

  // Settle invoice
  const nullifier = randomBytes32();
  const settleCall = registry.encodeSettleInvoice(invId, nullifier);
  assert.equal(settleCall.to, registry.registryAddress);
  assert.ok(settleCall.data.startsWith("0x28ea8ccf"), "Must match Solc settleInvoice selector");

  const pSettle = parseEVMCalldata(settleCall.data);
  assert.equal(pSettle.selector, "0x28ea8ccf");
  assert.equal(pSettle.words.length, 2);
  assert.equal(pSettle.words[0], Buffer.from(invId).toString("hex"));
  assert.equal(pSettle.words[1], Buffer.from(nullifier).toString("hex"));
});

test("10. Contract ABI Parity: client method selectors match ABI signatures", () => {
  assert.ok(CROSS_EVM_BRIDGE_ABI.some((f) => f.includes("bridgeOut")));
  assert.ok(CROSS_EVM_BRIDGE_ABI.some((f) => f.includes("claimBridged")));
  assert.ok(GAS_RELAYER_ABI.some((f) => f.includes("fundGasVoucher")));
  assert.ok(GAS_RELAYER_ABI.some((f) => f.includes("executeWithGasAbstraction")));
  assert.ok(INVOICE_REGISTRY_ABI.some((f) => f.includes("sendEncryptedMessage")));
  assert.ok(INVOICE_REGISTRY_ABI.some((f) => f.includes("createInvoice")));
  assert.ok(INVOICE_REGISTRY_ABI.some((f) => f.includes("settleInvoice")));
});

test("11. CrossEVMBridgeClient: empty, single, and depth-20 Merkle tree proof boundaries", () => {
  const bridge = new CrossEVMBridgeClient("0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF");
  const nullifier = randomBytes32();
  const recip = "0x90F79bf6EB2c4f870365E785982E1f101E93b906";
  const amount = 50_000n * 10n ** 18n;

  // Empty proof
  const emptyCall = bridge.encodeClaimBridged(1n, nullifier, recip, amount, []);
  const pEmpty = parseEVMCalldata(emptyCall.data);
  assert.equal(parseInt(pEmpty.words[4], 16), 160);
  assert.equal(parseInt(pEmpty.words[5], 16), 0);
  assert.equal(pEmpty.words.length, 6);

  // Single-element proof
  const singleProof = [randomBytes32()];
  const singleCall = bridge.encodeClaimBridged(2n, nullifier, recip, amount, singleProof);
  const pSingle = parseEVMCalldata(singleCall.data);
  assert.equal(parseInt(pSingle.words[5], 16), 1);
  assert.equal(pSingle.words[6], Buffer.from(singleProof[0]).toString("hex"));
  assert.equal(pSingle.words.length, 7);

  // Depth-20 tree proof (full production Merkle tree path)
  const depth20 = Array.from({ length: 20 }, () => randomBytes32());
  const deepCall = bridge.encodeClaimBridged(99n, nullifier, recip, amount, depth20);
  const pDeep = parseEVMCalldata(deepCall.data);
  assert.equal(parseInt(pDeep.words[5], 16), 20);
  assert.equal(pDeep.words.length, 5 + 1 + 20);
  for (let i = 0; i < 20; i++) {
    assert.equal(pDeep.words[6 + i], Buffer.from(depth20[i]).toString("hex"));
  }
});

test("12. GasRelayerClient: arbitrary calldata framing (empty, 4-byte selector, and multi-word)", () => {
  const relayer = new GasRelayerClient("0x8b5F2A84c7E1a37c0245a4944c6691c94488b394");
  const nullifier = randomBytes32();
  const feeToken = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const feeAmt = 10000000000000000n;
  const target = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

  // Empty calldata (0 bytes)
  const emptyCall = relayer.encodeExecuteWithGasAbstraction(nullifier, feeToken, feeAmt, target, new Uint8Array(0));
  const pEmpty = parseEVMCalldata(emptyCall.data);
  assert.equal(parseInt(pEmpty.words[5], 16), 0);
  assert.equal(pEmpty.words.length, 6);

  // 4-byte function selector (e.g. paused() -> 0x5c975abb)
  const selBytes = Buffer.from("5c975abb", "hex");
  const selCall = relayer.encodeExecuteWithGasAbstraction(nullifier, feeToken, feeAmt, target, selBytes);
  const pSel = parseEVMCalldata(selCall.data);
  assert.equal(parseInt(pSel.words[5], 16), 4);
  assert.equal(pSel.words.length, 7);
  assert.equal(pSel.words[6], "5c975abb" + "0".repeat(56));

  // 68-byte payload (e.g., function selector + two 32-byte arguments)
  const multiWord = new Uint8Array(68).fill(0xee);
  const multiCall = relayer.encodeExecuteWithGasAbstraction(nullifier, feeToken, feeAmt, target, multiWord);
  const pMulti = parseEVMCalldata(multiCall.data);
  assert.equal(parseInt(pMulti.words[5], 16), 68);
  assert.equal(pMulti.words.length, 5 + 1 + 3); // 5 head + 1 length + 3 words
  assert.equal(pMulti.words[6], "ee".repeat(32));
  assert.equal(pMulti.words[7], "ee".repeat(32));
  assert.equal(pMulti.words[8], "ee".repeat(4) + "0".repeat(56));
});

test("13. InvoiceRegistryClient: stream cipher test vectors (multibyte, emojis, JSON, and large payloads)", () => {
  const registry = new InvoiceRegistryClient("0x5FbDB2315678afecb367f032d93F642f64180aa3");
  const recipientKey = randomBytes32();

  const vectors = [
    "", // Empty payload
    "Exactly 32-byte message here!!!!", // 1 full block
    "Special characters: 🛡️ Privacy Continuum · 秘密の送金 · π ≈ 3.1415926535",
    JSON.stringify({
      invoiceId: "0xabcdef123456",
      merchant: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
      items: ["AI Compute Node #1", "ZK Proof Verification Voucher"],
      total: "250000000000000000000",
      token: "SER",
    }),
    "Z".repeat(512), // 16 rounds of 32-byte keystream pad wrapping
  ];

  for (const text of vectors) {
    const enc = registry.encryptMessage(recipientKey, text);
    assert.equal(enc.ciphertext.length, Buffer.byteLength(text, "utf8"));
    const dec = registry.decryptMessage(recipientKey, enc.ephemeralPubkey, enc.ciphertext);
    assert.equal(dec, text);
  }
});

test("14. InvoiceRegistryClient: stream cipher security properties and tamper isolation", () => {
  const registry = new InvoiceRegistryClient("0x5FbDB2315678afecb367f032d93F642f64180aa3");
  const recipientKey = randomBytes32();
  const secretText = "Confidential payment authorization token";

  const enc = registry.encryptMessage(recipientKey, secretText);

  // Wrong view key cannot recover plaintext
  const wrongKey = randomBytes32();
  const badDec = registry.decryptMessage(wrongKey, enc.ephemeralPubkey, enc.ciphertext);
  assert.notEqual(badDec, secretText);

  // Wrong ephemeral pubkey cannot recover plaintext
  const badEphPub = randomBytes32();
  const badEphDec = registry.decryptMessage(recipientKey, badEphPub, enc.ciphertext);
  assert.notEqual(badEphDec, secretText);

  // Fresh encryption generates distinct ephemeral secret and unique ciphertext
  const enc2 = registry.encryptMessage(recipientKey, secretText);
  assert.notDeepEqual(enc.ephemeralSecret, enc2.ephemeralSecret);
  assert.notDeepEqual(enc.ciphertext, enc2.ciphertext);

  // Stream cipher bit flip property: flipping 1 bit affects only 1 byte in plaintext
  const tampered = new Uint8Array(enc.ciphertext);
  tampered[5] ^= 0x01;
  const tamperedDec = registry.decryptMessage(recipientKey, enc.ephemeralPubkey, tampered);
  assert.notEqual(tamperedDec[5], secretText[5]);
  assert.equal(tamperedDec.slice(0, 5), secretText.slice(0, 5));
  assert.equal(tamperedDec.slice(6), secretText.slice(6));
});

test("15. End-to-End Protocol Flow: Stealth Invoicing -> Relayed Settlement -> Cross-EVM Bridge Transfer", () => {
  const bridge = new CrossEVMBridgeClient("0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF");
  const relayer = new GasRelayerClient("0x8b5F2A84c7E1a37c0245a4944c6691c94488b394");
  const invoice = new InvoiceRegistryClient("0x5FbDB2315678afecb367f032d93F642f64180aa3");

  const merchantKey = randomBytes32();
  const merchantClaimAddr = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const serToken = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const invAmount = 500n * 10n ** 18n; // 500 SER

  // 1. Merchant registers stealth invoice with encrypted memo
  const invId = randomBytes32();
  const stealthRecip = randomBytes32();
  const { ephemeralPubkey, ciphertext: encMemo } = invoice.encryptMessage(
    merchantKey,
    "Invoice #5021: AI Model Training Cluster (500 SER)"
  );
  const createCall = invoice.encodeCreateInvoice(invId, stealthRecip, merchantClaimAddr, serToken, invAmount, encMemo);
  assert.equal(createCall.to, invoice.registryAddress);
  assert.ok(createCall.data.startsWith("0x4bba01b6"));

  // Merchant decrypts invoice memo
  const decryptedMemo = invoice.decryptMessage(merchantKey, ephemeralPubkey, encMemo);
  assert.equal(decryptedMemo, "Invoice #5021: AI Model Training Cluster (500 SER)");

  // 2. Payer funds a gas voucher in GasRelayer to pay without linking gas wallet
  const voucherSecret = randomBytes32();
  const voucher = relayer.createVoucher(serToken, 10n * 10n ** 18n, voucherSecret);
  const fundCall = relayer.encodeFundGasVoucher(serToken, 10n * 10n ** 18n, voucher.commitment);
  assert.equal(fundCall.to, relayer.relayerAddress);
  assert.ok(fundCall.data.startsWith("0x74629578"));

  // 3. Payer constructs invoice settlement call
  const paymentNullifier = randomBytes32();
  const settleCall = invoice.encodeSettleInvoice(invId, paymentNullifier);
  assert.equal(settleCall.to, invoice.registryAddress);
  assert.ok(settleCall.data.startsWith("0x28ea8ccf"));

  // 4. Relayer executes settleInvoice on InvoiceRegistry with gas abstraction
  const innerCall = Buffer.from(settleCall.data.slice(2), "hex");
  const voucherNullifier = randomBytes32();
  const execCall = relayer.encodeExecuteWithGasAbstraction(
    voucherNullifier,
    serToken,
    250000000000000000n, // 0.25 SER relayer fee
    invoice.registryAddress,
    innerCall
  );
  assert.equal(execCall.to, relayer.relayerAddress);
  assert.ok(execCall.data.startsWith("0xf289b0a9"));

  // 5. Merchant bridges funds to Seraph EVM
  const destChain = Buffer.alloc(32);
  destChain.write("seraph_evm");
  const leaf = bridge.computeBridgeLeaf(paymentNullifier, merchantClaimAddr, invAmount, destChain);
  assert.equal(leaf.length, 32);

  const bridgeOutCall = bridge.encodeBridgeOut(merchantClaimAddr, invAmount, destChain);
  assert.equal(bridgeOutCall.to, bridge.bridgeAddress);
  assert.ok(bridgeOutCall.data.startsWith("0x9d10f39d"));

  // 6. Relayer finalizes bridged transfer with Merkle proof
  const proof = [randomBytes32(), randomBytes32()];
  const claimCall = bridge.encodeClaimBridged(1n, paymentNullifier, merchantClaimAddr, invAmount, proof);
  assert.equal(claimCall.to, bridge.bridgeAddress);
  assert.ok(claimCall.data.startsWith("0x9a670cd4"));
});

test("16. Exact Keccak-256 method selector calculation parity against Solidity specifications", () => {
  function sel(sig) {
    return "0x" + createHash("keccak-256").update(sig).digest("hex").slice(0, 8);
  }

  // CrossEVMBridge
  assert.equal(sel("bridgeOut(address,uint256,bytes32)"), "0x9d10f39d");
  assert.equal(sel("claimBridged(uint256,bytes32,address,uint256,bytes32[])"), "0x9a670cd4");
  assert.equal(sel("submitStateBatch(bytes32,bytes32)"), "0x69f589b0");
  assert.equal(sel("challengeBatch(uint256,address)"), "0x84cf2119");
  assert.equal(sel("bondRelayer()"), "0xe4f60588");
  assert.equal(sel("unbondRelayer(uint256)"), "0xd0efab97");

  // GasRelayer
  assert.equal(sel("fundGasVoucher(address,uint256,bytes32)"), "0x74629578");
  assert.equal(sel("executeWithGasAbstraction(bytes32,address,uint256,address,bytes)"), "0xf289b0a9");
  assert.equal(sel("setTokenGasRate(address,uint256)"), "0x4ef612b5");

  // InvoiceRegistry
  assert.equal(sel("sendEncryptedMessage(bytes32,bytes32,bytes)"), "0x4e94e35b");
  assert.equal(sel("createInvoice(bytes32,bytes32,address,address,uint256,bytes)"), "0x4bba01b6");
  assert.equal(sel("settleInvoice(bytes32,bytes32)"), "0x28ea8ccf");
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";

import {
  SeraphRelayerDaemon,
  InsufficientRelayerBondError,
  CrossChainBridgeBatcher,
  GasAbstractionDispatcher,
  MerkleTree,
  MockEVMProvider,
  keccak256,
  keccak256Hex,
  sha256Tag,
  computeBridgeLeaf,
  computeBridgeLeafKeccak,
  computeBridgeLeafSha256,
  hashSortedPair,
  cleanHex,
  padHex64,
  toBuffer32,
  toAddressHex,
  encodeSubmitStateBatch,
  encodeExecuteWithGasAbstraction,
  encodeClaimBridged,
  encodeBondRelayer,
  SELECTORS,
  EVENT_TOPICS,
} from "../src/index.ts";

function randomBytes32() {
  return new Uint8Array(randomBytes(32));
}

// =========================================================================
// 1. Cryptographic Primitives & Leaf Hashing
// =========================================================================

test("1. Cryptographic Primitives: keccak256 and sha256Tag parity & domain isolation", () => {
  // Test vector for keccak256("hello")
  const h1 = keccak256Hex(Buffer.from("hello", "utf8"));
  assert.equal(h1, "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8");

  // sha256Tag domain isolation
  const tag1 = sha256Tag("seraph_test_tag", Buffer.from("data1"));
  const tag2 = sha256Tag("seraph_test_tag_alt", Buffer.from("data1"));
  assert.equal(tag1.length, 32);
  assert.equal(tag2.length, 32);
  assert.notDeepEqual(tag1, tag2, "Different tags must yield distinct hashes");
});

test("2. Leaf Hashing: computeBridgeLeafKeccak matches Solidity abi.encodePacked layout", () => {
  const nullifier = randomBytes32();
  const recipient = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const amount = 500n * 10n ** 18n;
  const chainId = "seraph_evm";

  const leaf = computeBridgeLeafKeccak(nullifier, recipient, amount, chainId);
  assert.equal(leaf.length, 32);

  // Manual recreation of Solidity abi.encodePacked(nullifier, recipient, amount, localChainId)
  // 32 bytes + 20 bytes + 32 bytes + 32 bytes = 116 bytes
  const nullBuf = Buffer.from(nullifier);
  const recipBuf = Buffer.from(cleanHex(recipient), "hex");
  const amtBuf = Buffer.from(padHex64(amount.toString(16)), "hex");
  const chainBuf = toBuffer32(chainId);
  const packed = Buffer.concat([nullBuf, recipBuf, amtBuf, chainBuf]);
  assert.equal(packed.length, 116, "Solidity packed leaf preimage must be exactly 116 bytes");

  const expectedLeaf = keccak256(packed);
  assert.deepEqual(leaf, expectedLeaf, "computeBridgeLeafKeccak must match exact Solidity packed keccak256");

  // Address checksum case insensitivity
  const leafLower = computeBridgeLeafKeccak(nullifier, recipient.toLowerCase(), amount, chainId);
  assert.deepEqual(leaf, leafLower);
});

test("3. Leaf Hashing: computeBridgeLeafSha256 domain-tagged hashing", () => {
  const nullifier = randomBytes32();
  const recipient = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const amount = 1000n * 10n ** 18n;
  const chainId = "xmr_evm";

  const leafSha = computeBridgeLeafSha256(nullifier, recipient, amount, chainId);
  assert.equal(leafSha.length, 32);

  // Determinism
  const leafSha2 = computeBridgeLeafSha256(nullifier, recipient, amount, chainId);
  assert.deepEqual(leafSha, leafSha2);

  // Altering parameters changes leaf
  const leafDiffAmt = computeBridgeLeafSha256(nullifier, recipient, amount + 1n, chainId);
  assert.notDeepEqual(leafSha, leafDiffAmt);
});

test("4. hashSortedPair: commutative sorted order & determinism", () => {
  const a = randomBytes32();
  const b = randomBytes32();

  const hAB = hashSortedPair(a, b);
  const hBA = hashSortedPair(b, a);
  assert.deepEqual(hAB, hBA, "Sorted pair hashing must be commutative: H(A, B) === H(B, A)");
  assert.equal(hAB.length, 32);
});

test("5. Method Selectors: exact parity with CrossEVMBridge and GasRelayer Solidity ABI", () => {
  const computeSel = (sig) => "0x" + createHash("keccak-256").update(sig).digest("hex").slice(0, 8);

  assert.equal(SELECTORS.submitStateBatch, computeSel("submitStateBatch(bytes32,bytes32)"));
  assert.equal(SELECTORS.executeWithGasAbstraction, computeSel("executeWithGasAbstraction(bytes32,address,uint256,address,bytes)"));
  assert.equal(SELECTORS.claimBridged, computeSel("claimBridged(uint256,bytes32,address,uint256,bytes32[])"));
  assert.equal(SELECTORS.bondRelayer, computeSel("bondRelayer()"));
  assert.equal(SELECTORS.relayerBonds, computeSel("relayerBonds(address)"));
  assert.equal(SELECTORS.voucherPoolBalance, computeSel("voucherPoolBalance(address)"));
  assert.equal(SELECTORS.usedVouchers, computeSel("usedVouchers(bytes32)"));
  assert.equal(SELECTORS.tokenGasRate, computeSel("tokenGasRate(address)"));

  // Event topics
  const computeTopic = (sig) => "0x" + createHash("keccak-256").update(sig).digest("hex");
  assert.equal(EVENT_TOPICS.TokensLocked, computeTopic("TokensLocked(uint256,address,address,uint256,bytes32)"));
  assert.equal(EVENT_TOPICS.BatchSubmitted, computeTopic("BatchSubmitted(uint256,bytes32,bytes32,address)"));
  assert.equal(EVENT_TOPICS.RelayedCall, computeTopic("RelayedCall(bytes32,address,address,address,uint256)"));
});

// =========================================================================
// 2. Merkle Tree & Inclusion Proof Verification
// =========================================================================

test("6. MerkleTree: boundary conditions (0 leaves, 1 leaf, 2 leaves)", () => {
  // Empty tree
  const tree0 = new MerkleTree([]);
  assert.equal(tree0.getRootHex(), "0x" + "00".repeat(32));

  // 1 leaf
  const leaf1 = randomBytes32();
  const tree1 = new MerkleTree([leaf1]);
  assert.deepEqual(tree1.getRoot(), leaf1);
  const p1 = tree1.getProof(0);
  assert.equal(p1.length, 0);
  assert.ok(MerkleTree.verify(leaf1, p1, tree1.getRoot()));

  // 2 leaves
  const leafA = randomBytes32();
  const leafB = randomBytes32();
  const tree2 = new MerkleTree([leafA, leafB]);
  const root2 = hashSortedPair(leafA, leafB);
  assert.deepEqual(tree2.getRoot(), root2);

  const proofA = tree2.getProof(0);
  assert.equal(proofA.length, 1);
  assert.deepEqual(proofA[0], leafB);
  assert.ok(MerkleTree.verify(leafA, proofA, tree2.getRoot()));

  const proofB = tree2.getProof(1);
  assert.equal(proofB.length, 1);
  assert.deepEqual(proofB[0], leafA);
  assert.ok(MerkleTree.verify(leafB, proofB, tree2.getRoot()));
});

test("7. MerkleTree: arbitrary leaf counts (3, 7, 16, 33) & tamper detection", () => {
  const testCounts = [3, 7, 16, 33];

  for (const count of testCounts) {
    const leaves = Array.from({ length: count }, () => randomBytes32());
    const tree = new MerkleTree(leaves);
    const root = tree.getRoot();

    // Verify proof for every single leaf
    for (let i = 0; i < count; i++) {
      const proof = tree.getProof(i);
      assert.ok(
        MerkleTree.verify(leaves[i], proof, root),
        `Proof for leaf ${i} in tree of size ${count} must verify`
      );

      // Tampered leaf must fail
      const tamperedLeaf = new Uint8Array(leaves[i]);
      tamperedLeaf[0] ^= 0x01;
      assert.strictEqual(
        MerkleTree.verify(tamperedLeaf, proof, root),
        false,
        "Tampered leaf must fail verification"
      );

      // Tampered proof element must fail
      if (proof.length > 0) {
        const tamperedProof = proof.map((p) => new Uint8Array(p));
        tamperedProof[0][0] ^= 0x01;
        assert.strictEqual(
          MerkleTree.verify(leaves[i], tamperedProof, root),
          false,
          "Tampered proof must fail verification"
        );
      }
    }
  }
});

// =========================================================================
// 3. Cross-Chain Bridge Batcher
// =========================================================================

test("8. CrossChainBridgeBatcher: item queueing and batch accumulation", () => {
  const batcher = new CrossChainBridgeBatcher({ defaultSourceChain: "seraph_evm" });
  assert.equal(batcher.pendingCount, 0);

  const item1 = {
    nullifier: randomBytes32(),
    recipient: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    amount: 100n * 10n ** 18n,
    destChainId: "xmr_evm",
  };
  const item2 = {
    nullifier: randomBytes32(),
    recipient: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
    amount: 250n * 10n ** 18n,
    destChainId: "xmr_evm",
  };

  batcher.enqueue(item1);
  batcher.enqueue(item2);
  assert.equal(batcher.pendingCount, 2);

  // Build batch
  const batch = batcher.buildBatch();
  assert.equal(batch.batchId, 0);
  assert.equal(batch.items.length, 2);
  assert.equal(batcher.pendingCount, 0, "Queue must be empty after batch creation");
  assert.ok(batch.merkleRoot.startsWith("0x"));
  assert.ok(batch.stateDataHash.startsWith("0x"));
  assert.equal(batch.proofs.length, 2);

  // Retrieve batch
  const retrieved = batcher.getBatch(0);
  assert.deepEqual(retrieved, batch);

  // Attempting to build batch from empty queue throws
  assert.throws(() => batcher.buildBatch(), /pending queue is empty/);
});

test("9. CrossChainBridgeBatcher: event log ingestion from TokensLocked logs", () => {
  const batcher = new CrossChainBridgeBatcher();
  const bridgeAddr = "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF";

  const sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
  const recipient = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const amount = 420n * 10n ** 18n;
  const destChainHex = "xmr_evm".padEnd(64, "0");

  const mockLog = {
    address: bridgeAddr,
    topics: [
      EVENT_TOPICS.TokensLocked,
      "0x" + (1n).toString(16).padStart(64, "0"), // nonce = 1
      "0x" + cleanHex(sender).padStart(64, "0"),
      "0x" + cleanHex(recipient).padStart(64, "0"),
    ],
    data: "0x" + amount.toString(16).padStart(64, "0") + destChainHex,
    transactionHash: "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
    logIndex: 0,
  };

  const ingested = batcher.ingestLog(mockLog);
  assert.ok(ingested, "Log must be ingested");
  assert.equal(ingested.recipient.toLowerCase(), recipient.toLowerCase());
  assert.equal(ingested.amount, amount);
  assert.equal(batcher.pendingCount, 1);
});

test("10. CrossChainBridgeBatcher: claim proof generation, calldata encoding & verification", () => {
  const batcher = new CrossChainBridgeBatcher();
  const null1 = randomBytes32();
  const null2 = randomBytes32();
  const recip1 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const recip2 = "0x90F79bf6EB2c4f870365E785982E1f101E93b906";
  const amt1 = 1250n * 10n ** 18n;
  const amt2 = 2750n * 10n ** 18n;

  batcher.enqueue({ nullifier: null1, recipient: recip1, amount: amt1, destChainId: "seraph_evm" });
  batcher.enqueue({ nullifier: null2, recipient: recip2, amount: amt2, destChainId: "seraph_evm" });

  const batch = batcher.buildBatch({ sourceChainId: "xmr_evm" });

  // Get proof by nullifier
  const claim1 = batcher.getClaimProof(batch.batchId, { nullifier: null1 });
  assert.equal(claim1.recipient.toLowerCase(), recip1.toLowerCase());
  assert.equal(claim1.amount, amt1);
  assert.equal(claim1.merkleProof.length, 1);
  assert.ok(claim1.calldata.startsWith(SELECTORS.claimBridged));

  // Verify claim proof
  const isValid = batcher.verifyClaimProof(claim1);
  assert.ok(isValid, "Generated claim proof must pass verification");

  // Tampering with claim amount fails verification
  const tamperedClaim = { ...claim1, amount: amt1 + 1n };
  assert.strictEqual(batcher.verifyClaimProof(tamperedClaim), false, "Tampered claim amount must fail verification");

  // Get proof by index
  const claim2 = batcher.getClaimProof(batch.batchId, { index: 1 });
  assert.equal(claim2.recipient.toLowerCase(), recip2.toLowerCase());
  assert.ok(batcher.verifyClaimProof(claim2));
});

// =========================================================================
// 4. Gas Abstraction Dispatcher
// =========================================================================

test("11. GasAbstractionDispatcher: solvency check and successful voucher execution", async () => {
  const mockProvider = new MockEVMProvider();
  const feeToken = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const gasRelayerAddr = "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394";

  // Pre-fund voucher pool with 10 tokens
  mockProvider.setVoucherPoolBalance(feeToken, 10n * 10n ** 18n);

  const dispatcher = new GasAbstractionDispatcher({
    gasRelayerAddress: gasRelayerAddr,
    provider: mockProvider,
    minFeeThreshold: 10n ** 16n, // 0.01 token min fee
  });

  const nullifier = randomBytes32();
  const feeAmt = 5n * 10n ** 17n; // 0.5 token
  const target = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const callData = Buffer.from("test_payload");

  // Solvency validation
  const validation = await dispatcher.validateRequest({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: feeAmt,
    target,
    callData,
  });
  assert.ok(validation.isValid);

  // Dispatch execution
  const record = await dispatcher.dispatch({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: feeAmt,
    target,
    callData,
  });

  assert.equal(record.status, 1);
  assert.equal(record.feeAmount, feeAmt);
  assert.ok(dispatcher.isVoucherUsed(nullifier));

  // Check earnings
  const earnings = dispatcher.getRelayerEarnings();
  assert.equal(earnings[feeToken.toLowerCase()], feeAmt);

  // Check remaining pool balance in provider
  const remainingPool = mockProvider.getVoucherPoolBalance(feeToken);
  assert.equal(remainingPool, 10n * 10n ** 18n - feeAmt);
});

test("12. GasAbstractionDispatcher: error handling (insufficient pool, used nullifier, forbidden target, fee threshold)", async () => {
  const mockProvider = new MockEVMProvider();
  const feeToken = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const gasRelayerAddr = "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394";

  // Set pool to only 1 token
  mockProvider.setVoucherPoolBalance(feeToken, 1n * 10n ** 18n);

  const dispatcher = new GasAbstractionDispatcher({
    gasRelayerAddress: gasRelayerAddr,
    provider: mockProvider,
    minFeeThreshold: 10n ** 17n, // 0.1 token
  });

  const nullifier = randomBytes32();
  const target = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

  // 1. Fee below threshold
  const lowFeeRes = await dispatcher.validateRequest({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: 10n ** 15n, // 0.001 token < 0.1 token threshold
    target,
    callData: "0x",
  });
  assert.strictEqual(lowFeeRes.isValid, false);
  assert.equal(lowFeeRes.errorCode, "FEE_BELOW_THRESHOLD");

  // 2. Insufficient pool balance (requesting 5 tokens when pool has 1)
  const insolventRes = await dispatcher.validateRequest({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: 5n * 10n ** 18n,
    target,
    callData: "0x",
  });
  assert.strictEqual(insolventRes.isValid, false);
  assert.equal(insolventRes.errorCode, "INSUFFICIENT_VOUCHER_POOL");

  // 3. Forbidden target: GasRelayer itself
  const relayerTargetRes = await dispatcher.validateRequest({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: 5n * 10n ** 17n,
    target: gasRelayerAddr,
    callData: "0x",
  });
  assert.strictEqual(relayerTargetRes.isValid, false);
  assert.equal(relayerTargetRes.errorCode, "FORBIDDEN_TARGET");

  // 4. Forbidden target: Fee token contract itself (drain exploit)
  const tokenTargetRes = await dispatcher.validateRequest({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: 5n * 10n ** 17n,
    target: feeToken,
    callData: "0x",
  });
  assert.strictEqual(tokenTargetRes.isValid, false);
  assert.equal(tokenTargetRes.errorCode, "FORBIDDEN_TARGET");

  // 5. Successful dispatch, then attempted double-spend
  await dispatcher.dispatch({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: 5n * 10n ** 17n,
    target,
    callData: "0x",
  });

  const reuseRes = await dispatcher.validateRequest({
    voucherNullifier: nullifier,
    feeToken,
    feeAmount: 1n * 10n ** 17n,
    target,
    callData: "0x",
  });
  assert.strictEqual(reuseRes.isValid, false);
  assert.equal(reuseRes.errorCode, "VOUCHER_ALREADY_USED");

  await assert.rejects(
    () =>
      dispatcher.dispatch({
        voucherNullifier: nullifier,
        feeToken,
        feeAmount: 1n * 10n ** 17n,
        target,
        callData: "0x",
      }),
    /VOUCHER_ALREADY_USED/
  );
});

// =========================================================================
// 5. Relayer Bond Verification & Enforcement
// =========================================================================

test("13. SeraphRelayerDaemon: bond verification rejects unbonded relayer", async () => {
  const mockProvider = new MockEVMProvider();
  const bridgeAddr = "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF";
  const gasRelayerAddr = "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394";
  const relayerAddr = "0x2222222222222222222222222222222222222222";

  // Initial bond is 0 (below 1 ETH minimum)
  mockProvider.setRelayerBond(relayerAddr, 0n);

  const daemon = new SeraphRelayerDaemon(
    {
      bridgeAddress: bridgeAddr,
      gasRelayerAddress: gasRelayerAddr,
      relayerAddress: relayerAddr,
      minRelayerBond: 10n ** 18n,
    },
    mockProvider
  );

  // Ingest an item
  daemon.ingestBridgeOut({
    nullifier: randomBytes32(),
    recipient: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    amount: 100n * 10n ** 18n,
    destChainId: "xmr_evm",
  });

  // Submitting batch without bond must throw InsufficientRelayerBondError
  await assert.rejects(
    () => daemon.submitPendingBatch(),
    (err) => err instanceof InsufficientRelayerBondError && err.bondedAmount === 0n
  );

  // Now bond relayer with 2 ETH
  await daemon.depositBond(2n * 10n ** 18n);

  const bondStatus = await daemon.checkRelayerBond();
  assert.ok(bondStatus.isSufficient);
  assert.equal(bondStatus.bondedAmount, 2n * 10n ** 18n);

  // Now submitting batch must succeed
  const result = await daemon.submitPendingBatch();
  assert.equal(result.batchId, 0);
  assert.equal(result.itemCount, 1);
});

// =========================================================================
// 6. SeraphRelayerDaemon End-to-End Daemon Lifecycle & Orchestration
// =========================================================================

test("14. SeraphRelayerDaemon: complete end-to-end multi-tenant lifecycle", async () => {
  const mockProvider = new MockEVMProvider();
  const bridgeAddr = "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF";
  const gasRelayerAddr = "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394";
  const feeTokenSer = "0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F";
  const feeTokenXmr = "0x8009C1e2CB2342910C4985a76DdDC2b0Ab81935A";
  const relayerAddr = "0x4444444444444444444444444444444444444444";

  // Pre-configure bonds and voucher pool balances
  mockProvider.setRelayerBond(relayerAddr, 5n * 10n ** 18n);
  mockProvider.setVoucherPoolBalance(feeTokenSer, 100n * 10n ** 18n);
  mockProvider.setVoucherPoolBalance(feeTokenXmr, 20n * 10n ** 18n);

  const daemon = new SeraphRelayerDaemon(
    {
      bridgeAddress: bridgeAddr,
      gasRelayerAddress: gasRelayerAddr,
      relayerAddress: relayerAddr,
      batchIntervalMs: 50, // fast timer for testing
      maxBatchSize: 10,
    },
    mockProvider
  );

  let startedEventFired = false;
  let batchEventFired = false;
  let voucherEventFired = false;

  daemon.on("started", () => {
    startedEventFired = true;
  });
  daemon.on("batchSubmitted", () => {
    batchEventFired = true;
  });
  daemon.on("voucherDispatched", () => {
    voucherEventFired = true;
  });

  // 1. Start daemon
  await daemon.start();
  assert.ok(startedEventFired);

  // 2. Ingest 3 bridge items
  const null1 = randomBytes32();
  const null2 = randomBytes32();
  const null3 = randomBytes32();

  daemon.ingestBridgeOutBatch([
    { nullifier: null1, recipient: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", amount: 100n * 10n ** 18n, destChainId: "xmr_evm" },
    { nullifier: null2, recipient: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", amount: 200n * 10n ** 18n, destChainId: "xmr_evm" },
    { nullifier: null3, recipient: "0x90F79bf6EB2c4f870365E785982E1f101E93b906", amount: 300n * 10n ** 18n, destChainId: "xmr_evm" },
  ]);

  // Wait for batch interval flush or manually flush
  const batchResult = await daemon.submitPendingBatch();
  assert.equal(batchResult.itemCount, 3);
  assert.ok(batchEventFired);

  // Query proof for claim on destination chain
  const claimProof = daemon.getProofForClaim(batchResult.batchId, { nullifier: null2 });
  assert.equal(claimProof.recipient.toLowerCase(), "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC".toLowerCase());
  assert.ok(daemon.bridgeBatcher.verifyClaimProof(claimProof));

  // 3. Dispatch Gas Vouchers across SER and wXMR
  const serVoucherNull = randomBytes32();
  const xmrVoucherNull = randomBytes32();

  await daemon.dispatchGasVoucher({
    voucherNullifier: serVoucherNull,
    feeToken: feeTokenSer,
    feeAmount: 2n * 10n ** 18n, // 2 SER
    target: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    callData: Buffer.from("broadcast_encrypted_invoice"),
  });

  await daemon.dispatchGasVoucher({
    voucherNullifier: xmrVoucherNull,
    feeToken: feeTokenXmr,
    feeAmount: 5n * 10n ** 17n, // 0.5 wXMR
    target: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    callData: Buffer.from("settle_stealth_invoice"),
  });

  assert.ok(voucherEventFired);

  // 4. Verify Daemon Status metrics
  const status = await daemon.status();
  assert.equal(status.isRunning, true);
  assert.equal(status.totalBatchesSubmitted, 1);
  assert.equal(status.totalVouchersExecuted, 2);
  assert.equal(status.pendingBridgeItems, 0);
  assert.equal(status.isBondSufficient, true);
  assert.equal(status.totalFeesEarned[feeTokenSer.toLowerCase()], 2n * 10n ** 18n);
  assert.equal(status.totalFeesEarned[feeTokenXmr.toLowerCase()], 5n * 10n ** 17n);

  // 5. Stop daemon
  daemon.stop();
  const stoppedStatus = await daemon.status();
  assert.equal(stoppedStatus.isRunning, false);
});

// =========================================================================
// 7. Advanced Batching, Polling, & Configuration
// =========================================================================

test("15. SeraphRelayerDaemon: high-volume queue chunking across multiple batches", async () => {
  const mockProvider = new MockEVMProvider();
  const bridgeAddr = "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF";
  const gasRelayerAddr = "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394";
  const relayerAddr = "0x5555555555555555555555555555555555555555";

  mockProvider.setRelayerBond(relayerAddr, 10n * 10n ** 18n);

  const maxBatchSize = 8;
  const daemon = new SeraphRelayerDaemon(
    {
      bridgeAddress: bridgeAddr,
      gasRelayerAddress: gasRelayerAddr,
      relayerAddress: relayerAddr,
      maxBatchSize,
    },
    mockProvider
  );

  // Enqueue 25 items
  const totalItems = 25;
  const items = Array.from({ length: totalItems }, (_, i) => ({
    nullifier: randomBytes32(),
    recipient: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    amount: BigInt((i + 1) * 100) * 10n ** 18n,
    destChainId: "xmr_evm",
  }));
  daemon.ingestBridgeOutBatch(items);
  assert.equal(daemon.bridgeBatcher.pendingCount, 25);

  // Batch 1: items 0..7
  const b1 = await daemon.submitPendingBatch();
  assert.equal(b1.itemCount, 8);
  assert.equal(daemon.bridgeBatcher.pendingCount, 17);

  // Batch 2: items 8..15
  const b2 = await daemon.submitPendingBatch();
  assert.equal(b2.itemCount, 8);
  assert.equal(daemon.bridgeBatcher.pendingCount, 9);

  // Batch 3: items 16..23
  const b3 = await daemon.submitPendingBatch();
  assert.equal(b3.itemCount, 8);
  assert.equal(daemon.bridgeBatcher.pendingCount, 1);

  // Batch 4: item 24 (last item)
  const b4 = await daemon.submitPendingBatch();
  assert.equal(b4.itemCount, 1);
  assert.equal(daemon.bridgeBatcher.pendingCount, 0);

  // All 4 batches have unique roots and IDs
  assert.notEqual(b1.merkleRoot, b2.merkleRoot);
  assert.notEqual(b2.merkleRoot, b3.merkleRoot);
  assert.notEqual(b3.merkleRoot, b4.merkleRoot);

  const status = await daemon.status();
  assert.equal(status.totalBatchesSubmitted, 4);
});

test("16. CrossChainBridgeBatcher: parameter mapping variants for submitStateBatch", () => {
  const batcher = new CrossChainBridgeBatcher({ defaultSourceChain: "seraph_evm" });

  batcher.enqueue({
    nullifier: randomBytes32(),
    recipient: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    amount: 100n * 10n ** 18n,
    destChainId: "xmr_evm",
  });

  const batch = batcher.buildBatch();

  // Mode 1: sourceChainId + merkleRoot
  const sub1 = batcher.encodeBatchSubmission(batch.batchId, "sourceChainAndRoot");
  assert.ok(sub1.data.startsWith(SELECTORS.submitStateBatch));
  assert.equal(sub1.data.length, 2 + 8 + 64 * 2); // 0x + 4 bytes selector + 2 words = 138 chars

  // Mode 2: merkleRoot + stateDataHash
  const sub2 = batcher.encodeBatchSubmission(batch.batchId, "rootAndDataHash");
  assert.ok(sub2.data.startsWith(SELECTORS.submitStateBatch));
  assert.equal(sub2.data.length, 2 + 8 + 64 * 2);
  assert.notEqual(sub1.data, sub2.data);
});

test("17. SeraphRelayerDaemon: pollBridgeLogs fetches and queues emitted events", async () => {
  const mockProvider = new MockEVMProvider();
  const bridgeAddr = "0x10f135b8004fB99eec3d7e7E4f652b477A14b0bF";
  const gasRelayerAddr = "0x8b5F2A84c7E1a37c0245a4944c6691c94488b394";
  const relayerAddr = "0x6666666666666666666666666666666666666666";

  mockProvider.setRelayerBond(relayerAddr, 2n * 10n ** 18n);

  const daemon = new SeraphRelayerDaemon(
    {
      bridgeAddress: bridgeAddr,
      gasRelayerAddress: gasRelayerAddr,
      relayerAddress: relayerAddr,
    },
    mockProvider
  );

  // Simulate on-chain block advance and event emission
  mockProvider.blockNumber = 1005n;

  const mockLog = {
    address: bridgeAddr,
    topics: [
      EVENT_TOPICS.TokensLocked,
      "0x" + (99n).toString(16).padStart(64, "0"),
      "0x" + cleanHex("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266").padStart(64, "0"),
      "0x" + cleanHex("0x70997970C51812dc3A010C7d01b50e0d17dc79C8").padStart(64, "0"),
    ],
    data: "0x" + (500n * 10n ** 18n).toString(16).padStart(64, "0") + "xmr_evm".padEnd(64, "0"),
    blockNumber: 1005n,
    transactionHash: "0x1234567890123456789012345678901234567890123456789012345678901234",
    logIndex: 0,
  };

  mockProvider.addLog(mockLog);

  // Poll logs
  const ingested = await daemon.pollBridgeLogs();
  assert.equal(ingested.length, 1);
  assert.equal(daemon.bridgeBatcher.pendingCount, 1);
  assert.equal(ingested[0].amount, 500n * 10n ** 18n);
});


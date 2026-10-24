import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { stripTypeScriptTypes } from "node:module";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SDK_TS_PATH = path.resolve(__dirname, "../src/index.ts");

async function loadSdk() {
  const rawTs = fs.readFileSync(SDK_TS_PATH, "utf8");
  const enumTransformed = rawTs.replace(
    /export enum (\w+)\s*\{([^}]+)\}/g,
    (_, name, body) => `export const ${name} = Object.freeze({${body.replace(/=/g, ":")}});`
  );
  const jsCode = stripTypeScriptTypes(enumTransformed);
  const dataUrl = "data:text/javascript;base64," + Buffer.from(jsCode, "utf8").toString("base64");
  return import(dataUrl);
}

test("scanNotesForOwner: recovers spendable balance, asset, and private memos using incomingViewKey", async () => {
  const sdk = await loadSdk();
  const aliceSpendKey = sdk.randomBytes32();
  const aliceKeys = sdk.deriveWalletKeys(aliceSpendKey);

  const bobSpendKey = sdk.randomBytes32();
  const bobKeys = sdk.deriveWalletKeys(bobSpendKey);

  // Generate 2 notes for Alice and 1 note for Bob
  const note1Blinding = sdk.randomBytes32();
  const note1Memo = sdk.encodeNoteMemo(100000000n, sdk.AssetId.Seraph, "Payment for private compute batch #1");
  const encMemo1 = sdk.xorViewKeyMemo(aliceKeys.viewKey, note1Blinding, note1Memo);

  const note2Blinding = sdk.randomBytes32();
  const note2Memo = sdk.encodeNoteMemo(50000000n, sdk.AssetId.Xmr, "Salary bonus");
  const encMemo2 = sdk.xorViewKeyMemo(aliceKeys.viewKey, note2Blinding, note2Memo);

  const bobBlinding = sdk.randomBytes32();
  const bobMemo = sdk.encodeNoteMemo(10000000n, sdk.AssetId.Seraph, "Bob private funds");
  const encMemoBob = sdk.xorViewKeyMemo(bobKeys.viewKey, bobBlinding, bobMemo);

  const allNotes = [
    { leafIndex: 0, commitment: "0x1111", blinding: note1Blinding, encryptedMemo: encMemo1 },
    { leafIndex: 1, commitment: "0x2222", blinding: note2Blinding, encryptedMemo: encMemo2 },
    { leafIndex: 2, commitment: "0x3333", blinding: bobBlinding, encryptedMemo: encMemoBob },
  ];

  // Alice scans
  const aliceNotes = sdk.scanNotesForOwner(allNotes, aliceKeys.viewKey);
  assert.equal(aliceNotes.length, 2);
  assert.equal(aliceNotes[0].amount, 100000000n);
  assert.equal(aliceNotes[0].asset, sdk.AssetId.Seraph);
  assert.equal(aliceNotes[0].memo, "Payment for private compute batch #1");

  assert.equal(aliceNotes[1].amount, 50000000n);
  assert.equal(aliceNotes[1].asset, sdk.AssetId.Xmr);
  assert.equal(aliceNotes[1].memo, "Salary bonus");

  // Bob scans
  const bobNotes = sdk.scanNotesForOwner(allNotes, bobKeys.viewKey);
  assert.equal(bobNotes.length, 1);
  assert.equal(bobNotes[0].amount, 10000000n);
  assert.equal(bobNotes[0].memo, "Bob private funds");
});

test("generateComplianceDisclosure: creates verifiable signed disclosure package for accounting/tax audits", async () => {
  const sdk = await loadSdk();
  const outgoingViewKey = sdk.randomBytes32();
  const spentRecords = [
    {
      nullifier: "0xdeadbeef1111",
      amount: 150000000000000000000n, // 150 SER
      recipient: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
      timestamp: 1729740000,
      txHash: "0xabcdef123456",
    },
    {
      nullifier: "0xdeadbeef2222",
      amount: 50000000000000000000n, // 50 SER
      recipient: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
      timestamp: 1729743600,
    },
  ];

  const disclosure = sdk.generateComplianceDisclosure(spentRecords, outgoingViewKey);
  assert.equal(disclosure.itemCount, 2);
  assert.equal(disclosure.totalUnshielded, 200000000000000000000n);
  assert.ok(disclosure.signatureTag.startsWith("0x"));
  assert.equal(disclosure.signatureTag.length, 66); // 32 bytes hex + 0x

  const parsed = JSON.parse(disclosure.disclosureSummary);
  assert.equal(parsed.protocol, "Seraph Protocol");
  assert.equal(parsed.totalUnshielded, "200000000000000000000");
  assert.equal(parsed.records.length, 2);
});

test("UsageVaultClient & createCreditDeposit: derives commitment and ticket nullifier for autonomous AI agent billing", async () => {
  const sdk = await loadSdk();
  const secretPreimage = sdk.randomBytes32();
  const amount = 5000000000000000000n; // 5 SER

  const ticket = sdk.createCreditDeposit(amount, secretPreimage);
  assert.equal(ticket.commitment.length, 32);
  assert.equal(ticket.ticketNullifier.length, 32);

  const client = new sdk.UsageVaultClient("0x8080808080808080808080808080808080808080");
  const enc = client.encodeDeposit(ticket.commitment, amount);
  assert.equal(enc.to, "0x8080808080808080808080808080808080808080");
  assert.ok(enc.data.startsWith("0xd211e4f4"));
});

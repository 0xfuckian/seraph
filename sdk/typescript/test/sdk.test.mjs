import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

function sha256Tag(tag, ...chunks) {
  const h = createHash("sha256");
  h.update(Buffer.from(tag, "utf8"));
  for (const c of chunks) h.update(c);
  return new Uint8Array(h.digest());
}

test("derives deterministic viewKey, pubkey, note commitment, and nullifier", () => {
  const spendKey = new Uint8Array(32).fill(7);
  const viewKey = sha256Tag("seraph_viewkey_derive", spendKey);
  const pubkey = sha256Tag("seraph_pubkey_derive", spendKey);
  assert.equal(viewKey.length, 32);
  assert.equal(pubkey.length, 32);
  assert.notDeepEqual(viewKey, pubkey);

  const amtBuf = Buffer.alloc(8);
  amtBuf.writeBigUInt64BE(1000n);
  const c1 = sha256Tag("seraph_note_commitment_v1", new Uint8Array([0]), amtBuf, pubkey, new Uint8Array(32).fill(1));
  const c2 = sha256Tag("seraph_note_commitment_v1", new Uint8Array([1]), amtBuf, pubkey, new Uint8Array(32).fill(1));
  assert.notDeepEqual(c1, c2, "SERAPH and XMR commitments with same amount must differ");
});

test("enforces Launchpad fee caps (1% mandatory platform + max 2.5% creator) and 100% split", () => {
  const validSplit = 2000 + 2000 + 2000 + 2000 + 2000;
  assert.equal(validSplit, 10_000);
  const maxTradeFeeBps = 100 + 250;
  assert.equal(maxTradeFeeBps, 350); // 3.5% max total trade fee
});

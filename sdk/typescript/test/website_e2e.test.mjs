import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HTML_PATH = path.resolve(__dirname, "../../../website/index.html");
const RPC_URL = "https://sepolia.base.org";
const LAUNCHPAD_ADDRESS = "0xe0349E4cC431329207e98C5205062776e058A846";

test("website/index.html contains all Launchpad DOM IDs, chips, presets, and syntax-valid scripts", () => {
  const html = fs.readFileSync(HTML_PATH, "utf8");

  const requiredIds = [
    "view-launch",
    "lpStatus",
    "lpNetwork",
    "lpRows",
    "lpEmpty",
    "lpPreviewNote",
    "lpTradeBar",
    "lpTradeTitle",
    "lpTradeToken",
    "lpTradeReserve",
    "lpTradeGrad",
    "lpTradeFees",
    "lpTradeAmt",
    "lpBuyBtn",
    "lpSellBtn",
    "lpClaimFeesBtn",
    "lpClaimDivsBtn",
    "lpTradeStatus",
    "lpName",
    "lpTicker",
    "lpDesc",
    "lpDescCount",
    "lpWebsite",
    "lpTwitter",
    "lpTelegram",
    "lpChainChips",
    "lpModelChips",
    "lpModelNote",
    "lpSupply",
    "lpFeeWallet",
    "lpPresets",
    "lpBuyRange",
    "lpSellRange",
    "lpBuyOut",
    "lpSellOut",
    "lpCustom",
    "lpTotal",
    "lpDevChips",
    "lpAck",
    "lpLaunchBtn",
    "lpLaunchStatus",
    "lpPvImg",
    "lpPvTick",
    "lpPvSym",
    "lpPvName",
    "lpPvNet",
    "lpPvTax",
    "lpPvTotal",
    "lpPvSplit",
    "lpPvDev"
  ];

  for (const id of requiredIds) {
    assert.match(html, new RegExp(`id="${id}"`), `Missing DOM element id="${id}"`);
  }

  for (const preset of ["creator", "dividends", "buyback", "liquidity", "platform", "custom"]) {
    assert.match(html, new RegExp(`data-preset="${preset}"`), `Missing preset button data-preset="${preset}"`);
  }
  for (const status of ["trending", "new", "near", "graduated"]) {
    assert.match(html, new RegExp(`data-status="${status}"`), `Missing status chip data-status="${status}"`);
  }
  for (const model of ["fixed", "curve", "seraph"]) {
    assert.match(html, new RegExp(`data-model="${model}"`), `Missing model chip data-model="${model}"`);
  }

  assert.ok(html.includes(LAUNCHPAD_ADDRESS), "Missing Base Sepolia SeraphLaunchpad address");
  assert.ok(html.includes(RPC_URL), "Missing Base Sepolia RPC endpoint");

  // Extract inline classic <script> blocks and verify zero JS syntax errors
  const scriptRegex = /<script(?![^>]*\bsrc=)(?![^>]*\btype=["'](?:module|importmap)["'])[^>]*>([\s\S]*?)<\/script>/gi;
  let match;
  let scriptCount = 0;
  while ((match = scriptRegex.exec(html)) !== null) {
    scriptCount++;
    assert.doesNotThrow(() => new vm.Script(match[1]), `Syntax error in inline script #${scriptCount}`);
  }
  assert.ok(scriptCount >= 1, "Expected at least one inline classic script");
});

test("live Base Sepolia JSON-RPC decodes SeraphLaunchpad launches ($SALPHA, $SPRIV, etc.) for #lpRows", async () => {
  async function lpEthCall(to, data) {
    const res = await fetch(RPC_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_call",
        params: [{ to, data }, "latest"]
      })
    });
    const j = await res.json();
    assert.ok(!j.error, `RPC error: ${j.error?.message}`);
    return j.result;
  }

  const lpEncUint = (n) => BigInt(n).toString(16).padStart(64, "0");
  const lpEncAddr = (a) => String(a || "").replace(/^0x/i, "").toLowerCase().padStart(64, "0");
  const lpDecStr = (hex) => {
    const raw = hex.slice(2);
    const len = parseInt(raw.slice(64, 128), 16) * 2;
    const bytes = [];
    for (let i = 128; i < 128 + len && i < raw.length; i += 2) {
      bytes.push(parseInt(raw.slice(i, i + 2), 16));
    }
    return new TextDecoder().decode(new Uint8Array(bytes));
  };

  const totalHex = await lpEthCall(LAUNCHPAD_ADDRESS, "0x0e883f8b");
  const total = Number(BigInt(totalHex));
  assert.ok(total >= 1, `Expected at least 1 live launch on Base Sepolia, got ${total}`);

  const decodedRows = [];
  for (let i = 0; i < total; i++) {
    const tokHex = await lpEthCall(LAUNCHPAD_ADDRESS, "0x634282af" + lpEncUint(i));
    const tok = "0x" + tokHex.slice(-40);
    const [infoHex, nameHex, symHex] = await Promise.all([
      lpEthCall(LAUNCHPAD_ADDRESS, "0xb3964f23" + lpEncAddr(tok)),
      lpEthCall(tok, "0x06fdde03"),
      lpEthCall(tok, "0x95d89b41")
    ]);
    const w = infoHex.slice(2).match(/.{64}/g).map((x) => BigInt("0x" + x));
    assert.equal(w.length, 20, "LaunchInfo struct must have 20 static words");

    const name = lpDecStr(nameHex);
    const sym = lpDecStr(symHex);
    const graduated = w[4] !== 0n;
    const realQuote = w[15];
    const gradThreshold = w[19];
    const prog = (graduated || gradThreshold === 0n)
      ? 100
      : Math.min(100, Number((realQuote * 10000n) / gradThreshold) / 100);

    decodedRows.push({
      token: tok,
      name,
      sym,
      model: Number(w[3]),
      graduated,
      buyFeeBps: Number(w[5]),
      sellFeeBps: Number(w[6]),
      prog
    });
  }

  const symbols = decodedRows.map((r) => r.sym);
  assert.ok(symbols.includes("SALPHA"), `Expected $SALPHA in live launches, found: ${symbols.join(", ")}`);
  for (const row of decodedRows) {
    assert.match(row.token, /^0x[0-9a-f]{40}$/);
    assert.ok(row.name.length > 0 && row.name.length <= 32);
    assert.ok(row.sym.length > 0 && row.sym.length <= 10);
    assert.ok(row.buyFeeBps <= 250 && row.sellFeeBps <= 250);
    assert.ok(row.prog >= 0 && row.prog <= 100);
  }

  // Also verify ABI encoding of launch(LaunchParams) simulates cleanly against Base Sepolia
  const lpEncStr = (s) => {
    const bytes = new TextEncoder().encode(s || "");
    let hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
    if (hex.length % 64 !== 0) hex = hex.padEnd(Math.ceil(hex.length / 64) * 64, "0");
    return lpEncUint(bytes.length) + hex;
  };
  const strs = ["E2E Token", "E2E", "Automated E2E test", "", "https://seraphprotocol.tech", "@seraph", "@seraph"].map(lpEncStr);
  let offset = 18 * 32;
  const heads = strs.map((sb) => {
    const o = lpEncUint(offset);
    offset += sb.length / 2;
    return o;
  });
  heads.push(
    lpEncUint(1),
    lpEncUint(1000000000n * 10n ** 18n),
    lpEncAddr("0x1111111111111111111111111111111111111111"),
    lpEncUint(200),
    lpEncUint(200),
    lpEncUint(5000),
    lpEncUint(2000),
    lpEncUint(2000),
    lpEncUint(1000),
    lpEncUint(0),
    lpEncUint(0)
  );
  const launchCalldata = "0xf12b0b68" + lpEncUint(32) + heads.join("") + strs.join("");
  const simRes = await fetch(RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "eth_call",
      params: [{
        from: "0x1111111111111111111111111111111111111111",
        to: LAUNCHPAD_ADDRESS,
        value: "0x" + (500000000000000n).toString(16),
        data: launchCalldata
      }, "latest"]
    })
  });
  const simJson = await simRes.json();
  assert.ok(!simJson.error, `Simulated launch() reverted: ${simJson.error?.message}`);
  assert.match(simJson.result, /^0x0{24}[0-9a-f]{40}$/i, "Simulated launch() must return deployed token address");
});

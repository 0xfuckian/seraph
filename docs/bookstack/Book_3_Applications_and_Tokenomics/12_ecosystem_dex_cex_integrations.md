# Chapter 12: Ecosystem, DEX & CEX Integrations

## 12.1 Overview: Integrating Privacy with Global Liquidity

Decentralized finance (DeFi) liquidity and centralized exchange (CEX) listings require standard, predictable ERC-20 token interactions. However, protocols featuring transfer taxes or non-standard balance logic frequently experience routing failures, slippage mismatches, or unexpected fees during multi-hop DEX swaps.

Seraph solves this through a dedicated **Tax Exemption Registry** and standardized integration interfaces designed specifically for automated market makers (AMMs) and institutional custodians.

---

## 12.2 Decentralized Exchanges (Uniswap v3 & Aerodrome)

### The Multi-Hop Double-Tax Problem
On a standard DEX, a swap from SER to USDC often routes through an intermediary pool:
$$\text{User} \xrightarrow{\text{Swap}} \text{Pool}_{\text{SER/WETH}} \xrightarrow{\text{Internal Transfer}} \text{Router} \xrightarrow{\text{Swap}} \text{Pool}_{\text{WETH/USDC}} \xrightarrow{} \text{User}$$
If a 1.00% sell tax is assessed on every hop, the user would be taxed twice (or the DEX router would fail due to received amount mismatches).

### The Tax Exemption Mapping (`taxExempt`)
To ensure seamless integration with Uniswap v3, Aerodrome, Curve, and Balancer, `SERAPH.sol` includes a dynamic exemption mapping:

```solidity
// contracts/core/SERAPH.sol
mapping(address => bool) public taxExempt;
event TaxExemptionUpdated(address indexed account, bool isExempt);

function setTaxExempt(address account, bool isExempt) external onlyTreasury {
    taxExempt[account] = isExempt;
    emit TaxExemptionUpdated(account, isExempt);
}
```

In the internal `_update` transfer hook:
```solidity
bool isSell = from != address(0) && to != address(0) && from != address(this) && to != address(this)
    && from != presale && to != presale && from != treasury && to != treasury
    && from != privacyPool && to != privacyPool
    && !taxExempt[from] && !taxExempt[to];
```

### Whitelisting DEX Contracts:
1. When a new Uniswap v3 pool or Aerodrome gauge is deployed, the Seraph Treasury (governed by the Protocol DAO) invokes:
   ```solidity
   seraphToken.setTaxExempt(uniswapV3PoolAddress, true);
   seraphToken.setTaxExempt(universalRouterAddress, true);
   ```
2. Once whitelisted, transfers between the router, pools, and liquidity providers execute with **0% tax**.
3. Sells initiated by end users on public markets continue to contribute to the deflationary burn and protocol treasury.

---

## 12.3 Centralized Exchanges (CEX) Custody & Operations

Centralized exchanges (such as Coinbase, Binance, OKX, and Kraken) utilize hot-and-cold wallet architectures where funds are swept internally between omnibus deposit addresses, cold storage vaults, and hot withdrawal wallets.

### Custody Whitelisting Workflow:
1. Prior to listing, the exchange provides their omnibus hot/cold wallet addresses to the Seraph Treasury.
2. The Treasury adds these custody addresses to `taxExempt`:
   ```solidity
   seraphToken.setTaxExempt(cexOmnibusWallet, true);
   ```
3. **Benefits**:
   - Internal exchange balance sweeps incur **0% tax**.
   - User deposits and withdrawals match exact balances to the single wei.
   - Zero reconciliation discrepancy for exchange accounting databases.

---

## 12.4 Autonomous AI Agent Payment SDK Integration

Autonomous AI agents transacting across decentralized networks can integrate `@seraph-protocol/sdk` with zero external dependencies:

```typescript
import {
  deriveWalletKeys,
  computeNoteCommitment,
  UsageVaultClient,
  createCreditDeposit,
  AssetId,
} from "@seraph-protocol/sdk";

// Initialize autonomous agent wallet
const agentSpendKey = Buffer.from(process.env.AGENT_SPEND_KEY!, "hex");
const keys = deriveWalletKeys(agentSpendKey);

// Prepare usage credit deposit for compute streaming
const computeCost = 10n * 10n**18n; // 10 SER
const secretPreimage = crypto.randomBytes(32);
const ticket = createCreditDeposit(computeCost, secretPreimage);

// Submit on-chain via client
const vaultClient = new UsageVaultClient(USAGE_VAULT_ADDRESS);
const tx = vaultClient.encodeDeposit(ticket.commitment, computeCost);
```

---

## 12.5 Standardized JSON-RPC & WebSocket Streaming

Seraph nodes expose standard JSON-RPC 2.0 endpoints for ecosystem tooling:

### Custom Privacy RPC Methods:
- `seraph_getLastRoot()`: Returns the latest Merkle root of the active commitment tree.
- `seraph_isKnownRoot(root)`: Verifies if a given 32-byte root exists within the 100-root ring buffer.
- `seraph_getNotesByRange(startLeaf, endLeaf)`: Fetches encrypted note memo payloads for client-side scanning.
- `seraph_estimateGasVoucher(feeToken, gasLimit)`: Calculates the required SER or XMR fee voucher amount for gasless execution.

### WebSocket Subscriptions:
Clients can listen to live on-chain privacy events via WebSocket:
```javascript
const ws = new WebSocket("wss://rpc.seraphprotocol.tech/ws");
ws.send(JSON.stringify({
  jsonrpc: "2.0",
  id: 1,
  method: "eth_subscribe",
  params: ["logs", { address: PRIVACY_POOL_ADDRESS }]
}));
```
This allows wallets to detect incoming payments in real time (< 1 second latency).

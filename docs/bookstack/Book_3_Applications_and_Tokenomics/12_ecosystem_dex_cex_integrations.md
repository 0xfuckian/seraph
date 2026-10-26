# Chapter 12: Ecosystem, DEX & CEX Integrations

## 12.1 Overview: Integrating Privacy with Global Liquidity

Decentralized finance (DeFi) liquidity and centralized exchange (CEX) listings require standard, predictable ERC-20 token interactions. However, protocols featuring transfer taxes or non-standard balance logic frequently experience routing failures, slippage mismatches, or unexpected fees during multi-hop DEX swaps.

Seraph solves this through a dedicated **Tax Exemption Registry** and standardized integration interfaces designed specifically for automated market makers (AMMs) and institutional custodians.

---

## 12.2 Decentralized Exchanges (Uniswap v3 & Aerodrome)

### The Multi-Hop Double-Tax Problem
On a standard DEX, a swap from SER to USDC often routes through an intermediary pool:
`User --(Swap)--> Pool_SER/WETH --(Internal Hop)--> Router --(Swap)--> Pool_WETH/USDC ----> User`

If a 1.00% sell tax were assessed on every internal transfer hop, the user would suffer double taxation, or the router transaction would fail due to received amount discrepancies.

### The Tax Exemption Mapping (`taxExempt`)
To ensure smooth integration with Uniswap v3, Aerodrome, Curve, and Balancer, `SERAPH.sol` includes a dynamic exemption mapping:

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

### Precise DEX Whitelisting Architecture:
1. **DEX Routers and Aggregators Whitelisted**:
   The DAO Treasury whitelists the DEX execution router (e.g., Uniswap Universal Router, Aerodrome Router):
   ```solidity
   seraphToken.setTaxExempt(universalRouterAddress, true);
   ```
   When the router facilitates multi-hop swaps or handles intermediary token movements, those hops are exempt, eliminating double taxation.
2. **DEX Pools (Liquidity Pairs) Kept Unexempt**:
   The AMM pool contract itself (e.g. SER/WETH pair) is **not** added to `taxExempt`. When an end user sells SER to the pool, `to = poolAddress` is unexempt, so `isSell == true`, and the protocol collects the 1.00% sell tax (0.50% burned, 0.50% to treasury).
3. **Liquidity Seeding & Rebalancing**:
   Initial liquidity provisioning and LP rebalancing executed by the DAO Treasury are naturally exempt because `treasury` is hardcoded as exempt in `_update`.
4. **Zero Tax on Privacy Pool**:
   Transfers into and out of `PrivacyPool` are hardcoded exempt (`from != privacyPool && to != privacyPool`). Shielding and unshielding tokens never incur the 1.00% sell tax.

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

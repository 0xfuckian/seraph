# Seraph Protocol — Presale Deployment & Launch Guide

This guide walks you through deploying the Seraph Protocol presale contracts to **Base mainnet** (Chain ID 8453) and bringing the Web3 presale frontend live.

---

## 1. Architecture Overview

- **`SeraphToken` (`SER`)**: Native token with 1% transfer tax (50% burn, 50% treasury) and minter role for the presale.
- **`SeraphPresale`**: 3-tier presale contract (`Strategic`, `Private`, `Public`).
  - Accepts **USDT**, **USDC**, and **ETH** (Public tier only).
  - Collects 0.5% fee to treasury.
  - Strategic: $0.02 (3.75M cap, allowlisted, 25% at TGE, 14-day cliff + 12mo vesting).
  - Private: $0.03 (11.25M cap, allowlisted, 20% at TGE, 14-day cliff + 12mo vesting).
  - Public: $0.04 (10M cap, open, 100% unlocked at TGE).
- **Presale Frontend (`website/presale-app/`)**:
  - Built with **React 19 + Vite + RainbowKit + wagmi + viem**.
  - Supports MetaMask, Coinbase Wallet, WalletConnect, Rainbow, and more.
  - Automatic network detection & switching to Base.
  - Live tier selection, stablecoin approvals, purchasing, and allocation claims.

---

## 2. Prerequisites

1. **Deployer Wallet**: An Ethereum wallet with some **ETH on Base** to cover gas fees (~0.005 ETH is usually plenty).
2. **RPC Endpoint**: A Base mainnet RPC URL (e.g., Alchemy, Infura, QuickNode, or public `https://mainnet.base.org`).
3. **Basescan API Key** (optional, for automatic verification): Get one from [basescan.org](https://basescan.org).

---

## 3. Contract Deployment (Base Mainnet)

### Step 3.1: Configure Environment Variables

Create your `.env` file from the provided template:

```bash
cp .env.example .env
```

Edit `.env` and fill in:

```env
# Your private key (without 0x prefix)
PRIVATE_KEY=your_private_key_here

# Base mainnet RPC URL
BASE_RPC_URL=https://mainnet.base.org

# TGE Timestamp (Unix timestamp in seconds when TGE can be executed)
# Example: 1735689600 (Jan 1, 2025 00:00:00 UTC)
TGE_TIMESTAMP=1735689600

# Treasury wallet (receives 0.5% presale fee + post-TGE sell taxes)
# If omitted, defaults to the deployer address
TREASURY_ADDRESS=0xYourTreasuryWalletAddress

# Stablecoins on Base:
# Native Base USDC:
USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913

# USDT on Base (provide official bridged/native USDT address):
USDT_ADDRESS=0x0000000000000000000000000000000000000001

# Initial ETH/USD conversion price for public ETH purchases (default: 2500)
ETH_USD_PRICE=2500

# Basescan API key for contract verification
BASESCAN_API_KEY=your_basescan_api_key
```

### Step 3.2: Run the Deployment Script

Simulate first (dry-run):

```bash
source .env
forge script script/DeployPresale.s.sol:DeployPresale \
    --rpc-url $BASE_RPC_URL \
    -vvvv
```

Deploy live on Base:

```bash
forge script script/DeployPresale.s.sol:DeployPresale \
    --rpc-url $BASE_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv
```

When finished, Foundry will output:
- `SeraphToken deployed at: 0x...`
- `SeraphPresale deployed at: 0x...`

---

## 4. Allowlisting Addresses (Strategic & Private Tiers)

To allow specific investors or community members into Strategic (Tier 1) and Private (Tier 2):

```bash
# Call addToWhitelist as the treasury wallet:
cast send <PRESALE_ADDRESS> "addToWhitelist(address[])" "[0xUser1,0xUser2]" \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY
```

---

## 5. Wire the Frontend to the Deployed Contracts

Open `website/presale-app/src/config.ts` and set:

```typescript
export const PRESALE_ADDRESS = '0xYourDeployedPresaleAddress' as const
export const TOKEN_ADDRESS   = '0xYourDeployedTokenAddress' as const
export const USDC_ADDRESS    = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as const
export const USDT_ADDRESS    = '0xYourBaseUSDTAddress' as const

// Turn presale status to live:
export const PRESALE_LIVE = true
```

Optional: Set your WalletConnect Project ID in `.env`:
```
VITE_WALLETCONNECT_PROJECT_ID=your_project_id_from_cloud.walletconnect.com
```

### Build & Deploy the Frontend:

```bash
cd website/presale-app
npm run build

# Copy build to website/presale (or deploy website/dist directly to Vercel/Netlify/Cloudflare)
cp -r ../dist/* ../presale/
```

To run locally in dev mode:
```bash
cd website/presale-app
npm run dev
```

---

## 6. Post-Presale Management

### Executing TGE (Unlocks Claims)
Once `block.timestamp >= TGE_TIMESTAMP`, the treasury calls:

```bash
cast send <PRESALE_ADDRESS> "executeTGE()" \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY
```

Users can now visit the presale page and click **"CLAIM TGE PORTION"** to receive their initial tokens!

### Withdrawing Raised Funds
The treasury can withdraw raised stablecoins or ETH anytime:

```bash
# Withdraw USDC
cast send <PRESALE_ADDRESS> "withdrawStable(uint256,address)" <AMOUNT_IN_6_DECIMALS> <USDC_ADDRESS> \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY

# Withdraw ETH
cast send <PRESALE_ADDRESS> "withdrawETH()" \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY
```

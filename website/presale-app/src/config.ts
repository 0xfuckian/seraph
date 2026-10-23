/**
 * Seraph Presale — Contract configuration
 *
 * ⚠️  UPDATE THESE VALUES before going live:
 *   1. PRESALE_ADDRESS — deployed SeraphPresale contract on Base
 *   2. TOKEN_ADDRESS — deployed SeraphToken contract on Base
 *   3. USDT_ADDRESS / USDC_ADDRESS — real Base stablecoin addresses
 */

// ─── Contract addresses (Base mainnet) ──────────────────────────
// Replace with real deployed addresses before launch
export const PRESALE_ADDRESS = '0x0000000000000000000000000000000000000000' as const
export const TOKEN_ADDRESS   = '0x0000000000000000000000000000000000000000' as const

// Base mainnet stablecoins
// Real USDC on Base: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
// Real USDT on Base: check Tether's official deployment
export const USDC_ADDRESS = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as const
export const USDT_ADDRESS = '0x0000000000000000000000000000000000000001' as const // placeholder

// ─── Chain config ───────────────────────────────────────────────
export const CHAIN_ID = 8453 // Base mainnet

// ─── Presale is live? ───────────────────────────────────────────
// Set to true once contracts are deployed and you're ready to accept purchases
export const PRESALE_LIVE = false

// ─── Tier definitions (must match the on-chain contract) ────────
export interface TierConfig {
  id: number       // on-chain tierId (1-indexed)
  name: string
  badge: string
  badgeColor: 'magenta' | 'accent' | 'green'
  price: number    // USD price per token
  priceRaw: bigint // price in 1e6 units (stablecoin decimals)
  allocation: string
  allocationRaw: bigint
  tgePercent: number
  vestingLabel: string
  kycRequired: boolean
}

export const TIERS: TierConfig[] = [
  {
    id: 1,
    name: 'Strategic',
    badge: 'STRATEGIC',
    badgeColor: 'magenta',
    price: 0.02,
    priceRaw: 20000n,
    allocation: '3.75M SER',
    allocationRaw: 3_750_000n * 10n ** 18n,
    tgePercent: 25,
    vestingLabel: '14-day cliff · 12 mo',
    kycRequired: true,
  },
  {
    id: 2,
    name: 'Private',
    badge: 'PRIVATE',
    badgeColor: 'accent',
    price: 0.03,
    priceRaw: 30000n,
    allocation: '11.25M SER',
    allocationRaw: 11_250_000n * 10n ** 18n,
    tgePercent: 20,
    vestingLabel: '14-day cliff · 12 mo',
    kycRequired: true,
  },
  {
    id: 3,
    name: 'Public',
    badge: 'PUBLIC',
    badgeColor: 'green',
    price: 0.04,
    priceRaw: 40000n,
    allocation: '10M SER',
    allocationRaw: 10_000_000n * 10n ** 18n,
    tgePercent: 100,
    vestingLabel: 'None',
    kycRequired: false,
  },
]

// ─── Fee constants ──────────────────────────────────────────────
export const PRESALE_FEE_BPS = 50n // 0.5%
export const BPS = 10000n

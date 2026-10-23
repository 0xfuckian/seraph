/**
 * Seraph Presale + ERC20 ABIs
 * Extracted from the Foundry compilation output.
 * Only includes the functions/events the frontend needs.
 */

export const PRESALE_ABI = [
  // ── Read functions ────────────────────────────────
  {
    name: 'tiers',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'tierId', type: 'uint256' }],
    outputs: [
      { name: 'name', type: 'string' },
      { name: 'price', type: 'uint256' },
      { name: 'hardCap', type: 'uint256' },
      { name: 'sold', type: 'uint256' },
      { name: 'kycRequired', type: 'bool' },
      { name: 'lockupBps', type: 'uint256' },
      { name: 'vestingDuration', type: 'uint256' },
      { name: 'active', type: 'bool' },
    ],
  },
  {
    name: 'getProgress',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'sold', type: 'uint256' },
      { name: 'cap', type: 'uint256' },
    ],
  },
  {
    name: 'getBuyerAllocation',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'buyer', type: 'address' },
      { name: 'tierId', type: 'uint256' },
    ],
    outputs: [
      { name: 'total', type: 'uint256' },
      { name: 'tgeClaimed', type: 'uint256' },
      { name: 'releasable', type: 'uint256' },
    ],
  },
  {
    name: 'isWhitelisted',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'tierId', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getFeesCollected',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'usdtFees', type: 'uint256' },
      { name: 'usdcFees', type: 'uint256' },
      { name: 'ethFees', type: 'uint256' },
      { name: 'totalFeesUSD', type: 'uint256' },
    ],
  },
  {
    name: 'totalTokensSold',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalRaisedUSDT',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalRaisedUSDC',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalRaisedETH',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'ethUsdPrice',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'tgeExecuted',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'tierCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },

  // ── Write functions ───────────────────────────────
  {
    name: 'buyWithStablecoin',
    type: 'function',
    stateMutability: 'payable',
    inputs: [
      { name: 'tierId', type: 'uint256' },
      { name: 'stablecoinAmount', type: 'uint256' },
      { name: 'currency', type: 'address' },
      { name: 'referrer', type: 'address' },
    ],
    outputs: [],
  },
  {
    name: 'buyWithETH',
    type: 'function',
    stateMutability: 'payable',
    inputs: [{ name: 'tierId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'claimInitialAllocation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tierId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'claimVested',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tierId', type: 'uint256' }],
    outputs: [],
  },

  // ── Events ────────────────────────────────────────
  {
    name: 'Purchased',
    type: 'event',
    inputs: [
      { name: 'buyer', type: 'address', indexed: true },
      { name: 'tierId', type: 'uint256', indexed: false },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'cost', type: 'uint256', indexed: false },
      { name: 'currency', type: 'address', indexed: false },
    ],
  },
] as const

export const ERC20_ABI = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'decimals',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
] as const

import { useState, useMemo } from 'react'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { 
  useAccount, 
  useBalance, 
  useReadContract, 
  useWriteContract, 
  useWaitForTransactionReceipt,
  useChainId,
  useSwitchChain
} from 'wagmi'
import { parseUnits, formatUnits } from 'viem'
import { 
  PRESALE_ADDRESS, 
  USDC_ADDRESS, 
  USDT_ADDRESS, 
  CHAIN_ID, 
  PRESALE_LIVE, 
  TIERS, 
  TierConfig, 
  PRESALE_FEE_BPS, 
  BPS 
} from '../config'
import { PRESALE_ABI, ERC20_ABI } from '../abi'

type Currency = 'USDT' | 'USDC' | 'ETH'

export function Presale() {
  const { address, isConnected } = useAccount()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  const [selectedTier, setSelectedTier] = useState<TierConfig>(TIERS[1]) // Default to Private tier
  const [currency, setCurrency] = useState<Currency>('USDT')
  const [amount, setAmount] = useState<string>('')
  const [txError, setTxError] = useState<string | null>(null)
  const [txSuccess, setTxSuccess] = useState<string | null>(null)

  const isBase = chainId === CHAIN_ID
  const contractConfigured = PRESALE_ADDRESS !== '0x0000000000000000000000000000000000000000'

  // ── Token Balances ─────────────────────────────────────────────
  const { data: ethBalance } = useBalance({
    address,
    query: { enabled: isConnected },
  })

  const { data: usdcBalance } = useReadContract({
    address: USDC_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: isConnected && contractConfigured },
  })

  const { data: usdtBalance } = useReadContract({
    address: USDT_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: isConnected && contractConfigured },
  })

  // ── On-Chain Presale Progress ──────────────────────────────────
  const { data: progressData } = useReadContract({
    address: PRESALE_ADDRESS,
    abi: PRESALE_ABI,
    functionName: 'getProgress',
    query: { enabled: contractConfigured },
  })

  const { data: ethUsdPriceOnChain } = useReadContract({
    address: PRESALE_ADDRESS,
    abi: PRESALE_ABI,
    functionName: 'ethUsdPrice',
    query: { enabled: contractConfigured },
  })

  const ethPrice = ethUsdPriceOnChain ? Number(ethUsdPriceOnChain) : 2500

  // ── Allowlist Check ────────────────────────────────────────────
  const { data: isWhitelisted } = useReadContract({
    address: PRESALE_ADDRESS,
    abi: PRESALE_ABI,
    functionName: 'isWhitelisted',
    args: address ? [address, BigInt(selectedTier.id)] : undefined,
    query: { enabled: isConnected && contractConfigured },
  })

  // ── User Allocation in Selected Tier ───────────────────────────
  const { data: userAllocation, refetch: refetchAllocation } = useReadContract({
    address: PRESALE_ADDRESS,
    abi: PRESALE_ABI,
    functionName: 'getBuyerAllocation',
    args: address ? [address, BigInt(selectedTier.id)] : undefined,
    query: { enabled: isConnected && contractConfigured },
  })

  // ── Token Allowance (for USDT/USDC) ────────────────────────────
  const activeCurrencyAddress = currency === 'USDC' ? USDC_ADDRESS : USDT_ADDRESS

  const { data: currentAllowance, refetch: refetchAllowance } = useReadContract({
    address: activeCurrencyAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, PRESALE_ADDRESS] : undefined,
    query: { enabled: isConnected && contractConfigured && currency !== 'ETH' },
  })

  // ── Write Contracts ────────────────────────────────────────────
  const { writeContractAsync, isPending: isWritePending } = useWriteContract()
  const [activeTxHash, setActiveTxHash] = useState<`0x${string}` | undefined>(undefined)

  const { isLoading: isTxWaiting, isSuccess: isTxConfirmed } = useWaitForTransactionReceipt({
    hash: activeTxHash,
  })

  // ── Calculations ───────────────────────────────────────────────
  const parsedAmount = useMemo(() => {
    try {
      if (!amount || isNaN(Number(amount)) || Number(amount) <= 0) return 0n
      if (currency === 'ETH') {
        return parseUnits(amount, 18)
      } else {
        // USDT / USDC have 6 decimals
        return parseUnits(amount, 6)
      }
    } catch {
      return 0n
    }
  }, [amount, currency])

  const numAmount = Number(amount) || 0
  const feeAmount = (numAmount * Number(PRESALE_FEE_BPS)) / Number(BPS)
  const netAmount = numAmount - feeAmount

  const estimatedTokens = useMemo(() => {
    if (netAmount <= 0) return 0
    if (currency === 'ETH') {
      const netEth = netAmount
      const usdValue = netEth * ethPrice
      return Math.floor(usdValue / selectedTier.price)
    } else {
      return Math.floor(netAmount / selectedTier.price)
    }
  }, [netAmount, currency, ethPrice, selectedTier.price])

  // Allowance needed?
  const needsApproval = useMemo(() => {
    if (currency === 'ETH' || !contractConfigured) return false
    if (!currentAllowance) return true
    return currentAllowance < parsedAmount
  }, [currency, contractConfigured, currentAllowance, parsedAmount])

  // Get active currency balance string
  const currentBalanceFormatted = useMemo(() => {
    if (!isConnected) return '0.00'
    if (currency === 'ETH') {
      return ethBalance ? Number(formatUnits(ethBalance.value, 18)).toFixed(4) : '0.00'
    } else if (currency === 'USDC') {
      return usdcBalance ? Number(formatUnits(usdcBalance, 6)).toFixed(2) : '0.00'
    } else {
      return usdtBalance ? Number(formatUnits(usdtBalance, 6)).toFixed(2) : '0.00'
    }
  }, [currency, isConnected, ethBalance, usdcBalance, usdtBalance])

  // ── Action Handlers ────────────────────────────────────────────
  const handleApprove = async () => {
    setTxError(null)
    setTxSuccess(null)
    try {
      const hash = await writeContractAsync({
        address: activeCurrencyAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [PRESALE_ADDRESS, parseUnits('1000000000', 6)], // High allowance for smooth experience
      })
      setActiveTxHash(hash)
      setTxSuccess(`Approval transaction submitted: ${hash.slice(0, 10)}...`)
      await refetchAllowance()
    } catch (err: any) {
      setTxError(err.shortMessage || err.message || 'Approval failed')
    }
  }

  const handleBuy = async () => {
    setTxError(null)
    setTxSuccess(null)

    if (!isBase && switchChain) {
      switchChain({ chainId: CHAIN_ID })
      return
    }

    if (selectedTier.kycRequired && isWhitelisted === false) {
      setTxError('This address is not allowlisted for this tier.')
      return
    }

    try {
      let hash: `0x${string}`
      if (currency === 'ETH') {
        if (selectedTier.id !== 3) {
          setTxError('ETH is only accepted for the Public tier.')
          return
        }
        hash = await writeContractAsync({
          address: PRESALE_ADDRESS,
          abi: PRESALE_ABI,
          functionName: 'buyWithETH',
          args: [BigInt(selectedTier.id)],
          value: parsedAmount,
        })
      } else {
        hash = await writeContractAsync({
          address: PRESALE_ADDRESS,
          abi: PRESALE_ABI,
          functionName: 'buyWithStablecoin',
          args: [
            BigInt(selectedTier.id),
            parsedAmount,
            activeCurrencyAddress,
            '0x0000000000000000000000000000000000000000',
          ],
        })
      }
      setActiveTxHash(hash)
      setTxSuccess(`Purchase submitted! Tx: ${hash.slice(0, 10)}...`)
      setAmount('')
      refetchAllocation()
    } catch (err: any) {
      setTxError(err.shortMessage || err.message || 'Purchase failed')
    }
  }

  const handleClaimTGE = async () => {
    setTxError(null)
    try {
      const hash = await writeContractAsync({
        address: PRESALE_ADDRESS,
        abi: PRESALE_ABI,
        functionName: 'claimInitialAllocation',
        args: [BigInt(selectedTier.id)],
      })
      setActiveTxHash(hash)
      setTxSuccess(`Claim submitted! Tx: ${hash.slice(0, 10)}...`)
      refetchAllocation()
    } catch (err: any) {
      setTxError(err.shortMessage || err.message || 'Claim failed')
    }
  }

  const handleClaimVested = async () => {
    setTxError(null)
    try {
      const hash = await writeContractAsync({
        address: PRESALE_ADDRESS,
        abi: PRESALE_ABI,
        functionName: 'claimVested',
        args: [BigInt(selectedTier.id)],
      })
      setActiveTxHash(hash)
      setTxSuccess(`Vested claim submitted! Tx: ${hash.slice(0, 10)}...`)
      refetchAllocation()
    } catch (err: any) {
      setTxError(err.shortMessage || err.message || 'Vested claim failed')
    }
  }

  // Progress metrics
  const totalSoldTokens = progressData ? Number(formatUnits(progressData[0], 18)) : 0
  const totalCapTokens = progressData ? Number(formatUnits(progressData[1], 18)) : 25_000_000
  const percentFunded = totalCapTokens > 0 ? ((totalSoldTokens / totalCapTokens) * 100).toFixed(1) : '0'

  return (
    <>
      {/* ── Header ────────────────────────────────────────── */}
      <header>
        <a href="/" className="logo-cell">
          <span className="logo-badge" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="white">
              <path d="M12 1L12.9 9.8L21 12L12.9 14.2L12 23L11.1 14.2L3 12L11.1 9.8L12 1Z" />
            </svg>
          </span>
          <span className="logo">SERAPH<span className="dot">.</span></span>
        </a>
        <div className="nav-area">
          <div className="header-actions">
            <ConnectButton showBalance={false} chainStatus="icon" />
          </div>
        </div>
        <div className="status-cell">
          <span className={`status-dot ${PRESALE_LIVE ? 'live' : 'pending'}`}></span>
          <span className={`status-text ${PRESALE_LIVE ? 'live' : 'pending'}`}>
            {PRESALE_LIVE ? 'PRESALE LIVE' : 'PHASE 0 · UPCOMING'}
          </span>
        </div>
      </header>

      {/* ── Main Section ──────────────────────────────────── */}
      <main className="section">
        {/* Banner */}
        <div className={`presale-banner ${PRESALE_LIVE ? 'live' : ''}`}>
          <span className="pdot"></span>
          <div>
            <strong>
              {PRESALE_LIVE 
                ? 'Presale is LIVE on Base Mainnet' 
                : 'Presale Preparing for Launch on Base Mainnet'}
            </strong>
            <p>
              {PRESALE_LIVE
                ? 'Connect your wallet on Base to participate. Strategic and Private tiers require allowlisting; Public is open.'
                : 'Contracts are authored and ready for deployment. Connect your wallet to inspect terms, check your allowlist status, and preview allocations.'}
            </p>
          </div>
        </div>

        {/* Header Titles */}
        <div className="section-header">
          <div>
            <div className="meta">§ 09 — PRESALE · BASE MAINNET</div>
            <h1 className="section-title">Seed the continuum.</h1>
            <p className="section-desc">
              SERAPH ($SER) tier-based presale. Strategic and Private tiers are allowlisted; Public tier is open.
              All purchases interact directly with the verified on-chain presale contract.
            </p>
          </div>
        </div>

        {/* Target Metrics */}
        <div className="target-row">
          <div className="target-cell">
            <div className="num text-accent">25<span className="unit">M</span></div>
            <div className="lbl">Total SER for sale</div>
          </div>
          <div className="target-cell">
            <div className="num text-orange">$812.5<span className="unit">K</span></div>
            <div className="lbl">Target raise · all tiers</div>
          </div>
          <div className="target-cell">
            <div className="num text-green">{percentFunded}<span className="unit">%</span></div>
            <div className="lbl">Funded so far ({totalSoldTokens.toLocaleString()} SER)</div>
          </div>
        </div>

        {/* Tiers Grid */}
        <div className="meta">Select a Tier</div>
        <div className="tier-grid">
          {TIERS.map((tier) => {
            const isSelected = selectedTier.id === tier.id
            return (
              <div 
                key={tier.id}
                className={`tier-card ${isSelected ? 'active' : ''}`}
                onClick={() => setSelectedTier(tier)}
              >
                <span className={`tier-badge text-${tier.badgeColor}`}>
                  <span className="dot"></span> {tier.badge}
                </span>
                <div className="tier-name">{tier.name}</div>
                <div className="tier-detail">
                  {tier.kycRequired ? 'Allowlisted' : 'Open · No Allowlist'}
                </div>
                <div className="tier-price">
                  ${tier.price.toFixed(2)}<span className="unit">/SER</span>
                </div>
                <ul className="tier-list">
                  <li><span>Allocation</span><span className="v">{tier.allocation}</span></li>
                  <li><span>At TGE</span><span className="v">{tier.tgePercent}%</span></li>
                  <li><span>Vesting</span><span className="v">{tier.vestingLabel}</span></li>
                </ul>
                <div className="tier-progress">
                  <div className="tp-fill" style={{ width: `${percentFunded}%` }}></div>
                </div>
                <div className="tp-labels">
                  <span>Cap: {tier.allocation}</span>
                  <span>{tier.kycRequired ? 'Tier 1/2' : 'Tier 3'}</span>
                </div>
              </div>
            )
          })}
        </div>

        {/* ── User Allocation Details (if any purchased) ────── */}
        {isConnected && userAllocation && userAllocation[0] > 0n && (
          <div className="user-alloc-card">
            <div className="meta">Your Allocation ({selectedTier.name} Tier)</div>
            <div className="alloc-stats">
              <div className="alloc-stat-box">
                <div className="alloc-stat-val text-accent">
                  {Number(formatUnits(userAllocation[0], 18)).toLocaleString()}
                </div>
                <div className="alloc-stat-lbl">Total SER Allocated</div>
              </div>
              <div className="alloc-stat-box">
                <div className="alloc-stat-val">
                  {Number(formatUnits(userAllocation[1], 18)).toLocaleString()}
                </div>
                <div className="alloc-stat-lbl">TGE Claimed</div>
              </div>
              <div className="alloc-stat-box">
                <div className="alloc-stat-val text-green">
                  {Number(formatUnits(userAllocation[2], 18)).toLocaleString()}
                </div>
                <div className="alloc-stat-lbl">Releasable Now</div>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 12 }}>
              {userAllocation[1] === 0n && (
                <button className="action-btn secondary" onClick={handleClaimTGE} disabled={isWritePending}>
                  CLAIM TGE PORTION
                </button>
              )}
              {userAllocation[2] > 0n && (
                <button className="action-btn" onClick={handleClaimVested} disabled={isWritePending}>
                  CLAIM VESTED TOKENS
                </button>
              )}
            </div>
          </div>
        )}

        <div className="struct-line-accent"></div>

        {/* ── Purchase Panel ────────────────────────────────── */}
        <div className="meta">Buy SER</div>
        <div className="purchase-panel">
          {/* Left: Input & Buttons */}
          <div className="purchase-controls">
            <div className="currency-tabs">
              <button 
                className={`currency-tab ${currency === 'USDT' ? 'active' : ''}`}
                onClick={() => setCurrency('USDT')}
              >
                USDT
              </button>
              <button 
                className={`currency-tab ${currency === 'USDC' ? 'active' : ''}`}
                onClick={() => setCurrency('USDC')}
              >
                USDC
              </button>
              <button 
                className={`currency-tab ${currency === 'ETH' ? 'active' : ''}`}
                onClick={() => setCurrency('ETH')}
              >
                ETH
              </button>
            </div>

            <div className="amount-wrap">
              <span className="sym">{currency === 'ETH' ? 'Ξ' : '$'}</span>
              <input 
                className="amount-input" 
                type="text" 
                inputMode="decimal" 
                placeholder="0.00" 
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>

            <div className="balance-row">
              <span>Balance: {currentBalanceFormatted} {currency}</span>
              {isConnected && (
                <button 
                  className="max-btn" 
                  onClick={() => setAmount(currentBalanceFormatted)}
                >
                  MAX
                </button>
              )}
            </div>

            {/* Notifications / Alerts */}
            {selectedTier.kycRequired && isConnected && isWhitelisted === false && (
              <div className="notice-box warning">
                ⚠️ Your wallet is not on the allowlist for the {selectedTier.name} tier. Please choose the <b>Public</b> tier or contact the team.
              </div>
            )}

            {currency === 'ETH' && selectedTier.id !== 3 && (
              <div className="notice-box warning">
                ℹ️ Direct ETH purchases are designated for the <b>Public tier</b>. To buy Strategic or Private tiers, please switch to USDT or USDC.
              </div>
            )}

            {txError && (
              <div className="notice-box error">
                ✕ {txError}
              </div>
            )}

            {txSuccess && (
              <div className="notice-box success">
                ✓ {txSuccess}
              </div>
            )}

            {/* Action Buttons */}
            <div style={{ marginTop: 20 }}>
              {!isConnected ? (
                <ConnectButton.Custom>
                  {({ openConnectModal }) => (
                    <button className="action-btn" onClick={openConnectModal}>
                      CONNECT WALLET TO PARTICIPATE
                    </button>
                  )}
                </ConnectButton.Custom>
              ) : !isBase ? (
                <button 
                  className="action-btn" 
                  onClick={() => switchChain && switchChain({ chainId: CHAIN_ID })}
                >
                  SWITCH TO BASE NETWORK
                </button>
              ) : needsApproval ? (
                <button 
                  className="action-btn secondary" 
                  onClick={handleApprove}
                  disabled={isWritePending || isTxWaiting || parsedAmount === 0n}
                >
                  {isWritePending || isTxWaiting ? 'APPROVING...' : `APPROVE ${currency}`}
                </button>
              ) : (
                <button 
                  className="action-btn" 
                  onClick={handleBuy}
                  disabled={
                    isWritePending || 
                    isTxWaiting || 
                    parsedAmount === 0n || 
                    (selectedTier.kycRequired && isWhitelisted === false) ||
                    (currency === 'ETH' && selectedTier.id !== 3)
                  }
                >
                  {isWritePending || isTxWaiting ? 'PROCESSING...' : `BUY ${estimatedTokens.toLocaleString()} SER`}
                </button>
              )}
            </div>
          </div>

          {/* Right: Summary */}
          <div className="purchase-summary">
            <div className="meta">Order Summary</div>
            <div className="spec-row">
              <span className="k">Selected Tier</span>
              <span className="v">{selectedTier.name}</span>
            </div>
            <div className="spec-row">
              <span className="k">Token Price</span>
              <span className="v">${selectedTier.price.toFixed(2)} / SER</span>
            </div>
            <div className="spec-row">
              <span className="k">You Pay</span>
              <span className="v">{numAmount > 0 ? numAmount.toLocaleString() : '0.00'} {currency}</span>
            </div>
            <div className="spec-row">
              <span className="k">0.5% Presale Fee</span>
              <span className="v">{feeAmount > 0 ? feeAmount.toFixed(4) : '0.00'} {currency}</span>
            </div>
            <div className="spec-row">
              <span className="k">Est. SER Received</span>
              <span className="v accent">{estimatedTokens > 0 ? estimatedTokens.toLocaleString() : '—'} SER</span>
            </div>
            <div className="spec-row">
              <span className="k">Release Terms</span>
              <span className="v">{selectedTier.tgePercent}% at TGE, {selectedTier.vestingLabel}</span>
            </div>
          </div>
        </div>

        {/* ── FAQ ───────────────────────────────────────────── */}
        <div className="struct-line"></div>
        <div className="meta">Presale FAQ</div>
        <div className="faq">
          <details className="faq-item">
            <summary>How do I join the presale on Base?</summary>
            <p>
              Connect any Ethereum/Base compatible wallet (MetaMask, Coinbase Wallet, Rainbow, etc.). Ensure your wallet is connected to the Base network and has ETH for gas, plus USDT, USDC, or ETH to make your purchase.
            </p>
          </details>
          <details className="faq-item">
            <summary>What are the differences between tiers?</summary>
            <p>
              <b>Strategic ($0.02)</b>: Early backer tier, requires allowlisting, 25% at TGE with 12 months linear vesting (14-day cliff).<br />
              <b>Private ($0.03)</b>: Private backer tier, requires allowlisting, 20% at TGE with 12 months linear vesting (14-day cliff).<br />
              <b>Public ($0.04)</b>: Open to everyone without allowlist, 100% unlocked at TGE, accepts ETH in addition to stablecoins.
            </p>
          </details>
          <details className="faq-item">
            <summary>When do I receive my SER tokens?</summary>
            <p>
              Tokens are claimable right from this page at the Token Generation Event (TGE). For vested tiers, your remaining balance unlocks continuously over the 12-month period following the 14-day cliff.
            </p>
          </details>
          <details className="faq-item">
            <summary>What fees apply?</summary>
            <p>
              A 0.5% protocol fee is routed directly to the Seraph treasury contract upon purchase. Post-TGE, standard token transfers carry a 1% sell tax (50% burned, 50% treasury).
            </p>
          </details>
        </div>
      </main>

      {/* ── Footer ────────────────────────────────────────── */}
      <footer>
        <div className="footer-top">
          <span className="logo-badge" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="white">
              <path d="M12 1L12.9 9.8L21 12L12.9 14.2L12 23L11.1 14.2L3 12L11.1 9.8L12 1Z" />
            </svg>
          </span>
          <span className="logo">SERAPH<span className="dot">.</span></span>
          <span style={{ color: 'var(--color-sub)' }}>Privacy Continuum Protocol · Base Mainnet</span>
        </div>
        <div className="copyright">
          © Seraph Protocol. All contracts are verified and open-source. Never share your private keys.
        </div>
      </footer>
    </>
  )
}

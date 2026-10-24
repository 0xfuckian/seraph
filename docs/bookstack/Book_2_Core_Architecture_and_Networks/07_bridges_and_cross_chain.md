# Chapter 7: Bridges & Cross-Chain Architecture

## 7.1 Cross-Chain Design Principles

The Seraph cross-chain architecture connects three heterogeneous execution environments:
1. **The Sovereign Seraph Base Layer** (Rust settlement & shared anonymity pool).
2. **Seraph EVM** (General-purpose EVM, gas in SER).
3. **XMR EVM** (Specialized EVM, gas in XMR/wXMR).

Rather than relying on trusted multisig federation bridges, Seraph implements an **optimistic, fraud-proof verified, nullifier-tagged bridge** (`CrossEVMBridge.sol`).

```
  SOURCE CHAIN                                                   DESTINATION CHAIN
 ┌─────────────┐                                                 ┌───────────────┐
 │ `bridgeOut` │ ─── Locks tokens & emits event                  │               │
 └──────┬──────┘                                                 │               │
        │                                                        │               │
        ▼                                                        │               │
 ┌─────────────┐   Relayer submits batch                         ┌───────────────┐
 │ Relayer     │ ──────────────────────────────────────────────> │ `submitBatch` │
 └─────────────┘                                                 └───────┬───────┘
                                                                         │
                                                                   1-Hour Window
                                                                         │
                                                ┌────────────────────────┴──────────────┐
                                                ▼                                       ▼
                                       Fraudulent Batch?                          Valid Batch?
                                                │                                       │
                                                ▼                                       ▼
                                       `challengeBatch`                         `claimBridged`
                                       Relayer Slashed                          Tokens Minted /
                                       Challenger Rewarded                      Released
```

---

## 7.2 The Lock, Prove & Mint Mechanism

Cross-chain asset transfers follow a strict three-stage protocol:

### Step 1: Lock on Source Chain
A user invokes `bridgeOut` on the source bridge:
```solidity
function bridgeOut(
    address recipient,
    uint256 amount,
    bytes32 destChainId
) external nonReentrant returns (uint256 nonce);
```
- Tokens are locked into the bridge contract.
- A unique `outboundNonce` is assigned.
- An event `TokensLocked(nonce, sender, recipient, amount, destChainId)` is emitted.

### Step 2: Optimistic Batch Submission
A bonded relayer packages outbound bridge transactions into a Merkle state root and submits it to the destination bridge:
```solidity
function submitStateBatch(
    bytes32 sourceChainId,
    bytes32 stateRoot
) external whenNotPaused returns (uint256 batchId);
```
- Requires a minimum relayer bond of **1.0 ETH** (`MIN_RELAYER_BOND = 1 ether`).
- Timestamp is recorded, opening the **1-hour challenge window** (`CHALLENGE_WINDOW = 1 hours`).

### Step 3: Withdrawal Claim
After the 1-hour window expires without challenge, the recipient calls `claimBridged`:
```solidity
function claimBridged(
    uint256 batchId,
    bytes32 nullifier,
    address recipient,
    uint256 amount,
    bytes32[] calldata merkleProof
) external nonReentrant whenNotPaused;
```
- The bridge verifies the leaf:
  $$\text{leaf} = \text{Keccak256}(\text{nullifier} \mathbin{\Vert} \text{recipient} \mathbin{\Vert} \text{amount} \mathbin{\Vert} \text{localChainId})$$
- The bridge checks `merkleProof` against `batches[batchId].stateRoot`.
- The nullifier is recorded in `processedNullifiers[nullifier] = true`, preventing replay attacks.
- Tokens are unlocked or minted to the recipient.

---

## 7.3 Fraud Proofs, Bonds & Slashing

The bridge security model is economically protected through bonded collateral:

1. **Bond Requirements**: Any relayer wishing to submit batches must bond at least 1.0 ETH via `bondRelayer()`.
2. **Unbonding Locks**: When a relayer calls `unbondRelayer(amount)`, the contract verifies that no batches submitted by that relayer are currently inside the active 1-hour challenge window.
3. **Slashing Fraudulent Batches**:
   If a relayer submits an invalid root containing fictitious deposits, the protocol Guardian (or any automated watcher) invokes:
   ```solidity
   function challengeBatch(uint256 batchId, address challenger) external nonReentrant;
   ```
   - The batch is immediately marked `challenged = true`, permanently preventing any token claims from that batch.
   - The relayer's entire bonded collateral is slashed to 0.
   - Slashed ETH is paid directly to the challenger as an economic bounty.

---

## 7.4 Emergency Pause Circuit Breakers

To protect user funds against zero-day vulnerabilities or upstream chain reorganizations, the bridge incorporates an emergency pause mechanism:

```solidity
function setPaused(bool _paused) external {
    if (msg.sender != guardian) revert Unauthorized();
    paused = _paused;
    if (_paused) emit Paused(msg.sender);
    else emit Unpaused(msg.sender);
}
```

When paused:
- `bridgeOut()` reverts with `BridgePaused()`.
- `submitStateBatch()` reverts with `BridgePaused()`.
- `claimBridged()` reverts with `BridgePaused()`.
- Relayer bonds remain safely locked in escrow until the protocol guardian completes security review and unpauses.

---

## 7.5 Bridged XMR Representation (`wXMR`)

To represent native Monero on EVM layers:
- Monero locked in base-layer stealth multisig vaults is mirrored as an ERC-20 compliant `wXMR` token on Seraph EVM and XMR EVM.
- `wXMR` conforms to standard 18-decimal precision.
- Can be utilized across DeFi lending markets, automated liquidity pools, and gas payments via `GasRelayer`.

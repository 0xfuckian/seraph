# Chapter 7: Bridges & Cross-Chain Architecture

## 7.1 Cross-Chain Design Principles

The Seraph cross-chain architecture connects three heterogeneous execution environments:
1. **The Sovereign Seraph Base Layer** (Rust settlement & shared anonymity pool).
2. **Seraph EVM** (General-purpose EVM, gas in SER).
3. **XMR EVM** (Specialized EVM, gas in XMR / wXMR).

Rather than relying on closed multisig federation bridges, Seraph implements an **optimistic, bonded-relayer, nullifier-tagged bridge** (`CrossEVMBridge.sol`).

```
  SOURCE CHAIN                                                   DESTINATION CHAIN
 +-------------+                                                 +---------------+
 |  bridgeOut  | --- Locks tokens & emits event                  |               |
 +------+------+                                                 |               |
        |                                                        |               |
        v                                                        |               |
 +-------------+   Relayer submits batch                         +---------------+
 | Relayer     | ----------------------------------------------> |  submitBatch  |
 +-------------+                                                 +-------+-------+
                                                                         |
                                                                   1-Hour Window
                                                                         |
                                                 +-----------------------+-----------------------+
                                                 |                                               |
                                                 v                                               v
                                        Fraudulent Batch?                          Valid Batch?
                                                 |                                               |
                                                 v                                               v
                                         challengeBatch                             claimBridged
                                        Relayer Slashed                          Tokens Minted /
                                        Challenger Rewarded                      Released
```

---

## 7.2 The Lock, Prove & Mint Mechanism

Cross-chain asset transfers follow a strict three-stage protocol:

### Step 1: Lock on Source Chain
A user invokes `bridgeOut` on the source bridge contract:
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
  `leaf = Keccak256(nullifier || recipient || amount || localChainId)`
- The bridge checks `merkleProof` against `batches[batchId].stateRoot`.
- The nullifier is recorded in `processedNullifiers[nullifier] = true`, preventing replay attacks.
- Tokens are unlocked or minted to the recipient.

---

## 7.3 Trust Model, Fraud Challenges & Bond Slashing

The bridge security model operates in progressive trust phases:

### Phase 0/1: Optimistic Guardian-Attested Challenge Mechanism
In Phase 0 (testnet) and Phase 1 (initial mainnet), the bridge relies on bonded relayers and an active sentinel watcher network overseen by the Protocol Guardian Council:
1. **Bond Requirements**: Any relayer submitting state roots must deposit at least 1.0 ETH via `bondRelayer()`.
2. **Unbonding Locks**: When a relayer calls `unbondRelayer(amount)`, the contract verifies that no batches submitted by that relayer are currently inside the active 1-hour challenge window (`block.timestamp <= batch.timestamp + 1 hours`).
3. **Discretionary Guardian Challenge Procedure**:
   Sentinel nodes continuously monitor source-chain RPC event logs (`TokensLocked`). If a relayer submits an invalid root containing fictitious deposits, an authorized Guardian watcher executes:
   ```solidity
   function challengeBatch(uint256 batchId, address challenger) external nonReentrant;
   ```
   - The batch is immediately marked `challenged = true`, permanently preventing any token claims from that batch.
   - The relayer's entire bonded collateral (1.0 ETH) is slashed to 0.
   - Slashed ETH is paid directly to the challenger address as an economic bounty.

### Roadmap to Phase 2/3: Autonomous ZK Validity Proofs
To eliminate reliance on guardian watchtowers, Phase 2 upgrades the bridge from optimistic challenges to **Zero-Knowledge Validity Proofs**. Under this architecture, `submitStateBatch` requires a cryptographic SNARK proof certifying the validity of all source chain lock events against the source chain's block header, enabling trustless, instantaneous cross-chain finality without 1-hour dispute delays.

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

## 7.5 Bridged XMR Representation (`wXMR`) & Proof-of-Reserves

To represent native Monero on EVM layers:
- Monero locked in base-layer multi-sig stealth vaults is mirrored as an ERC-20 compliant `wXMR` token on Seraph EVM and XMR EVM.
- `wXMR` conforms to standard 18-decimal precision.
- **1:1 Reserve Invariant**: For every 1 `wXMR` minted on EVM layers, exactly 1 XMR is locked in the base-layer reserve vault.
- **Proof-of-Reserves**: The base-layer vault publishes cryptographic view-key disclosures (using $K_{\text{view}}$ audit packages) every 24 hours, allowing any user to independently verify that total locked base-layer XMR balance matches or exceeds total circulating `wXMR` across all EVM chains.

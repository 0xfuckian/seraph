# Seraph Protocol: Threat Model & Security Architecture

**Status:** Living Specification & Security Assessment  
**Target Environment:** Base Sepolia Testnet (Alpha) → Sovereign Base Layer (Mainnet)  
**Classification:** Public Security Specification  
**Last Updated:** October 2026  

---

## 1. Executive Summary

Seraph Protocol operates a **Privacy Continuum** architecture providing granular confidentiality levels from public transactions to zero-knowledge confidential compute across dual EVM layers and an eventual sovereign Rust settlement chain. 

This document provides a systematic threat model addressing the five primary attack surfaces identified across cryptographic verification, inter-layer bridging, Merkle state integrity, client key custody, and relayer network economics.

---

## 2. Threat Vector Analysis & Mitigations

```
               ┌────────────────────────────────────────────────────────┐
               │                SERAPH ATTACK VECTORS                   │
               └────────────────────────────────────────────────────────┘
                                           │
         ┌───────────────────┬─────────────┴──────┬───────────────────┐
         ▼                   ▼                    ▼                   ▼
┌──────────────────┐┌──────────────────┐┌──────────────────┐┌──────────────────┐
│ 1. Verifier      ││ 2. Guardian      ││ 3. Root History  ││ 4. Client-Side   │
│    Compromise    ││    Malice        ││    Exhaustion    ││    Key Theft     │
└──────────────────┘└──────────────────┘└──────────────────┘└──────────────────┘
         │                   │                    │                   │
         ▼                   ▼                    ▼                   ▼
┌──────────────────┐┌──────────────────┐┌──────────────────┐┌──────────────────┐
│ • Strict Binding ││ • Permissionless ││ • 100-Root Buffer││ • AES-GCM-256    │
│ • Non-Bypassable ││   Fraud Proofs   ││ • Ring Rollover  ││ • PBKDF2 100k    │
│ • Timelock Ctrl  ││ • 2-Step Handover││ • Re-proving Hook││ • Encrypted JSON │
└──────────────────┘└──────────────────┘└──────────────────┘└──────────────────┘
```

---

### Threat 1: Verifier Compromise & Proof Bypass

#### Attack Scenario
An attacker seeks to withdraw unshielded tokens or spend notes without possessing valid private preimages, either by:
1. Exploiting zero-address checks in smart contracts (`spendVerifier == address(0)`).
2. Supplying a forged or manipulated ZK proof that passes due to insufficient public signal binding.
3. Exploiting an unauthorized replacement of the verifier contract by a compromised treasury key.

#### Impact
Critical. Unauthorized token minting or complete drainage of the `PrivacyPool` collateral reserves.

#### Protocol Mitigations
1. **Mandatory Non-Bypassable Verification**:
   - `PrivacyPool.sol` strictly enforces:
     ```solidity
     require(spendVerifier != address(0), "PrivacyPool: spend verifier not configured");
     require(_verifySpendProof(root, nullifiers, commitments, proof), "PrivacyPool: invalid proof");
     ```
   - Zero-address verifiers revert execution immediately; there is no sandbox bypass in production paths.
   - `setSpendVerifier` explicitly reverts if `_verifier == address(0)`:
     ```solidity
     require(_verifier != address(0), "PrivacyPool: zero verifier not allowed");
     ```
2. **Strict Signal Binding**:
   - Public signals bind the Merkle `root`, `nullifiers`, and output `commitments` in deterministic array sequence.
   - Any modification to amounts, recipient addresses, or nullifiers produces mismatched proof signals and reverts on-chain.
3. **Governance Timelock**:
   - Upgrades to verifier contracts are governed by `SeraphTimelock` (minimum 24–48h delay floor), preventing instant backdoors.

---

### Threat 2: Guardian Malice & Censorship

#### Attack Scenario
A privileged `guardian` or `treasury` account behaves maliciously by:
1. Arbitrarily slashing honest bonded relayers.
2. Censoring legitimate state batch transitions across EVM layers.
3. Freezing bridge operations indefinitely via `setPaused(true)`.

#### Impact
High. Disruption of cross-chain liquidity and centralized censorship of bridge withdrawals.

#### Protocol Mitigations
1. **Permissionless Cryptographic Fraud Proofs**:
   - Bridge state challenges are **not restricted to guardians**. Any public actor (`msg.sender`) can challenge an invalid batch via `challengeBatchWithFraudProof`:
     ```solidity
     function challengeBatchWithFraudProof(
         uint256 batchId,
         bytes calldata fraudProof,
         bytes32[] calldata pubSignals
     ) external nonReentrant whenNotPaused;
     ```
   - Valid cryptographic fraud proofs slash the relayer's 1 ETH bond on-chain and reward the submitter directly without guardian mediation.
2. **Permissionless Duplicate Nullifier Proofs**:
   - Anyone can call `challengeDuplicateNullifier` to mathematically prove that a batch contains a previously spent nullifier, slashing the fraudulent relayer immediately.
3. **2-Step Governance Handover**:
   - Both `CrossEVMBridge` and `PrivacyPool` implement two-step ownership transfer (`transferGuardian`/`acceptGuardian` and `transferTreasury`/`acceptTreasury`), preventing single-transaction capture or fat-finger misdirection.
4. **Timelock Migration Path**:
   - Guardian and treasury roles are scheduled to transition to the `SeraphTimelock` and multi-sig DAO governance prior to mainnet value launch.

---

### Threat 3: Merkle Root History Exhaustion (Root Staleness DoS)

#### Attack Scenario
A high volume of deposits (`shield` operations) occurs between the moment a user generates a client-side ZK proof and the moment their transaction is included in an on-chain block. If the Merkle root advances by more than the ring buffer capacity, the historic root becomes unrecognized.

#### Impact
Medium. Transactions revert with `"PrivacyPool: unknown or expired root"`, causing griefing or front-running denial of service. Note funds remain safe and unspent, but must be re-proven against the updated tree.

#### Protocol Mitigations
1. **100-Root Ring Buffer**:
   - `PrivacyPool.sol` stores a circular history of recent roots:
     ```solidity
     uint32 public constant ROOT_HISTORY_SIZE = 100;
     bytes32[ROOT_HISTORY_SIZE] public roots;
     ```
   - At current block production rates, 100 insertions provide a resilient window for transaction confirmation.
2. **Client-Side Proof Freshness Verification**:
   - The Seraph TypeScript SDK (`@seraph/sdk`) polls `getLastRoot()` and compares the proving root against `isKnownRoot(root)` prior to transaction broadcast.
   - If a root is nearing ring buffer boundary, client-side re-proving hooks automatically re-anchor the proof to the latest root.
3. **Mainnet Scaling Roadmap**:
   - Transitioning `ROOT_HISTORY_SIZE` to 500–1,000 slots and integrating batch commitment trees for high-throughput mainnet epochs.

---

### Threat 4: Client-Side Key Theft & Storage Compromise

#### Attack Scenario
A user's browser environment is compromised via:
1. Malicious browser extensions reading `window.localStorage`.
2. Cross-site scripting (XSS) or prototype pollution attacks.
3. Physical access or unencrypted local backups.

#### Impact
High. If raw spend keys and note blinding factors are compromised, the attacker can submit a valid spend proof and steal the unshielded funds.

#### Protocol Mitigations
1. **Web Crypto AES-GCM-256 Vault Encryption**:
   - The Seraph web interface supports client-side password protection.
   - Notes are encrypted at rest using PBKDF2-SHA256 (100,000 iterations) with a 16-byte cryptographically secure random salt and AES-GCM-256 encryption.
   - Unencrypted note data is purged from `localStorage` upon encryption.
2. **Volatile Session Memory & Explicit Lock State**:
   - Decrypted notes reside solely in volatile JavaScript memory while unlocked.
   - Locking or reloading wipes active keys from DOM/memory, requiring passphrase re-entry.
3. **Encrypted Backup & Restore**:
   - Exported backup files can be encrypted with an independent passphrase, preventing plaintext disclosure in download directories.
4. **Hardened Content Security Policy (CSP)**:
   - `website/_headers` enforces `frame-ancestors 'none'`, `X-Frame-Options DENY`, `X-Content-Type-Options nosniff`, and strictly whitelisted `connect-src` RPC endpoints.

---

### Threat 5: Bridge Griefing & Relayer Bond Depletion

#### Attack Scenario
1. A malicious relayer posts spam batches with invalid state roots to consume relayer monitoring resources.
2. An attacker attempts to front-run a slash by withdrawing their relayer bond immediately after posting fraudulent data.

#### Impact
Medium to High. Liveness degradation or economic extraction.

#### Protocol Mitigations
1. **Minimum Relayer Bond Floor**:
   - Relayers must lock `MIN_RELAYER_BOND = 1 ether`. Batches cannot be proposed without active bonded collateral.
2. **Challenge Window Bond Locking**:
   - `unbondRelayer()` enforces a mandatory timelock:
     ```solidity
     if (lastSub > 0 && block.timestamp < uint256(lastSub) + CHALLENGE_WINDOW) {
         revert ChallengeWindowActive();
     }
     ```
   - Relayers cannot withdraw collateral while any submitted batch remains within the 1-hour challenge window.
3. **100% Sashing Economic Disincentive**:
   - Slashed relayer bonds are forfeited immediately and awarded to the challenger, making fraudulent proposals economically irrational.

---

## 3. Production Deployment Security Matrix

| Component | Testnet Status (Alpha) | Production Gate (Mainnet Candidate) |
| :--- | :--- | :--- |
| **ZK Verification** | Mandatory on-chain verifier checks | Multi-verifier consensus + Halo2/Circom formal proofs |
| **Bridge Challenges** | Permissionless fraud & nullifier checks | Decentralized light client + multi-relayer network |
| **Role Governance** | 2-step treasury & guardian handover | `SeraphTimelock` (48h) + multi-sig DAO governance |
| **Client Vault** | AES-GCM-256 + PBKDF2 encrypted storage | Hardware wallet / WebAuthn Enclave integration |
| **Audit Status** | Internal automated fuzzing & pentests | Tier-1 independent audits + formal circuit verification |

---

## 4. Conclusion

By systematically eradicating optional verification bypasses, opening bridge fraud challenges to permissionless callers, establishing two-step timelock governance controls, and hardening browser storage with authenticated encryption, Seraph establishes an uncompromising security foundation as it progresses toward mainnet deployment.

# Chapter 18: Emergency Procedures & Circuit Breakers

## 18.1 Emergency Architecture Overview

While Seraph is architected for decentralized autonomy, early-stage network operations require robust fail-safe mechanisms to protect user capital against unknown zero-day vulnerabilities, compiler bugs, or unexpected cross-chain bridge anomalies.

Seraph implements two on-chain **Emergency Circuit Breakers**:
1. **`PrivacyPool.setPaused(bool)`**: Gates all deposit (`shieldFor`), transfer (`privateTransfer`), and withdrawal (`unshield`) operations.
2. **`CrossEVMBridge.setPaused(bool)`**: Gates all outbound bridging (`bridgeOut`), batch submission (`submitStateBatch`), and claim operations (`claimBridged`).

---

## 18.2 Access Control & The Guardian Council

Emergency intervention is strictly governed by authorized administrative roles:
- **`PrivacyPool`**: Gated by `onlyTreasury`.
- **`CrossEVMBridge`**: Gated by `guardian`.

```
                         GUARDIAN SECURITY COUNCIL
               (4-of-7 Gnosis Safe Multisig with Hardware Keys)
                                      |
              +-----------------------+-----------------------+
              |                                               |
              v                                               v
     PrivacyPool.setPaused(true)                 CrossEVMBridge.setPaused(true)
     Freezes pool transfers & withdrawals        Freezes cross-chain message processing
```

### Multisig Composition:
The Guardian Council is structured as a **4-of-7 Gnosis Safe multisig**:
- 3 Core Cryptographic Engineers
- 2 Independent Security Auditors
- 2 Long-Standing Community / Validator Representatives
- Key signers are geographically distributed across 4 different legal jurisdictions.
- All signing operations require FIDO2 / WebAuthn hardware security keys.

### Pause & Admin Authority Matrix:

| Contract | Function | Authorized Role | Response Target | Timelock Requirement |
| :--- | :--- | :--- | :--- | :--- |
| `PrivacyPool` | `setPaused(true)` | Guardian / Treasury | < 15 minutes | Instant emergency execution |
| `PrivacyPool` | `setPaused(false)` | DAO Treasury | Post-audit recovery | 48-hour timelock delay |
| `PrivacyPool` | `setSpendVerifier` | DAO Treasury | Governed upgrade | 48-hour timelock delay |
| `CrossEVMBridge` | `setPaused(true)` | Guardian Council | < 15 minutes | Instant emergency execution |
| `CrossEVMBridge` | `challengeBatch` | Guardian / Sentinel | Inside 1-hour window | Instant 1 ETH relayer slash |
| `SERAPH` | `setSellTaxEnabled` | DAO Treasury | Governed policy | 48-hour timelock delay |
| `SERAPH` | `setTaxExempt` | DAO Treasury | DEX / CEX listing | 48-hour timelock delay |

---

## 18.3 Incident Response Playbook

In the event of an active security exploit or anomalous telemetry alert:

### Phase 1: Rapid Containment (< 15 Minutes)
1. **Automated Alert Trigger**: On-chain monitoring sentinels detect suspicious invariant deviations (e.g., unexpected token balance drain or invalid Merkle roots).
2. **Emergency Pause Execution**: The Guardian Council signs an emergency transaction calling:
   ```solidity
   privacyPool.setPaused(true);
   crossEVMBridge.setPaused(true);
   ```
3. **Immediate Effect**:
   - `shield()`, `privateTransfer()`, and `unshield()` revert with `"PrivacyPool: paused"`.
   - `bridgeOut()`, `submitStateBatch()`, and `claimBridged()` revert with `BridgePaused()`.
   - All assets currently held in the pool and bridge escrow are frozen in place, preventing further unauthorized extraction.

### Phase 2: Root-Cause Analysis (< 24 Hours)
1. Core developers and external auditors isolate the failing transaction hashes.
2. Reproduce the vulnerability in an isolated Foundry fork test (`forge test --fork-url`).
3. Formulate a patch (e.g., verifier replacement or logic hotfix).

### Phase 3: Governed Resolution & Remediation
- **Verifier Replacement**: If a zero-knowledge circuit defect is discovered, the DAO Treasury queues `setSpendVerifier(newVerifier)` through the 48-hour timelock, allowing community inspection before activation.
- **Bridge Slashing**: If a fraudulent relayer batch was submitted, the Guardian invokes `challengeBatch(batchId, treasury)` to slash the malicious relayer's 1.0 ETH bond and cancel the batch.

### Phase 4: Graceful Unpausing & Post-Mortem
1. Verify the patch across all 205+ test suites and invariant harnesses.
2. Following the timelock window, the unpause transaction executes:
   ```solidity
   privacyPool.setPaused(false);
   crossEVMBridge.setPaused(false);
   ```
3. Publish a comprehensive public post-mortem report within 48 hours detailing the incident timeline, root cause, economic impact (if any), and permanent architectural remediations.

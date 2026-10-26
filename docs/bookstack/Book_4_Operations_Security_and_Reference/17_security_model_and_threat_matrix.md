# Chapter 17: Security Model, Threat Vectors & Pentest Matrix

## 17.1 Security Philosophy: Defense in Depth

Decentralized privacy protocols carry unique security requirements: if a vulnerability exists in an arithmetic circuit or state contract, economic loss and loss of user anonymity can be catastrophic.

Seraph implements a multi-tiered defensive security architecture combining:
1. **Formal Mathematical Proofs**: Validating balance conservation and discrete logarithm hardness.
2. **Defensive Smart Contract Engineering**: Reentrancy guards, pull-escrow fee accounting, and emergency pause circuit breakers.
3. **Exhaustive Automated Fuzz Testing**: Over 896,000 stateful invariant checks across millions of randomized transactions.
4. **Adversarial Penetration Test Suites**: Rust base-layer pentesting and TypeScript DOM injection tests.

---

## 17.2 The Threat Matrix

| Threat Vector | Attack Scenario | Mitigation in Seraph Architecture | Verifying Test Suite |
| :--- | :--- | :--- | :--- |
| **1. Double-Spend Replay** | Attacker spends a note, then attempts to spend it again in the same or future block. | **Deterministic Nullifiers**: Any repeat nullifier is caught in O(1) and reverts before state changes. | `PrivacyPool.t.sol`<br>`adversarial_pentest.rs` |
| **2. Cross-Asset Substitution** | Attacker substitutes an XMR note for a SER note of equal value to mint unbacked tokens. | **Domain-Separated Commitments**: `AssetId` is hashed into the leaf commitment and verified in the R1CS spend circuit balance equation. | `adversarial_pentest.rs` |
| **3. Sybil Dividend Loop** | Attacker loops tokens through 10 addresses to claim multiple dividend allocations. | **Reward Debt Accounting**: Unclaimed dividends settle on transfer; reward debts update atomically. | `LaunchpadMultiActor.t.sol` |
| **4. Flash-Loan Curve Drain** | Attacker buys and sells on bonding curve within one transaction to exploit rounding errors. | **Monotonic Price Invariant**: Verified via fuzzing that roundtrip sell value is strictly <= buy cost. | `DeepPentestLaunchpadPresale.t.sol` |
| **5. Callback Reentrancy** | Malicious contract re-enters `claimDividends` or `buy` from inside `receive()`. | **OpenZeppelin ReentrancyGuard**: All external state transitions gated by `nonReentrant`. | `DeepPentestLaunchpadPresale.t.sol` |
| **6. Honeypot Fee Lockup** | Malicious creator specifies a fee wallet that always reverts on receiving ETH. | **Pull-Escrow Architecture**: Fees accumulate in contract balance; failure of fee wallet never blocks trades. | `LaunchpadMultiActor.t.sol` |
| **7. Merkle Tree Overflow** | Attacker attempts to insert more leaves than tree capacity (2²⁰). | **Capacity Bounds Check**: `require(nextLeafIndex < 2**TREE_DEPTH)` prevents tree overflow. | `PrivacyPool.sol` |
| **8. Expired Root Manipulation** | Attacker proves membership against an obsolete Merkle root to spend spent notes. | **100-Root Ring Buffer**: Roots older than 100 updates expire cleanly; unrecorded roots revert. | `PrivacyPool.t.sol` |
| **9. Bridge Fraud Front-Running** | Relayer submits fake batch and unbonds before challenge window expires. | **Active Window Timelock**: Relayers cannot unbond while any batch is inside the 1-hour window. | `CrossEVMBridge.sol` |
| **10. Gas Relayer Token Drain** | Attacker passes `target = address(serToken)` to drain tokens held in gas voucher escrow. | **Forbidden Target Filter**: Targets matching token addresses, relayer address, or zero revert instantly. | `GasRelayer.sol` |
| **11. Front-Running / MEV** | Bots monitor mempool to sandwich user trades and extract slippage. | **Threshold Encrypted Mempool**: Transactions are ordered while encrypted; decrypted only after ordering. | `StatefulProtocolInvariants.t.sol` |
| **12. DOM XSS / Injection** | Attacker launches token with malicious HTML in metadata to execute script in client web UI. | **Zero-Dependency Escaping**: All on-chain string data sanitized via `lpEsc()` before DOM injection. | `security_pentest.test.mjs` |
| **13. Rogue Verifier Swap** | Compromised admin or key updates `spendVerifier` to an exploit contract that approves invalid proofs. | **DAO Timelock & Event Monitoring**: `setSpendVerifier` is restricted to DAO Treasury with a 48-hour timelock delay; permanently renounced in Phase 3. | `PrivacyPool.t.sol` |

---

## 17.3 Automated Test Coverage & Proof Matrix

The protocol codebase is verified across four independent test frameworks:
- **Foundry Core Suites**: 205 unit, scenario, stress, and multi-actor tests passing with 100% success rate (`forge test`).
- **Foundry Stateful Invariants (`StdInvariant`)**: 896,000 continuous invariant checks with 0 reverts, proving:
  - `PrivacyPool` solvency: Balance equals net shielded minus unshielded.
  - `CollateralVault` solvency: 150% minimum collateral ratio preserved under all fuzz actions.
  - `GasRelayer` solvency: Escrowed balances match active voucher claims.
- **Rust Base Layer (`cargo test`)**: 17 adversarial pentest functions verifying Merkle proofs, view-key stream cipher security, and multi-asset domain separation.
- **Node.js SDK & UI Suites (`node:test`)**: 59 automated tests verifying ABI encoding, mathematical curve estimations, and live Base Sepolia JSON-RPC decoding.

---

## 17.4 Bug Bounty Program & Responsible Disclosure

Seraph maintains an active Bug Bounty Program to reward security researchers for responsible disclosure:

| Severity Level | Reward Cap | Eligible Findings |
| :--- | :--- | :--- |
| **Critical** | **Up to $250,000** | Direct theft of user funds, catastrophic loss of anonymity across all pool notes, complete bridge drain. |
| **High** | **Up to $50,000** | Unclaimed dividend drainage, temporary protocol freezing requiring guardian intervention, circumvention of sell tax. |
| **Medium** | **Up to $15,000** | Individual note linkage through side-channels, rounding discrepancies > 0.01%, non-critical denial-of-service. |
| **Low** | **Up to $3,000** | Minor gas optimizations, documentation inaccuracies, non-exploitable edge-case reverts. |

### Bug Bounty Rules & Scope:
- **In-Scope Targets**: Smart contracts in `contracts/core/` and `contracts/modules/`, arithmetic ZK circuits, and official `@seraph-protocol/sdk`.
- **Out-of-Scope**: Third-party RPC provider downtimes, social engineering, denial of service requiring spamming gas on public L2 networks, or vulnerabilities in unreleased test scripts.
- **Safe Harbor**: Security researchers acting in good faith who follow these guidelines, do not exploit bugs on production mainnets, and provide reasonable time for remediation will not face legal action.
- **Submission**: Reports should be submitted with reproducible Foundry/Rust test cases to `security@seraphprotocol.tech`.

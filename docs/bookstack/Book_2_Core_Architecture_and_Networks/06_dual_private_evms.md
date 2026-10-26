# Chapter 6: Dual Private EVMs

## 6.1 Architectural Overview

Seraph deploys two specialized Ethereum Virtual Machines designed to provide programmable privacy without sacrificing developer tooling:

```
                            THE DUAL EVM ARCHITECTURE
   +----------------------------------+      +----------------------------------+
   |            SERAPH EVM            |      |             XMR EVM              |
   +----------------------------------+      +----------------------------------+
   | - Native Gas: SER                |      | - Native Gas: XMR (wXMR)         |
   | - General-Purpose Smart Contracts|      | - Tight Base-Layer Coupling      |
   | - DeFi, Lending, Launchpad, NFT  |      | - Cross-Chain Settlement Hub     |
   | - Universal Precompiles (0x20..) |      | - Pure Privacy-Preserving Logic  |
   +----------------------------------+      +----------------------------------+
                    |                                          |
                    +------------------+-----------------------+
                                       |
                                       v
                        Cross-EVM Bridge & State Prover
```

> [!NOTE] Current Deployment Status (Phase 0 Sandbox) vs Target Dual EVM Architecture
> Today in Phase 0, all Seraph smart contracts (`SERAPH.sol`, `PrivacyPool.sol`, `CrossEVMBridge.sol`, `Launchpad.sol`, `Presale.sol`, etc.) are deployed on **Base Sepolia** (Chain ID `84532`), where transactions utilize standard Ethereum Virtual Machine gas (ETH). The Dual EVM architecture detailed in this chapter represents the **Phase 2** execution layer where execution gas is settled natively in SER (Seraph EVM) and atomic XMR / wXMR (XMR EVM).

---

## 6.2 Seraph EVM: General-Purpose Confidential Execution

The **Seraph EVM** is an optimized EVM runtime where:
- **Base Fee Token**: Paid natively in SER tokens.
- **Contract Environment**: 100% bytecode compatible with standard EVM bytecode (Cancun/Prague), allowing existing Solidity, Vyper, and Yul contracts to deploy seamlessly.
- **Confidential Extensions**: Developers can import Seraph privacy libraries to shield variables, store encrypted state in storage slots, and authenticate callers via zero-knowledge proofs.

---

## 6.3 XMR EVM: Native XMR Settlement

The **XMR EVM** is a purpose-built sister EVM where:
- **Gas Settlement in XMR**: Gas fees are calculated in standard EVM gas units but deducted from user account balances in atomic XMR (piconeros) or bridged `wXMR`.
- **Base-Layer Synchronization**: The state of the XMR EVM is closely coupled to the base layer's Monero anonymity pool.
- **Cross-EVM Interoperability**: Contracts on the XMR EVM can trigger cross-contract calls into Seraph EVM via the Cross-EVM Bridge.

---

## 6.4 Custom Privacy Precompiles

Both EVM runtimes introduce specialized cryptographic precompiles located in the reserved precompile address range (`0x20` to `0x25`):

| Address | Precompile Name | Description | Gas Cost |
| :--- | :--- | :--- | :--- |
| `0x20` | `PEDERSEN_COMMIT` | Computes C = v * H + r * G over BN254 | 750 gas |
| `0x21` | `POSEIDON_HASH` | High-throughput algebraic hash for ZK circuits | 300 gas |
| `0x22` | `STEALTH_DERIVE` | DKSAP derivation P = Hs(r * A) * G + B | 1,200 gas |
| `0x23` | `BULLETPROOF_VERIFY` | Verifies range proofs v in [0, 2⁶⁴ - 1] | 12,000 gas |
| `0x24` | `MERKLE_INSERT` | O(1) incremental Merkle tree insertion | 2,500 gas |
| `0x25` | `NULLIFIER_CHECK` | Checks and consumes nullifiers in state | 800 gas |

These precompiles reduce the computational cost of zero-knowledge privacy operations by up to 90% compared to equivalent pure-Solidity implementations.

---

## 6.5 Confidential Contract State & Encrypted Variables

Traditional EVMs make all contract storage slots publicly readable by anyone running a node. Seraph introduces **Confidential Storage Slots**:

```solidity
// Example: Confidential Storage in Solidity using Seraph Verifier
interface ISpendVerifier {
    function verifyProof(
        bytes calldata proof,
        uint256[2] calldata commitments,
        bytes32 root,
        bytes32 nullifier
    ) external view returns (bool);
}

contract PrivateBalanceVault {
    // Encrypted mapping: slot contains encrypted ciphertext + commitment
    mapping(address => bytes32) private encryptedBalances;
    ISpendVerifier public immutable verifier;

    constructor(address _verifier) {
        verifier = ISpendVerifier(_verifier);
    }
    
    // Homomorphic update via precompile / zero-knowledge proof
    function transferConfidential(
        bytes32 commitmentIn,
        bytes32 commitmentOut,
        bytes32 root,
        bytes32 nullifier,
        bytes calldata zkProof
    ) external {
        uint256[2] memory comms = [uint256(commitmentIn), uint256(commitmentOut)];
        require(verifier.verifyProof(zkProof, comms, root, nullifier), "Invalid proof");
        // State updated without exposing raw balance
    }
}
```

- Data stored in confidential slots is encrypted with a contract-level ephemeral key.
- State modifications require valid zero-knowledge proofs of authorization.
- Public observers see state transitions occur, but cannot decode the underlying quantities.

---

## 6.6 Tooling & Developer Compatibility

Seraph maintains strict compatibility with standard Web3 development tools:
- **Hardhat & Foundry**: Compile and test using standard `forge build` and `forge test` without custom compiler forks.
- **Ethers.js & Viem**: Standard JSON-RPC interface support (`eth_call`, `eth_sendRawTransaction`, `eth_getLogs`).
- **MetaMask & Web3 Wallets**: Connect directly by adding RPC URL and Chain ID.
- **OpenZeppelin Contracts**: Inherit directly from standard OpenZeppelin v5 libraries (`ERC20`, `ReentrancyGuard`, `Ownable`).

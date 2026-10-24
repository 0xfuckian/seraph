# Chapter 4: ZK Circuit Architecture & Prover Pipeline

## 4.1 Overview of the Proof System

The zero-knowledge proving subsystem of Seraph converts state transitions into rank-1 constraint systems (R1CS) and algebraic intermediate representations (AIR) verifiable within the Ethereum Virtual Machine (EVM).

Seraph utilizes two complementary proving backends:
1. **Groth16 (BN254)**: Deployed on the EVM for maximum gas efficiency. Groth16 yields 128-byte proofs and requires only 3 pairing operations during on-chain verification, consuming approximately 190,000 gas.
2. **UltraPLONK / Halo2**: Used for complex confidential contract state transitions on the private EVMs, offering custom gates, lookup tables, and universal setup parameters.

---

## 4.2 The Private Spend Circuit

The core circuit governing `PrivacyPool.sol` enforces four simultaneous constraints for every private spend:

```
                          ┌────────────────────────┐
                          │   PRIVATE SPEND PROOF  │
                          └───────────┬────────────┘
                                      │
       ┌──────────────────────────────┼──────────────────────────────┐
       ▼                              ▼                              ▼
  Merkle Tree                   Nullifier Derivation           Value Conservation
  Inclusion Proof                                              & Range Bounds
 (Depth 20 = 1,048,576)      N = H(spendKey, leafIndex)     sum(Vin) == sum(Vout) + Fee
```

### Circuit Constraints Specification:
1. **Merkle Inclusion Proof**:
   - Given a historic root $R \in \text{roots}[0..99]$ and a note commitment $C$, prove that $C$ exists at `leafIndex` along the path $\mathbf{p} = [p_0, p_1, \dots, p_{19}]$:
     $$h_0 = C$$
     $$h_{i+1} = \text{HashPair}(h_i, p_i) \quad \text{for } i \in [0, 19]$$
     $$\text{Enforce: } h_{20} == R$$
2. **Nullifier Derivation**:
   - The prover must prove knowledge of the private `spendKey` such that:
     $$\mathcal{N} = \text{Keccak256}(\text{spendKey} \mathbin{\Vert} \text{leafIndex})$$
   - Because `spendKey` is never revealed, the nullifier cannot be forged.
3. **Commitment Knowledge**:
   - The prover proves that the note commitment is mathematically valid:
     $$C = \text{Keccak256}(\text{asset} \mathbin{\Vert} v \mathbin{\Vert} \text{recipientPubkey} \mathbin{\Vert} \text{blinding})$$
4. **Range & Conservation**:
   - For all output notes $j \in [1, n]$:
     $$v_{\text{out}}^{(j)} \in [0, 2^{64}-1]$$
   - Conservation:
     $$\sum_{i=1}^m v_{\text{in}}^{(i)} = \sum_{j=1}^n v_{\text{out}}^{(j)} + f$$

---

## 4.3 On-Chain Verification (`IVerifier.sol`)

The EVM verifier contract evaluates pairing equations over the elliptic curve BN254.

```solidity
interface IVerifier {
    function verifyProof(
        bytes calldata proof,
        uint256[] calldata pubSignals
    ) external view returns (bool);
}
```

### Public Signals Layout:
The public signals array passed to `verifyProof` contains:
- `pubSignals[0]`: Historical Merkle Root ($R$)
- `pubSignals[1]`: Nullifier Hash ($\mathcal{N}$)
- `pubSignals[2]`: Output Commitment 1 ($C_{\text{out}}^{(1)}$)
- `pubSignals[3]`: Output Commitment 2 ($C_{\text{out}}^{(2)}$)
- `pubSignals[4]`: Public Amount (if unshielding, otherwise 0)
- `pubSignals[5]`: Public Recipient Address (if unshielding, otherwise 0)

### Gas Benchmark Table:
| Verification Operation | EVM Gas Cost | Execution Time |
| :--- | :--- | :--- |
| `ecAdd` (0x06 precompile) | 150 gas | < 0.05 ms |
| `ecMul` (0x07 precompile) | 6,000 gas | < 0.2 ms |
| `ecPairing` (0x08 precompile, 4 pairs) | 185,000 gas | < 1.8 ms |
| **Total `verifyProof` Execution** | **~210,000 gas** | **~2.1 ms** |

---

## 4.4 Client-Side Prover Benchmarks (WASM & WebGPU)

To prevent centralized information leakage, **all zero-knowledge proofs are generated locally on the user's client device**. The private keys and blinding scalars never touch a remote server.

Seraph's proving engine compiles to WebAssembly (WASM) with SIMD acceleration and experimental WebGPU compute shaders:

| Platform / Device | Proof Engine | Spend Proof Gen Time | Peak Memory |
| :--- | :--- | :--- | :--- |
| Apple M2 Max (Chrome / Desktop) | WebGPU Shaders | **1.24 s** | 185 MB |
| Apple M2 Max (Node.js) | Native C++ / Rust | **0.88 s** | 140 MB |
| Intel Core i7-12700K (Desktop) | WASM + SIMD | **2.15 s** | 210 MB |
| iPhone 15 Pro (Safari / Mobile) | WebAssembly | **3.42 s** | 195 MB |
| Samsung Galaxy S23 (Chrome) | WebAssembly | **4.10 s** | 220 MB |

---

## 4.5 Trusted Setup Transparency & Future STARK Upgrades

1. **Powers of Tau Ceremony**: Groth16 circuits rely on structured reference strings (SRS). Seraph utilizes the perpetual Powers of Tau ceremony (with over 1,000 international contributors). As long as one participant destroyed their toxic waste, the setup is secure.
2. **PLONK Universal Setup**: UltraPLONK implementations use KZG polynomial commitments over the same universal setup.
3. **STARK Upgrade Path**: Phase 4 of our research roadmap plans to integrate transparent, quantum-resistant STARKs (utilizing Rescue-Prime and Poseidon hashes) which eliminate trusted setups entirely.

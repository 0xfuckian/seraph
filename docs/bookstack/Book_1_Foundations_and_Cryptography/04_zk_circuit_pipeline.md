# Chapter 4: ZK Circuit Architecture & Prover Pipeline

## 4.1 Overview of the Proof System

The zero-knowledge proving subsystem of Seraph converts state transitions into rank-1 constraint systems (R1CS) and algebraic intermediate representations (AIR) verifiable within the Ethereum Virtual Machine (EVM).

Seraph utilizes two complementary proving backends:
1. **Groth16 (BN254)**: Deployed on the EVM for maximum execution efficiency. Groth16 yields 128-byte proofs and requires a single call to the EVM `ecPairing` (0x08) precompile evaluating 4 point pairs ($e(-A, B) \cdot e(\alpha, \beta) \cdot e(K_{pub}, \gamma) \cdot e(C, \delta) = 1$), consuming approximately 210,000 total gas.
2. **UltraPLONK / Halo2**: Used for complex confidential contract state transitions on the private EVMs, offering custom gates, lookup tables, and universal setup parameters.

---

## 4.2 The Private Spend Circuit

The core circuit governing `PrivacyPool.sol` enforces four simultaneous constraints for every private spend:

```
                          +------------------------+
                          |   PRIVATE SPEND PROOF  |
                          +-----------+------------+
                                      |
       +------------------------------+------------------------------+
       |                              |                              |
       v                              v                              v
  Merkle Tree                   Nullifier Derivation           Value Conservation
  Inclusion Proof                                              & Range Bounds
 (Depth 20 = 1,048,576)      N = H(spendKey, leafIndex)     sum(Vin) == sum(Vout) + Fee
```

### Circuit Constraints Specification (~24,800 R1CS Constraints):
1. **Merkle Inclusion Proof**:
   - Given a historic root `R` in `roots[0..99]` and a note commitment `C`, prove that `C` exists at `leafIndex` along the path `p = [p₀, p₁, ..., p₁₉]`:
     `h₀ = C`
     `h_{i+1} = HashPair(h_i, p_i) for i in [0, 19]`
     `Enforce: h₂₀ == R`
2. **Nullifier Derivation**:
   - The prover must prove knowledge of the private `spendKey` such that:
     `Nullifier N = Keccak256(spendKey || leafIndex)`
   - Because `spendKey` is never revealed, the nullifier cannot be forged.
3. **Commitment Knowledge**:
   - The prover proves that the note commitment is mathematically valid:
     `C = Keccak256(asset || amount || recipientPubkey || blinding)`
4. **Range & Conservation**:
   - For all output notes `j in [1, n]`:
     `v_out[j] in [0, 2⁶⁴ - 1]`
   - Exact token conservation:
     `Sum(v_in) == Sum(v_out) + unshield_amount + relayer_fee`

---

## 4.3 On-Chain Verification: IVerifier Specification

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
- `pubSignals[0]`: Historical Merkle Root (`R`)
- `pubSignals[1]`: Nullifier Hash (`N`)
- `pubSignals[2]`: Output Commitment 1 (`C_out_1`)
- `pubSignals[3]`: Output Commitment 2 (`C_out_2`)
- `pubSignals[4]`: Public Unshield Amount (if exiting, otherwise 0)
- `pubSignals[5]`: Public Recipient Address (if exiting, otherwise 0)

### Gas Benchmark Table:
| Verification Operation | EVM Precompile | EVM Gas Cost | Execution Time |
| :--- | :--- | :--- | :--- |
| `ecAdd` (Point Addition) | `0x06` precompile | 150 gas | < 0.05 ms |
| `ecMul` (Scalar Multiplication) | `0x07` precompile | 6,000 gas | < 0.2 ms |
| `ecPairing` (Batch 4-Pair Check) | `0x08` precompile | 181,000 gas | < 1.8 ms |
| Public Input Multi-Scalar Combination | Memory & EVM Arithmetic | ~23,000 gas | < 0.2 ms |
| **Total `verifyProof` Execution** | **Core Verifier Call** | **~210,000 gas** | **~2.1 ms** |

---

## 4.4 Client-Side Prover Benchmarks (WASM & WebGPU)

To prevent centralized information leakage, **all zero-knowledge proofs are generated locally on the user's client device**. Private keys and blinding scalars never touch a remote server.

Seraph's proving engine compiles to WebAssembly (WASM) with SIMD acceleration and experimental WebGPU compute shaders. Benchmarks measured across client environments for the 24,800-constraint spend circuit:

| Platform / Device | Proof Engine | Spend Proof Gen Time | Peak Memory |
| :--- | :--- | :--- | :--- |
| Apple M2 Max (Chrome / Desktop) | WebGPU Compute Shaders | **1.24 s** | 185 MB |
| Apple M2 Max (Node.js) | Native C++ / Rust (`arkworks`) | **0.38 s** | 140 MB |
| Intel Core i7-12700K (Desktop) | WASM + SIMD Acceleration | **2.15 s** | 210 MB |
| iPhone 15 Pro (Safari / Mobile) | WebAssembly | **3.42 s** | 195 MB |
| Samsung Galaxy S23 (Chrome) | WebAssembly | **4.10 s** | 220 MB |

---

## 4.5 Trusted Setup Ceremony & Future STARK Upgrades

1. **Phase 1: Universal Perpetual Powers of Tau**: Seraph's circuits build on the Hermez / Polygon universal Powers of Tau MPC ceremony conducted over BN254 with 54 international contributors. Soundness holds if at least one participant destroyed their secret randomness.
2. **Phase 2: Circuit-Specific Ceremony**: Prior to mainnet token generation, Seraph conducts a circuit-specific Groth16 Phase 2 ceremony for the exact R1CS constraints of `PrivacyPool.sol`. Contributors inject entropy using `snarkjs` with public transcripts and an independent cryptographic beacon finalizer.
3. **STARK Upgrade Path**: Phase 4 of our research roadmap plans to integrate transparent, quantum-resistant STARKs (utilizing Poseidon and Rescue-Prime algebraic hashes) which eliminate trusted setups entirely.

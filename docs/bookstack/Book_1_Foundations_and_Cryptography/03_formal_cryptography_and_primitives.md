# Chapter 3: Formal Cryptography & Primitives

## 3.1 Mathematical Notation & Elliptic Curve Parameters

Seraph uses a combination of two primary elliptic curve groups:

1. **Ed25519 / Curve25519**: Used on the high-throughput base layer for stealth addresses, signature verification, and view-key encryption.
   - Prime field: `p = 2²⁵⁵ - 19`
   - Base point generator: `G`
   - Curve equation: `-x² + y² = 1 - (121665 / 121666) · x² · y²`

2. **BN254 (alt_bn128)**: Used for on-chain zero-knowledge SNARK proof verification inside the Ethereum Virtual Machine via EVM precompiles at `0x06`, `0x07`, and `0x08`.
   - **Base Field Modulus (`p`)**:
     `p = 21888242871839275222246405745257275088696311157297823662689037894645226208583`
     (`0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47`)
     Defines the field `𝔽_p` over which elliptic curve point coordinates `(x, y)` exist.
   - **Scalar Field Order (`r`)**:
     `r = 21888242871839275222246405745257275088548364400416034343698204186575808495617`
     (`0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001`)
     Defines the field `𝔽_r` over which circuit constraints, private witness variables, and polynomials are evaluated.

### Common Symbols & Operators
- `𝔽_p`: The base field of characteristic `p`.
- `𝔽_r`: The scalar field of order `r` for SNARK circuits.
- `𝔾₁, 𝔾₂, 𝔾_T`: The pairing groups for BN254 with bilinear pairing `e: 𝔾₁ × 𝔾₂ -> 𝔾_T`.
- `x <~$ 𝔽_r`: Uniform random sampling from the field.
- `Hs(·)`: Cryptographic hash function mapping arbitrary byte strings to a field scalar in `𝔽_r`.
- `Hp(·)`: Hash function mapping arbitrary data to a point on elliptic curve group `𝔾`.
- `||`: Byte concatenation.

---

## 3.2 Pedersen Commitments

A Pedersen commitment binds the committer to a specific value `v` without revealing that value to observers.

### Construction
Let `G` and `H` be two independent generator points of the elliptic curve such that `log_G(H)` is unknown:
```
Commitment C = v · H + r · G
```
where:
- `v in [0, 2⁶⁴ - 1]` is the confidential amount.
- `r in 𝔽_r` is the uniform random blinding factor.

### Security Properties
1. **Information-Theoretic Hiding**: For any value `v`, and for any chosen commitment `C`, there exists a valid blinding factor `r` such that `C = v · H + r · G`. Therefore, an observer with infinite computational power learns zero information about `v`.
2. **Computational Binding**: Assuming the discrete logarithm problem is hard, it is computationally infeasible to find `(v, r)` and `(v', r')` such that `v != v'` and:
   `v · H + r · G = v' · H + r' · G`
   If an adversary could find such values, they could calculate the discrete logarithm:
   `log_G(H) = (r' - r) / (v - v')`

### Homomorphic Linearity
Pedersen commitments support homomorphic addition:
```
C₁ + C₂ = (v₁ · H + r₁ · G) + (v₂ · H + r₂ · G) = (v₁ + v₂) · H + (r₁ + r₂) · G
```

---

## 3.3 Stealth Address Derivation

Seraph uses the Dual-Key Stealth Address Protocol (DKSAP) to ensure that transactions sent to a recipient can never be linked to that recipient's public wallet address.

```
 Sender                                                    Recipient
(Knows A, B)                                              (Holds a, b)
     |                                                         |
     | 1. Sample r <--$ F_r                                    |
     | 2. Compute R = r · G                                    |
     | 3. S = r · A                                            |
     | 4. t = Hs(S)                                            |
     | 5. P = t · G + B                                        |
     |                                                         |
     +------------ Publishes (R, P, Encrypted Memo) ---------->|
     |                                                         | 6. Computes S' = a · R
     |                                                         |    (Notice S' == r · A)
     |                                                         | 7. t' = Hs(S')
     |                                                         | 8. P' = t' · G + B
     |                                                         | 9. Verifies P' == P
     |                                                         |10. Recovers x = t' + b
```

Because `x · G = (t' + b) · G = t' · G + b · G = P`, only the recipient possessing the private spend key `b` can authorize transfers from `P`.

---

## 3.4 Key Images and Nullifiers

To ensure privacy while preventing double-spending, Seraph uses two deterministic nullifier constructions:

### 1. Base Layer Key Image
For a one-time key `P = x · G`:
```
Key Image I = x · Hp(P)
```
If an adversary attempts to spend the note twice, they are forced to use the exact same private key `x`, producing an identical key image `I`.

### 2. EVM Privacy Pool Nullifier
In the `PrivacyPool.sol` smart contract, each private note has a unique nullifier:
```
Nullifier N = Keccak256(spendKey || leafIndex)
```
When a note is spent via `privateTransfer` or `unshield`:
1. The contract checks `require(!nullified[nullifier], "PrivacyPool: nullifier already spent")`.
2. The contract sets `nullified[nullifier] = true`.
3. The zero-knowledge verifier confirms that the nullifier corresponds to the valid note at `leafIndex` proven in the Merkle tree.

---

## 3.5 The Balance Equation with Protocol Fees

For any transaction consuming `m` input notes and generating `n` output notes with a public protocol fee `f`, the balance equation is:

```
Sum(v_in[i]) = Sum(v_out[j]) + f
```

### Sovereign Base Layer (Pedersen Verification)
Expressed in Pedersen commitments:
```
Sum(C_in[i]) - Sum(C_out[j]) - f · H = (Sum(r_in[i]) - Sum(r_out[j])) · G
```
Let `Delta_r = Sum(r_in) - Sum(r_out)`. The transaction prover provides a Schnorr signature proving knowledge of the private scalar `Delta_r` with respect to the public key point `Delta_r · G`.

### EVM Privacy Pool (Circuit Verification)
In the EVM Groth16 spend circuit, value conservation is verified directly as an arithmetic constraint:
```
Sum(input_amounts) === Sum(output_amounts) + public_unshield_amount + relayer_fee
```
This guarantees exact token conservation without exposing individual note quantities.

---

## 3.6 Range Proofs

Without range proofs, an adversary could spend `10 SER` and create two output notes of `15 SER` and `-5 SER`:
```
15 + (-5) = 10
```
Because arithmetic in `𝔽_r` is modular:
```
-5 == r - 5 (mod r)
```
A negative number is represented as a massive positive scalar, minting counterfeit tokens.

Seraph solves this by enforcing:
```
v in [0, 2⁶⁴ - 1]
```
This is proven either via logarithmic **Bulletproofs++** inner-product arguments on the base layer, or via 64-bit binary decomposition range constraints within the Groth16 circuits on the EVM.

---

## 3.7 Viewing Keys & Selective Compliance Disclosure

Seraph addresses the compliance dilemma through cryptographic key decoupling:

### 1. Incoming View Key (`K_in`)
- Derived via domain separation:
  `K_in = sha256Tag("seraph_viewkey_derive", spendKey)`
- Used by client wallets to scan the global Merkle tree and decrypt incoming note amounts and memos.
- Cannot spend funds or create transactions.

### 2. Outgoing View Key (`K_out`)
- Derived via domain separation:
  `K_out = sha256Tag("seraph_tax_disclosure", spendKey)`
- Authorizes generation of cryptographically signed compliance packages.
- Allows users to provide selective disclosure to accountants, auditors, or tax authorities proving:
  - Exact unshielded amounts.
  - Destination public addresses.
  - Timestamps and transaction hashes.
  - Authenticity verified without revealing other wallet balances.

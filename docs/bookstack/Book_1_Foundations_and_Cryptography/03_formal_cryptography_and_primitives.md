# Chapter 3: Formal Cryptography & Primitives

## 3.1 Mathematical Notation & Elliptic Curve Parameters

Seraph uses a combination of two primary elliptic curve groups:
1. **Ed25519 / Curve25519**: Used on the high-throughput base layer for stealth addresses, signature verification, and view-key encryption.
   - Prime field: $p = 2^{255} - 19$
   - Base point generator: $G$
   - Curve equation: $-x^2 + y^2 = 1 - \frac{121665}{121666} x^2 y^2$
2. **BN254 (alt_bn128)**: Used for on-chain zero-knowledge SNARK proof verification inside the Ethereum Virtual Machine via EVM precompiles at `0x06`, `0x07`, and `0x08`.
   - Prime field: $q = 21888242871839275222246405745257275088548364400416034343698204186575808495617$
   - Curve order: $r = 21888242871839275222246405745257275088696311157297823662689037894645226208583$

### Common Symbols
- $\mathbb{F}_q$: The scalar field of order $q$.
- $\mathbb{G}_1, \mathbb{G}_2, \mathbb{G}_T$: The pairing groups for BN254.
- $x \xleftarrow{\$} \mathbb{F}_q$: Uniform random sampling from the field.
- $\mathcal{H}_s(\cdot)$: Cryptographic hash function mapping arbitrary byte strings to a field scalar in $\mathbb{F}_q$.
- $\mathcal{H}_p(\cdot)$: Hash function mapping arbitrary data to a point on the elliptic curve group $\mathbb{G}$.

---

## 3.2 Pedersen Commitments

A Pedersen commitment binds the committer to a specific value $v$ without revealing that value to observers.

### Construction
Let $G$ and $H$ be two independent generator points of the elliptic curve such that $\log_G(H)$ is unknown:
$$C = vH + rG$$
where:
- $v \in [0, 2^{64}-1]$ is the confidential amount.
- $r \in \mathbb{F}_q$ is the uniform random blinding factor.

### Security Properties
1. **Information-Theoretic Hiding**: For any value $v$, and for any chosen commitment $C$, there exists a valid blinding factor $r$ such that $C = vH + rG$. Therefore, an observer with infinite computational power learns zero information about $v$.
2. **Computational Binding**: Assuming the discrete logarithm problem is hard, it is computationally infeasible to find $(v, r)$ and $(v', r')$ such that $v \neq v'$ and:
   $$vH + rG = v'H + r'G$$
   If an adversary could find such values, they could calculate the discrete logarithm:
   $$\log_G(H) = \frac{r' - r}{v - v'}$$

### Homomorphic Linearity
Pedersen commitments support homomorphic addition:
$$C_1 + C_2 = (v_1 H + r_1 G) + (v_2 H + r_2 G) = (v_1 + v_2)H + (r_1 + r_2)G$$

---

## 3.3 Stealth Address Derivation

Seraph uses the Dual-Key Stealth Address Protocol (DKSAP) to ensure that transactions sent to a recipient can never be linked to that recipient's public wallet address.

```
 Sender                                                    Recipient
(Knows A, B)                                              (Holds a, b)
     │                                                         │
     │ 1. Sample r <--$ Fq                                     │
     │ 2. Compute R = rG                                       │
     │ 3. S = rA                                               │
     │ 4. t = Hs(S)                                            │
     │ 5. P = tG + B                                           │
     │                                                         │
     ├───────────── Publishes (R, P, Encrypted Memo) ─────────>│
     │                                                         │ 6. Computes S' = aR
     │                                                         │    (Notice S' == rA)
     │                                                         │ 7. t' = Hs(S')
     │                                                         │ 8. P' = t'G + B
     │                                                         │ 9. Verifies P' == P
     │                                                         │10. Recovers x = t' + b
```

Because $xG = (t' + b)G = t'G + bG = P$, only the recipient possessing the private spend key $b$ can authorize transfers from $P$.

---

## 3.4 Key Images and Nullifiers

To ensure privacy while preventing double-spending, Seraph uses two deterministic nullifier constructions:

### 1. Base Layer Key Image
For a one-time key $P = xG$:
$$I = x \mathcal{H}_p(P)$$
If an adversary attempts to spend the note twice, they are forced to use the exact same private key $x$, producing an identical key image $I$.

### 2. EVM Privacy Pool Nullifier
In the `PrivacyPool.sol` smart contract, each private note has a unique nullifier:
$$\mathcal{N} = \text{Keccak256}(\text{spendKey} \mathbin{\Vert} \text{leafIndex})$$
When a note is spent via `privateTransfer` or `unshield`:
1. The contract checks `require(!nullified[nullifier], "nullifier already spent")`.
2. The contract sets `nullified[nullifier] = true`.
3. The zero-knowledge verifier confirms that the nullifier corresponds to the note at `leafIndex` proven in the Merkle tree.

---

## 3.5 The Balance Equation with Protocol Fees

For any transaction consuming $m$ input notes and generating $n$ output notes with a public protocol fee $f$, the balance equation is:

$$\sum_{i=1}^m v_{\text{in}}^{(i)} = \sum_{j=1}^n v_{\text{out}}^{(j)} + f$$

Expressed in Pedersen commitments:
$$\sum_{i=1}^m C_{\text{in}}^{(i)} - \sum_{j=1}^n C_{\text{out}}^{(j)} - f \cdot H = \left(\sum_{i=1}^m r_{\text{in}}^{(i)} - \sum_{j=1}^n r_{\text{out}}^{(j)}\right) G$$

Let $\Delta r = \sum r_{\text{in}} - \sum r_{\text{out}}$. The transaction prover provides a signature proving knowledge of the private scalar $\Delta r$ with respect to the public key point $\Delta r G$.

---

## 3.6 Range Proofs

Without range proofs, an adversary could spend $10 \text{ SER}$ and create two output notes of $15 \text{ SER}$ and $-5 \text{ SER}$:
$$15 + (-5) = 10$$
Because arithmetic in $\mathbb{F}_q$ is modular:
$$-5 \equiv q - 5 \pmod q$$
A negative number is represented as a massive positive scalar, minting counterfeit tokens.

Seraph solves this by enforcing:
$$v \in [0, 2^{64}-1]$$
This is proven either via logarithmic **Bulletproofs++** inner-product arguments on the base layer, or via zero-knowledge arithmetic range constraints within the SNARK circuits on the EVM.

---

## 3.7 Viewing Keys & Selective Compliance Disclosure

Seraph addresses the compliance dilemma through asymmetric key decoupling:

### 1. Incoming View Key ($\mathcal{K}_{\text{in}}$)
- Derived as $\mathcal{K}_{\text{in}} = \text{Keccak256}(\text{spendKey} \mathbin{\Vert} \text{"seraph\_viewkey\_derive"})$.
- Used by client wallets to scan the global Merkle tree and decrypt incoming note amounts and memos.
- Cannot spend funds or create transactions.

### 2. Outgoing View Key ($\mathcal{K}_{\text{out}}$)
- Authorizes generation of cryptographically signed compliance packages.
- Allows users to provide selective disclosure to accountants, auditors, or tax authorities proving:
  - Exact unshielded amounts.
  - Destination public addresses.
  - Timestamps and transaction hashes.
  - Authenticity verified without revealing other wallet balances.

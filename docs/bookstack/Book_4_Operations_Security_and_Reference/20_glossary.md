# Chapter 20: Glossary of Terms

An alphabetical reference of mathematical, cryptographic, and architectural terminology used throughout Seraph Protocol.

---

### A
- **Anonymity Set**: The set of all possible accounts or notes that could have originated a transaction. In Seraph, the anonymity set encompasses all unspent notes in the Merkle tree ($2^{20} = 1,048,576$).
- **AssetId**: A 32-bit identifier domain tag bound into note commitments to cryptographically separate SER, XMR, and custom tokens within the same anonymity pool.
- **Auto-LP**: A launchpad fee preset that directs trading fees directly into bonding curve quote reserves to accelerate pool graduation.

---

### B
- **Blinding Factor**: A random scalar $r \in \mathbb{F}_q$ used in Pedersen commitments and note derivations to render commitments information-theoretically hiding.
- **Bonding Curve**: A mathematical formula ($x \cdot y = k$) defining the continuous relationship between token supply and token price.
- **Bulletproofs++**: An optimized zero-knowledge range proof argument eliminating trusted setups and yielding logarithmic proof sizes.

---

### C
- **Circuit Breaker**: An on-chain emergency pause mechanism (`setPaused`) enabling the Guardian Council to freeze contract operations during active exploits.
- **CLSAG (Compact Linkable Spontaneous Anonymous Group)**: The compact ring signature algorithm historically used in Monero transactions.
- **Commitment**: A cryptographic hash binding a user to a specific value without revealing that value.
- **Confidential Storage Slot**: An encrypted EVM storage slot whose plaintext value is inaccessible to public observers without zero-knowledge authorization.

---

### D
- **Dandelion++**: A peer-to-peer transaction propagation protocol featuring stem and fluff phases to prevent network surveillance nodes from triangulating the origin IP.
- **DKSAP (Dual-Key Stealth Address Protocol)**: A cryptographic protocol allowing senders to derive unlinkable one-time public keys using a recipient's static view and spend keys.

---

### E
- **Enote (Electronic Note)**: A modular transaction output object separating ownership proof, value commitment, and nullifier generation.

---

### F
- **FCMP++ (Full-Chain Membership Proofs)**: A cryptographic advancement replacing small ring signatures with zero-knowledge membership proofs across the entire ledger history.
- **Fixed Pool**: A launchpad model where tokens are distributed at an unchanging fixed rate until the supply cap is exhausted.

---

### G
- **Gas Abstraction**: The capability for users to pay EVM transaction execution fees in arbitrary tokens (SER, XMR) without holding native ETH.
- **Groth16**: A zero-knowledge SNARK proof system producing constant-size 128-byte proofs verifiable on Ethereum with minimal gas overhead.

---

### H
- **Homomorphic Addition**: An algebraic property where operating on encrypted commitments yields a valid commitment to the sum of the plaintexts: $(v_1 H + r_1 G) + (v_2 H + r_2 G) = (v_1 + v_2)H + (r_1 + r_2)G$.

---

### I
- **Incoming View Key**: A private scalar key allowing a wallet to scan public blockchain blocks and decrypt incoming transaction amounts and memos without granting spending authority.
- **Incremental Merkle Tree**: A specialized append-only Merkle tree structure allowing logarithmic insertion ($O(\log N)$) and constant on-chain storage.

---

### J
- **Jamtis**: The comprehensive wallet addressing standard designed to accompany the Seraphis enote protocol.

---

### K
- **Key Image**: A deterministic cryptographic tag derived from a private key and its corresponding public key ($I = x \mathcal{H}_p(P)$) used to prevent double-spending in ring signature schemes.

---

### M
- **MEV (Maximal Extractable Value)**: Profit extracted by miners, validators, or searchers by arbitrarily including, excluding, or reordering transactions in a block.
- **Mempool**: The memory pool where pending transactions wait prior to block confirmation.

---

### N
- **Nullifier**: A deterministic 32-byte cryptographic identifier derived from a secret spend key and note index ($\mathcal{N} = \text{Keccak256}(\text{spendKey} \mathbin{\Vert} \text{leafIndex})$). When revealed, it proves a note has been spent without revealing which note it was.

---

### O
- **Outgoing View Key**: A private scalar key authorizing the generation of verifiable tax compliance and audit disclosure packages.

---

### P
- **Pedersen Commitment**: A computationally binding and information-theoretically hiding commitment scheme defined by $C = vH + rG$.
- **Privacy Continuum**: The four-tier privacy spectrum of Seraph spanning Level 0 (public EVM) to Level 3 (confidential contract state).
- **Pull-Escrow**: A defensive smart contract design pattern where balances accumulate in internal accounting records and are claimed by recipients, preventing malicious fallback revert attacks.

---

### R
- **Range Proof**: A zero-knowledge proof establishing that a confidential amount $v$ lies within a valid non-negative interval $[0, 2^{64}-1]$ without revealing $v$.
- **R1CS (Rank-1 Constraint System)**: A system of quadratic equations used to represent computational circuits in zero-knowledge SNARKs.

---

### S
- **Sell Tax**: A 1.00% protocol fee assessed exclusively on sell transactions of SER tokens, split 50% to a permanent burn address and 50% to the Protocol Treasury.
- **Seraph EVM**: The general-purpose confidential EVM where transaction gas is settled in SER tokens.
- **Shielding**: Depositing public ERC-20 tokens into the `PrivacyPool` to mint a confidential private note.
- **Stealth Address**: A one-time public key derived mathematically such that only the designated recipient can compute the corresponding private spend key.

---

### T
- **Tax Exemption Mapping (`taxExempt`)**: An on-chain registry allowing governance to whitelist DEX routers (Uniswap v3, Aerodrome) and CEX custody wallets from the 1.00% sell tax.
- **Threshold Cryptography**: A cryptographic scheme where a private key is split across $n$ parties, requiring a quorum of $t$ participants to decrypt data or sign messages.

---

### U
- **Unshielding**: Withdrawing private notes from the `PrivacyPool` to a public Ethereum recipient address with zero protocol tax.
- **Usage Ticket**: A one-time cryptographic voucher consumed by autonomous AI agents to pay compute providers without linking payments to master wallets.

---

### W
- **wXMR**: An ERC-20 token representing bridged Monero on EVM chains with 1:1 backing in base-layer multi-sig vaults.

---

### X
- **XMR EVM**: A specialized EVM environment where transaction gas fees are paid in native XMR or `wXMR`.
- **xUSD**: A confidential, decentralized stablecoin minted against over-collateralized SER and XMR deposits via the `CollateralVault`.

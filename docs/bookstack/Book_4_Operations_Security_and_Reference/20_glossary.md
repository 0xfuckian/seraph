# Chapter 20: Glossary of Terms

An alphabetical reference of mathematical, cryptographic, and architectural terminology used throughout Seraph Protocol.

---

### A
- **Anonymity Set**: The set of all possible accounts or notes that could have originated a transaction. In Seraph, the anonymity set encompasses all unspent notes in the Merkle tree (up to 2²⁰ = 1,048,576 notes).
- **AssetId**: A 32-bit identifier domain tag bound into note commitments to cryptographically separate SER, XMR, and custom tokens within the same anonymity pool.
- **Auto-LP**: A launchpad fee preset that directs trading fees directly into bonding curve quote reserves to accelerate pool graduation.

---

### B
- **Blinding Factor**: A random scalar r in Fq used in Pedersen commitments and note derivations to render commitments information-theoretically hiding.
- **Bonding Curve**: A mathematical formula (x * y = k) defining the continuous relationship between token supply and token price.
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
- **Dividend**: Proportionate ETH rewards distributed automatically to token holders on the Launchpad via the global accumulator algorithm (`accDividendPerShare`).
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
- **Groth16**: A zero-knowledge SNARK proof system producing constant-size 128-byte proofs verifiable on Ethereum with minimal gas overhead (~210,000 gas).
- **Guardian Council**: A 4-of-7 multi-signature governance body authorized to trigger emergency circuit breakers and challenge fraudulent bridge roots.

---

### H
- **Homomorphic Addition**: An algebraic property where operating on encrypted commitments yields a valid commitment to the sum of the plaintexts: (v1 * H + r1 * G) + (v2 * H + r2 * G) = (v1 + v2) * H + (r1 + r2) * G.

---

### I
- **Incoming View Key**: A private scalar key allowing a wallet to scan public blockchain blocks and decrypt incoming transaction amounts and memos without granting spending authority.
- **Incremental Merkle Tree**: A specialized append-only Merkle tree structure utilizing the filled subtrees algorithm, allowing O(depth) hash operations and constant O(depth) storage slots on-chain.

---

### J
- **Jamtis**: The comprehensive wallet addressing standard designed to accompany the Seraphis enote protocol.

---

### K
- **Key Image**: A deterministic cryptographic tag derived from a private key and its corresponding public key (I = x * Hp(P)) used to prevent double-spending in ring signature schemes.

---

### M
- **MEV (Maximal Extractable Value)**: Profit extracted by miners, validators, or searchers by arbitrarily including, excluding, or reordering transactions in a block.
- **Mempool**: The memory pool where pending transactions wait prior to block confirmation.

---

### N
- **Nullifier**: A deterministic 32-byte cryptographic identifier derived from a secret spend key and note index (N = Keccak256(spendKey || leafIndex)). When revealed, it proves a note has been spent without revealing which note it was.

---

### O
- **Outgoing View Key**: A private scalar key authorizing the generation of verifiable tax compliance and audit disclosure packages.

---

### P
- **Pedersen Commitment**: A computationally binding and information-theoretically hiding commitment scheme defined by C = v * H + r * G.
- **Privacy Continuum**: The four-tier privacy spectrum of Seraph spanning Level 0 (public EVM) to Level 3 (confidential contract state).
- **Pull-Escrow**: A defensive smart contract design pattern where balances accumulate in internal accounting records and are claimed by recipients, preventing malicious fallback revert attacks.

---

### Q
- **Quorum**: The minimum threshold of validator votes or key shares required to finalize an action, such as 5-of-7 sequencers in the encrypted threshold mempool.

---

### R
- **Range Proof**: A zero-knowledge proof establishing that a confidential amount v lies within a valid non-negative interval [0, 2⁶⁴ - 1] without revealing v.
- **R1CS (Rank-1 Constraint System)**: A system of quadratic equations used to represent computational circuits in zero-knowledge SNARKs.

---

### S
- **Sell Tax**: A 1.00% protocol fee assessed exclusively on sell transactions of SER tokens, split 50% to a permanent burn address and 50% to the Protocol Treasury.
- **Sequencer**: A bonded node responsible for ordering encrypted transactions into batches prior to threshold decryption.
- **Seraph EVM**: The general-purpose confidential EVM where transaction gas is settled in SER tokens.
- **Seraph Pool**: A hybrid launchpad model combining bonding curve automated market making with direct privacy pool note shielding.
- **Shielding**: Depositing public ERC-20 tokens into the `PrivacyPool` to mint a confidential private note.
- **Stealth Address**: A one-time public key derived mathematically such that only the designated recipient can compute the corresponding private spend key.

---

### T
- **Tax Exemption Mapping (`taxExempt`)**: An on-chain registry allowing governance to whitelist DEX routers (Uniswap v3, Aerodrome) and CEX custody wallets from the 1.00% sell tax.
- **TGE (Token Generation Event)**: The on-chain protocol initialization event when initial minting permissions are executed, vesting starts, and public token trading commences.
- **Threshold Cryptography**: A cryptographic scheme where a private key is split across n parties, requiring a quorum of t participants to decrypt data or sign messages.
- **Tier**: A structured investment tranche in the Seraph Presale (Tier 1 Strategic, Tier 2 Private, Tier 3 Public) with distinct pricing and vesting terms.

---

### U
- **Unshielding**: Withdrawing private notes from the `PrivacyPool` to a public Ethereum recipient address with zero protocol tax.
- **Usage Ticket**: A one-time cryptographic voucher consumed by autonomous AI agents to pay compute providers without linking payments to master wallets.

---

### V
- **Voucher**: A pre-funded cryptographic gas credit enabling transactions on the Seraph EVM via `GasRelayer` without holding native ETH.

---

### W
- **wXMR**: An ERC-20 token representing bridged Monero on EVM chains with 1:1 backing in base-layer multi-sig vaults.

---

### X
- **XMR EVM**: A specialized EVM environment where transaction gas fees are paid in native XMR or `wXMR`.
- **xUSD**: A confidential, decentralized stablecoin minted against over-collateralized SER and XMR deposits via the `CollateralVault`.

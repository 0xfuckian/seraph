# Chapter 10: Wallets, Scanning & Key Recovery

## 10.1 The Official Seraph Wallet Ecosystem

The Seraph wallet ecosystem provides non-custodial key management and privacy execution across desktop, mobile, and web interfaces:
- **Desktop Wallet (macOS, Linux, Windows)**: Full-featured native application with local zero-knowledge prover acceleration and optional integrated full-node synchronization.
- **Web Wallet & Browser Extension**: Lightweight client integrated directly into modern browsers, utilizing WASM and WebGPU shaders for client-side proof generation.
- **Mobile Wallet (iOS, Android)**: Fast, touch-optimized wallet with biometric key protection and delegated scan-key processing.

---

## 10.2 Key Hierarchy & Derivation

Seraph derives all cryptographic keys deterministically from a single standard 24-word BIP-39 mnemonic seed phrase:

```
                          24-WORD BIP-39 SEED
                                   |
                                   v
                       m/44'/9999'/0'/0/0 (BIP-44)
                                   |
                                   v
                       MASTER SPEND KEY (32 bytes)
                                   |
           +-----------------------+-----------------------+
           |                       |                       |
           v                       v                       v
   Incoming View Key           Scan Key            Outgoing View Key
   Hs("seraph_viewkey" || sk)  Hs("seraph_scan"||sk) Hs("seraph_tax" || sk)
   (Decrypts Incoming Notes)   (Fast Light-Client) (Audit Packages)
           |                                               |
           v                                               v
   Stealth Public Key                              Compliance Tag
   Hs("seraph_pubkey" || sk)                       Bilateral Verification
```

### Derivation Domain Separation:
All keys are derived from the 32-byte master spend key using domain-separated cryptographic hashing `Hs(tag || spendKey)`:
- **Master Spend Key (`K_spend`)**: Authorizes note spending and nullifier computation.
- **Incoming View Key (`K_in`)**: Decrypts note amounts, asset IDs, and memos during client scanning.
- **Scan Key (`K_scan`)**: Allows delegated light-clients or mobile nodes to identify candidate transactions without revealing transaction values.
- **Outgoing View Key (`K_out`)**: Generates bilateral audit disclosure tags for tax and regulatory reporting.

---

## 10.3 Client-Side Note Scanning (scanNotesForOwner)

Because note commitments on the blockchain are cryptographically blinded, a wallet must scan new ledger blocks to identify which notes belong to the user.

In Seraph, this is accomplished via **trial decryption** using the wallet's **Incoming View Key**:

```typescript
// Production Note Scanning Engine (sdk/typescript/src/index.ts)
const scannedNotes = scanNotesForOwner(encryptedNotes, incomingViewKey);
```

### The Magic Tag & Decryption Layout:
Every note memo payload is encoded with a 4-byte magic identifier (`NOTE_MAGIC = "SERP"` = `0x53455250`):
`Memo Layout = [4 bytes "SERP"] || [8 bytes Amount BE] || [1 byte AssetId] || [UTF-8 Memo]`

### AEAD Authenticated Encryption Specification:
While early prototypes utilized lightweight XOR keystream encryption, production Seraph wallets implement **ChaCha20-Poly1305 / AES-256-GCM** authenticated encryption:
1. **Key Derivation**:
   `k_memo = HKDF-Extract-Expand(K_in, blinding, "seraph_memo_aead_v1")`
2. **Nonce**:
   `nonce = blinding[0..12]`
3. **Decryption**:
   The wallet decrypts `encryptedMemo` using `k_memo` and `nonce`, authenticating against the note commitment `C` as associated authenticated data (AAD).
4. **Magic Verification**:
   The wallet inspects the first 4 bytes of decrypted plaintext:
   - If `decrypted[0..3] == 0x53455250`, the note **definitely belongs to this wallet**.
   - If the magic does not match or authentication fails, the note belongs to another user and is instantly discarded.
5. For matched notes, the wallet decodes the spendable balance, the asset type (`AssetId.Seraph` or `AssetId.Xmr`), and the transaction memo.

---

## 10.4 Verifiable Tax & Compliance Disclosures

Privacy should not require users to violate financial reporting laws. Seraph enables users to generate mathematical, verifiable compliance disclosure packages authenticated by their **Outgoing View Key**:

```typescript
// Generate Tax Package (sdk/typescript/src/index.ts)
const disclosure = generateComplianceDisclosure(spentRecords, outgoingViewKey);
```

### Disclosure Package Structure:
- `disclosureSummary`: JSON payload enumerating:
  - Consumed nullifiers (N_i).
  - Exact unshielded amounts.
  - Destination public addresses.
  - Timestamps and on-chain transaction hashes.
- `signatureTag`: 32-byte cryptographic authentication tag:
  `signatureTag = HMAC-SHA256(K_out, "seraph_tax_disclosure_v1" || summaryBytes)`

### Verification Model:
- **Bilateral Verification**: An auditor or tax accountant who receives the user's `outgoingViewKey` under confidentiality can verify the `signatureTag` and confirm that all reported transactions are authentic and complete, without receiving spending authority.
- **Third-Party Non-Repudiation**: For public or multi-party disclosures where revealing `K_out` is undesirable, the wallet generates a zero-knowledge proof of knowledge certifying that the tax report accurately accounts for all consumed nullifiers within the reported tax period.

---

## 10.5 Wallet Security Guidelines & AI Agent Key Isolation

1. **Standard Seed Phrase**: The 24-word seed phrase is sufficient to recover 100% of all past, present, and future funds and transaction history.
2. **Local Keystore Hardening**: Local keystores must encrypt secret seeds using **Argon2id** (memory cost 64 MB, time cost 3 iterations) or PBKDF2 with at least **600,000 iterations**.
3. **Autonomous AI Agent Key Isolation**: For automated AI agents executing compute streaming or micro-transactions, spend keys should be isolated within a Hardware Security Module (HSM), AWS KMS, or secure enclave (Apple Secure Enclave / TPM 2.0).
4. **Encrypted JSON Vault**: Desktop and web wallets export AES-256-GCM encrypted backup files containing cached Merkle paths, note commitments, and local address labels for instantaneous wallet restore without requiring a full chain rescan.

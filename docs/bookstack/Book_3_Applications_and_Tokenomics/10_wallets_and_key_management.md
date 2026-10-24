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
                                   │
                                   ▼
                       m/44'/9999'/0'/0/0 (BIP-44)
                                   │
                                   ▼
                       MASTER SPEND KEY (32 bytes)
                                   │
           ┌───────────────────────┴───────────────────────┐
           ▼                                               ▼
  Incoming View Key                                Outgoing View Key
  Hs("seraph_viewkey_derive" || spendKey)         Hs("seraph_tax_disclosure" || spendKey)
  (Scans & Decrypts Incoming Notes)               (Signs Verifiable Audit Packages)
           │                                               │
           ▼                                               ▼
  Stealth Public Key                              Compliance Signature
  Hs("seraph_pubkey_derive" || spendKey)          Tax / Audit Verification
```

---

## 10.3 Client-Side Note Scanning (`scanNotesForOwner`)

Because note commitments on the blockchain are cryptographically blinded, a wallet must scan new ledger blocks to identify which notes belong to the user.

In Seraph, this is accomplished via **trial decryption** using the wallet's **Incoming View Key**:

```typescript
// Production Note Scanning Engine (sdk/typescript/src/index.ts)
const scannedNotes = scanNotesForOwner(encryptedNotes, incomingViewKey);
```

### The Magic Tag & Decryption Layout:
Every note memo payload is encoded with a 4-byte magic identifier (`NOTE_MAGIC = "SERP"` = `0x53455250`):
$$\text{Memo Layout} = [\text{4 bytes "SERP"}] \mathbin{\Vert} [\text{8 bytes Amount BE}] \mathbin{\Vert} [\text{1 byte AssetId}] \mathbin{\Vert} [\text{UTF-8 Memo}]$$

1. The wallet iterates through new note commitments.
2. For each note, the wallet decrypts the ciphertext using its `incomingViewKey` and the note's public `blinding`:
   $$\text{decrypted} = \text{xorViewKeyMemo}(\mathcal{K}_{\text{in}}, \text{blinding}, \text{encryptedMemo})$$
3. The wallet inspects the first 4 bytes:
   - If `decrypted[0..3] == 0x53455250`, the note **definitely belongs to this wallet**!
   - If the magic does not match, the note belongs to another user and is instantly discarded.
4. For matched notes, the wallet decodes the exact spendable balance, the asset type (`AssetId.Seraph` or `AssetId.Xmr`), and the secret transaction memo.

---

## 10.4 Verifiable Tax & Compliance Disclosures

Privacy should not require users to violate financial reporting laws. Seraph enables users to generate mathematical, verifiable compliance disclosure packages signed by their **Outgoing View Key**:

```typescript
// Generate Tax Package (sdk/typescript/src/index.ts)
const disclosure = generateComplianceDisclosure(spentRecords, outgoingViewKey);
```

### Disclosure Package Structure:
- `disclosureSummary`: JSON payload enumerating:
  - Consumed nullifiers ($\mathcal{N}_i$).
  - Exact unshielded amounts.
  - Destination public addresses.
  - Timestamps and on-chain transaction hashes.
- `signatureTag`: 32-byte cryptographic HMAC tag:
  $$\text{signatureTag} = \text{SHA256Tag}(\text{"seraph\_tax\_disclosure\_v1"}, \mathcal{K}_{\text{out}}, \text{summaryBytes})$$

An auditor or tax accountant possessing the user's `outgoingViewKey` can verify the signature and prove that all reported transactions are authentic and comprehensive, without being given spending authority.

---

## 10.5 Encrypted Wallet Backups & Paper Recovery

1. **Standard Seed Phrase**: The 24-word seed phrase is sufficient to recover 100% of all past, present, and future funds and transaction history.
2. **Encrypted JSON Vault**: Desktop and web wallets allow exporting an AES-GCM-256 encrypted backup file containing cached Merkle paths, note commitments, and local address labels for instantaneous wallet restore without requiring a full chain rescan.
3. **Emergency Paper Key**: A printable cold-storage certificate containing the master spend key and incoming view key in high-density QR code format.

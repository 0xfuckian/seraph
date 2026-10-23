use sha3::{Digest, Keccak256};
use crate::assets::AssetId;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Note {
    pub asset: AssetId,
    pub amount: u64,
    pub recipient_pubkey: [u8; 32],
    pub blinding: [u8; 32],
    pub encrypted_memo: Vec<u8>,
}

impl Note {
    pub fn new(amount: u64, recipient_pubkey: [u8; 32], blinding: [u8; 32]) -> Self {
        Self::new_with_asset(AssetId::Seraph, amount, recipient_pubkey, blinding, Vec::new())
    }

    pub fn new_with_asset(
        asset: AssetId,
        amount: u64,
        recipient_pubkey: [u8; 32],
        blinding: [u8; 32],
        encrypted_memo: Vec<u8>,
    ) -> Self {
        Self {
            asset,
            amount,
            recipient_pubkey,
            blinding,
            encrypted_memo,
        }
    }

    /// Computes the cryptographic commitment = Keccak256(asset_tag || amount || pubkey || blinding)
    pub fn commitment(&self) -> [u8; 32] {
        let mut hasher = Keccak256::new();
        hasher.update(self.asset.domain_tag());
        hasher.update(self.amount.to_be_bytes());
        hasher.update(self.recipient_pubkey);
        hasher.update(self.blinding);
        hasher.finalize().into()
    }

    /// Derives the unique nullifier for spending this note = Keccak256(spend_key || leaf_index)
    pub fn derive_nullifier(spend_key: &[u8; 32], leaf_index: u32) -> [u8; 32] {
        let mut hasher = Keccak256::new();
        hasher.update(spend_key);
        hasher.update(leaf_index.to_be_bytes());
        hasher.finalize().into()
    }

    /// Encrypts/decrypts a memo payload using a view-key stream cipher (Keccak256 CTR).
    pub fn xor_memo(view_key: &[u8; 32], blinding: &[u8; 32], data: &[u8]) -> Vec<u8> {
        let mut hasher = Keccak256::new();
        hasher.update(b"seraph_memo_stream");
        hasher.update(view_key);
        hasher.update(blinding);
        let pad: [u8; 32] = hasher.finalize().into();
        data.iter().enumerate().map(|(i, b)| b ^ pad[i % 32]).collect()
    }
}

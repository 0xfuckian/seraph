use sha3::{Digest, Keccak256};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Note {
    pub amount: u64,
    pub recipient_pubkey: [u8; 32],
    pub blinding: [u8; 32],
}

impl Note {
    pub fn new(amount: u64, recipient_pubkey: [u8; 32], blinding: [u8; 32]) -> Self {
        Self {
            amount,
            recipient_pubkey,
            blinding,
        }
    }

    /// Computes the cryptographic commitment = Keccak256(amount || pubkey || blinding)
    pub fn commitment(&self) -> [u8; 32] {
        let mut hasher = Keccak256::new();
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
}

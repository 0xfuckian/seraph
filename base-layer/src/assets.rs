use sha3::{Digest, Keccak256};

/// First-class assets supported natively in the Seraph Base Layer shared anonymity pool.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum AssetId {
    Seraph = 0,
    Xmr = 1,
}

impl AssetId {
    pub fn symbol(&self) -> &'static str {
        match self {
            AssetId::Seraph => "SER",
            AssetId::Xmr => "XMR",
        }
    }

    /// Derives a blinded asset generator tag so SERAPH and XMR notes are indistinguishable
    /// inside the shared Merkle tree while preserving per-asset balance conservation.
    pub fn domain_tag(&self) -> [u8; 32] {
        let mut hasher = Keccak256::new();
        hasher.update(b"seraph_asset_generator_v1:");
        hasher.update([*self as u8]);
        hasher.finalize().into()
    }
}

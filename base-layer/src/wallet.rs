use sha3::{Digest, Keccak256};
use crate::assets::AssetId;
use crate::note::Note;
use crate::ledger::Transaction;

#[derive(Clone, Debug)]
pub struct TrackedNote {
    pub note: Note,
    pub leaf_index: u32,
    pub spent: bool,
}

pub struct Wallet {
    pub spend_key: [u8; 32],
    pub view_key: [u8; 32],
    pub pubkey: [u8; 32],
    pub notes: Vec<TrackedNote>,
}

impl Wallet {
    pub fn new(spend_key: [u8; 32]) -> Self {
        let mut vk_hasher = Keccak256::new();
        vk_hasher.update(spend_key);
        vk_hasher.update(b"seraph_viewkey_derive");
        let view_key: [u8; 32] = vk_hasher.finalize().into();

        let mut pk_hasher = Keccak256::new();
        pk_hasher.update(spend_key);
        pk_hasher.update(b"seraph_pubkey_derive");
        let pubkey: [u8; 32] = pk_hasher.finalize().into();

        Self {
            spend_key,
            view_key,
            pubkey,
            notes: Vec::new(),
        }
    }

    pub fn total_private_balance(&self) -> u64 {
        self.private_balance_of(AssetId::Seraph)
    }

    pub fn private_balance_of(&self, asset: AssetId) -> u64 {
        self.notes
            .iter()
            .filter(|n| !n.spent && n.note.asset == asset)
            .map(|n| n.note.amount)
            .sum()
    }

    pub fn add_note(&mut self, note: Note, leaf_index: u32) {
        self.notes.push(TrackedNote {
            note,
            leaf_index,
            spent: false,
        });
    }

    pub fn create_shield(&mut self, amount: u64, blinding: [u8; 32]) -> (Transaction, Note) {
        self.create_asset_shield(AssetId::Seraph, amount, blinding)
    }

    pub fn create_asset_shield(
        &mut self,
        asset: AssetId,
        amount: u64,
        blinding: [u8; 32],
    ) -> (Transaction, Note) {
        let note = Note::new_with_asset(asset, amount, self.pubkey, blinding, Vec::new());
        let commitment = note.commitment();
        let tx = Transaction::Shield {
            asset,
            from: self.pubkey,
            amount,
            commitment,
        };
        (tx, note)
    }

    pub fn create_private_transfer(
        &mut self,
        send_amount: u64,
        recipient_pubkey: [u8; 32],
        recipient_blinding: [u8; 32],
        change_blinding: [u8; 32],
        current_root: [u8; 32],
    ) -> Result<(Transaction, Note, Option<Note>), &'static str> {
        self.create_asset_private_transfer(
            AssetId::Seraph,
            send_amount,
            recipient_pubkey,
            recipient_blinding,
            change_blinding,
            current_root,
        )
    }

    pub fn create_asset_private_transfer(
        &mut self,
        asset: AssetId,
        send_amount: u64,
        recipient_pubkey: [u8; 32],
        recipient_blinding: [u8; 32],
        change_blinding: [u8; 32],
        current_root: [u8; 32],
    ) -> Result<(Transaction, Note, Option<Note>), &'static str> {
        let input_idx = self
            .notes
            .iter()
            .position(|n| !n.spent && n.note.asset == asset && n.note.amount >= send_amount)
            .ok_or("No single note large enough for transfer")?;

        let input_note = &mut self.notes[input_idx];
        input_note.spent = true;

        let input_amount = input_note.note.amount;
        let nullifier = Note::derive_nullifier(&self.spend_key, input_note.leaf_index);

        let recipient_note = Note::new_with_asset(asset, send_amount, recipient_pubkey, recipient_blinding, Vec::new());
        let mut commitments = vec![recipient_note.commitment()];

        let change_amount = input_amount - send_amount;
        let change_note = if change_amount > 0 {
            let note = Note::new_with_asset(asset, change_amount, self.pubkey, change_blinding, Vec::new());
            commitments.push(note.commitment());
            Some(note)
        } else {
            None
        };

        let tx = Transaction::PrivateTransfer {
            nullifiers: vec![nullifier],
            commitments,
            root: current_root,
        };

        Ok((tx, recipient_note, change_note))
    }

    pub fn create_unshield(
        &mut self,
        amount: u64,
        recipient_address: [u8; 32],
        current_root: [u8; 32],
    ) -> Result<Transaction, &'static str> {
        self.create_asset_unshield(AssetId::Seraph, amount, recipient_address, current_root)
    }

    pub fn create_asset_unshield(
        &mut self,
        asset: AssetId,
        amount: u64,
        recipient_address: [u8; 32],
        current_root: [u8; 32],
    ) -> Result<Transaction, &'static str> {
        let input_idx = self
            .notes
            .iter()
            .position(|n| !n.spent && n.note.asset == asset && n.note.amount == amount)
            .ok_or("No matching unspent note with exact amount found")?;

        let input_note = &mut self.notes[input_idx];
        input_note.spent = true;

        let nullifier = Note::derive_nullifier(&self.spend_key, input_note.leaf_index);

        Ok(Transaction::Unshield {
            asset,
            nullifier,
            amount,
            recipient: recipient_address,
            root: current_root,
        })
    }
}

use sha3::{Digest, Keccak256};
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
    pub pubkey: [u8; 32],
    pub notes: Vec<TrackedNote>,
}

impl Wallet {
    pub fn new(spend_key: [u8; 32]) -> Self {
        let mut hasher = Keccak256::new();
        hasher.update(spend_key);
        hasher.update(b"seraph_pubkey_derive");
        let pubkey: [u8; 32] = hasher.finalize().into();

        Self {
            spend_key,
            pubkey,
            notes: Vec::new(),
        }
    }

    pub fn total_private_balance(&self) -> u64 {
        self.notes.iter()
            .filter(|n| !n.spent)
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

    /// Prepares a shield transaction and records the pending note
    pub fn create_shield(&mut self, amount: u64, blinding: [u8; 32]) -> (Transaction, Note) {
        let note = Note::new(amount, self.pubkey, blinding);
        let commitment = note.commitment();
        let tx = Transaction::Shield {
            from: self.pubkey,
            amount,
            commitment,
        };
        (tx, note)
    }

    /// Creates a 1-input 2-output private transfer (recipient amount + change)
    pub fn create_private_transfer(
        &mut self,
        send_amount: u64,
        recipient_pubkey: [u8; 32],
        recipient_blinding: [u8; 32],
        change_blinding: [u8; 32],
        current_root: [u8; 32],
    ) -> Result<(Transaction, Note, Option<Note>), &'static str> {
        let input_idx = self.notes.iter().position(|n| !n.spent && n.note.amount >= send_amount)
            .ok_or("No single note large enough for transfer")?;

        let input_note = &mut self.notes[input_idx];
        input_note.spent = true;

        let input_amount = input_note.note.amount;
        let nullifier = Note::derive_nullifier(&self.spend_key, input_note.leaf_index);

        let recipient_note = Note::new(send_amount, recipient_pubkey, recipient_blinding);
        let mut commitments = vec![recipient_note.commitment()];

        let change_amount = input_amount - send_amount;
        let change_note = if change_amount > 0 {
            let note = Note::new(change_amount, self.pubkey, change_blinding);
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

    /// Creates an unshield transaction withdrawing from private pool to a transparent address
    pub fn create_unshield(
        &mut self,
        amount: u64,
        recipient_address: [u8; 32],
        current_root: [u8; 32],
    ) -> Result<Transaction, &'static str> {
        let input_idx = self.notes.iter().position(|n| !n.spent && n.note.amount == amount)
            .ok_or("No matching unspent note with exact amount found")?;

        let input_note = &mut self.notes[input_idx];
        input_note.spent = true;

        let nullifier = Note::derive_nullifier(&self.spend_key, input_note.leaf_index);

        Ok(Transaction::Unshield {
            nullifier,
            amount,
            recipient: recipient_address,
            root: current_root,
        })
    }
}

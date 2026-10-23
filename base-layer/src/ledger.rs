use std::collections::{HashMap, HashSet};
use crate::tree::IncrementalMerkleTree;

#[derive(Clone, Debug)]
pub enum Transaction {
    Shield {
        from: [u8; 32],
        amount: u64,
        commitment: [u8; 32],
    },
    PrivateTransfer {
        nullifiers: Vec<[u8; 32]>,
        commitments: Vec<[u8; 32]>,
        root: [u8; 32],
    },
    Unshield {
        nullifier: [u8; 32],
        amount: u64,
        recipient: [u8; 32],
        root: [u8; 32],
    },
}

pub struct Ledger {
    pub tree: IncrementalMerkleTree,
    pub nullified: HashSet<[u8; 32]>,
    pub transparent_balances: HashMap<[u8; 32], u64>,
}

impl Ledger {
    pub fn new() -> Self {
        Self {
            tree: IncrementalMerkleTree::new(),
            nullified: HashSet::new(),
            transparent_balances: HashMap::new(),
        }
    }

    pub fn set_balance(&mut self, account: [u8; 32], amount: u64) {
        self.transparent_balances.insert(account, amount);
    }

    pub fn get_balance(&self, account: &[u8; 32]) -> u64 {
        *self.transparent_balances.get(account).unwrap_or(&0)
    }

    pub fn apply(&mut self, tx: Transaction) -> Result<(), &'static str> {
        match tx {
            Transaction::Shield { from, amount, commitment } => {
                let bal = self.get_balance(&from);
                if bal < amount {
                    return Err("Insufficient transparent balance to shield");
                }
                self.transparent_balances.insert(from, bal - amount);
                self.tree.insert(commitment)?;
                Ok(())
            }
            Transaction::PrivateTransfer { nullifiers, commitments, root } => {
                if nullifiers.is_empty() || commitments.is_empty() {
                    return Err("Empty nullifiers or commitments");
                }
                if !self.tree.is_known_root(&root) {
                    return Err("Invalid or expired Merkle root");
                }
                for nullifier in &nullifiers {
                    if self.nullified.contains(nullifier) {
                        return Err("Double-spend detected: nullifier already spent");
                    }
                }
                for nullifier in nullifiers {
                    self.nullified.insert(nullifier);
                }
                for commitment in commitments {
                    self.tree.insert(commitment)?;
                }
                Ok(())
            }
            Transaction::Unshield { nullifier, amount, recipient, root } => {
                if !self.tree.is_known_root(&root) {
                    return Err("Invalid or expired Merkle root");
                }
                if self.nullified.contains(&nullifier) {
                    return Err("Double-spend detected: nullifier already spent");
                }
                self.nullified.insert(nullifier);
                let current_bal = self.get_balance(&recipient);
                self.transparent_balances.insert(recipient, current_bal + amount);
                Ok(())
            }
        }
    }
}

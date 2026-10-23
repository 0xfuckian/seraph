use std::collections::{HashMap, HashSet};
use crate::assets::AssetId;
use crate::tree::IncrementalMerkleTree;

#[derive(Clone, Debug)]
pub enum Transaction {
    Shield {
        asset: AssetId,
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
        asset: AssetId,
        nullifier: [u8; 32],
        amount: u64,
        recipient: [u8; 32],
        root: [u8; 32],
    },
}

pub struct Ledger {
    pub tree: IncrementalMerkleTree,
    pub nullified: HashSet<[u8; 32]>,
    pub transparent_balances: HashMap<([u8; 32], AssetId), u64>,
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
        self.set_asset_balance(account, AssetId::Seraph, amount);
    }

    pub fn set_asset_balance(&mut self, account: [u8; 32], asset: AssetId, amount: u64) {
        self.transparent_balances.insert((account, asset), amount);
    }

    pub fn get_balance(&self, account: &[u8; 32]) -> u64 {
        self.get_asset_balance(account, AssetId::Seraph)
    }

    pub fn get_asset_balance(&self, account: &[u8; 32], asset: AssetId) -> u64 {
        *self.transparent_balances.get(&(*account, asset)).unwrap_or(&0)
    }

    pub fn apply(&mut self, tx: Transaction) -> Result<(), &'static str> {
        match tx {
            Transaction::Shield { asset, from, amount, commitment } => {
                let bal = self.get_asset_balance(&from, asset);
                if bal < amount {
                    return Err("Insufficient transparent balance to shield");
                }
                self.transparent_balances.insert((from, asset), bal - amount);
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
            Transaction::Unshield { asset, nullifier, amount, recipient, root } => {
                if !self.tree.is_known_root(&root) {
                    return Err("Invalid or expired Merkle root");
                }
                if self.nullified.contains(&nullifier) {
                    return Err("Double-spend detected: nullifier already spent");
                }
                self.nullified.insert(nullifier);
                let current_bal = self.get_asset_balance(&recipient, asset);
                self.transparent_balances.insert((recipient, asset), current_bal + amount);
                Ok(())
            }
        }
    }
}

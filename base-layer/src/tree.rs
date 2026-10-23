use sha3::{Digest, Keccak256};

pub const TREE_DEPTH: usize = 20;
pub const ROOT_HISTORY_SIZE: usize = 100;

pub fn hash_pair(a: &[u8; 32], b: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Keccak256::new();
    if a < b {
        hasher.update(a);
        hasher.update(b);
    } else {
        hasher.update(b);
        hasher.update(a);
    }
    hasher.finalize().into()
}

pub struct IncrementalMerkleTree {
    pub next_leaf_index: u32,
    pub filled_subtrees: [[u8; 32]; TREE_DEPTH],
    pub roots: [[u8; 32]; ROOT_HISTORY_SIZE],
    pub current_root_index: usize,
    pub zeros: [[u8; 32]; TREE_DEPTH],
}

impl IncrementalMerkleTree {
    pub fn new() -> Self {
        let mut zeros = [[0u8; 32]; TREE_DEPTH];
        let mut filled_subtrees = [[0u8; 32]; TREE_DEPTH];

        let mut current_zero = Keccak256::digest(b"seraph_privacy_zero").into();
        zeros[0] = current_zero;
        filled_subtrees[0] = current_zero;

        for i in 1..TREE_DEPTH {
            current_zero = hash_pair(&current_zero, &current_zero);
            zeros[i] = current_zero;
            filled_subtrees[i] = current_zero;
        }

        let initial_root = hash_pair(&current_zero, &current_zero);
        let mut roots = [[0u8; 32]; ROOT_HISTORY_SIZE];
        roots[0] = initial_root;

        Self {
            next_leaf_index: 0,
            filled_subtrees,
            roots,
            current_root_index: 0,
            zeros,
        }
    }

    pub fn insert(&mut self, leaf: [u8; 32]) -> Result<u32, &'static str> {
        let max_leaves = 1u32 << TREE_DEPTH;
        if self.next_leaf_index >= max_leaves {
            return Err("Tree is full");
        }

        let leaf_index = self.next_leaf_index;
        let mut current_index = leaf_index;
        let mut current_hash = leaf;

        for i in 0..TREE_DEPTH {
            if current_index % 2 == 0 {
                self.filled_subtrees[i] = current_hash;
                current_hash = hash_pair(&current_hash, &self.zeros[i]);
            } else {
                current_hash = hash_pair(&self.filled_subtrees[i], &current_hash);
            }
            current_index /= 2;
        }

        self.current_root_index = (self.current_root_index + 1) % ROOT_HISTORY_SIZE;
        self.roots[self.current_root_index] = current_hash;
        self.next_leaf_index = leaf_index + 1;

        Ok(leaf_index)
    }

    pub fn get_last_root(&self) -> [u8; 32] {
        self.roots[self.current_root_index]
    }

    pub fn is_known_root(&self, root: &[u8; 32]) -> bool {
        if *root == [0u8; 32] {
            return false;
        }
        let mut idx = self.current_root_index;
        for _ in 0..ROOT_HISTORY_SIZE {
            if self.roots[idx] == *root {
                return true;
            }
            if idx == 0 {
                idx = ROOT_HISTORY_SIZE - 1;
            } else {
                idx -= 1;
            }
        }
        false
    }
}

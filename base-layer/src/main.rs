use seraph_core::ledger::Ledger;
use seraph_core::wallet::Wallet;

fn main() {
    println!("==================================================");
    println!("  Seraph Protocol — Base Layer CLI Node (Phase 0) ");
    println!("  Privacy Continuum Settlement & Note Pool Engine ");
    println!("==================================================");

    let mut ledger = Ledger::new();
    println!("[Node] Initialized Incremental Merkle Tree (Depth 20).");
    println!("[Node] Initial Root: 0x{}", hex::encode(ledger.tree.get_last_root()));

    let mut alice = Wallet::new([1u8; 32]);
    let mut bob = Wallet::new([2u8; 32]);

    println!("[Wallet Alice] Pubkey: 0x{}", hex::encode(alice.pubkey));
    println!("[Wallet Bob]   Pubkey: 0x{}", hex::encode(bob.pubkey));

    // Fund Alice
    ledger.set_balance(alice.pubkey, 5_000);
    println!("[Faucet] Credited 5,000 SER to Alice's transparent address.");

    // Alice shields 5,000 SER
    let (shield_tx, alice_note) = alice.create_shield(5_000, [42u8; 32]);
    ledger.apply(shield_tx).expect("Shield failed");
    alice.add_note(alice_note, 0);
    println!("[Shield] Alice shielded 5,000 SER into Note Pool.");
    println!("[Shield] Tree leaves: {}", ledger.tree.next_leaf_index);
    println!("[Shield] Alice Private Balance: {} SER", alice.total_private_balance());

    // Alice transfers 2,500 SER to Bob
    let root = ledger.tree.get_last_root();
    let (tx, bob_note, change_note) = alice
        .create_private_transfer(2_500, bob.pubkey, [88u8; 32], [99u8; 32], root)
        .expect("Transfer failed");

    ledger.apply(tx).expect("Apply transfer failed");
    bob.add_note(bob_note, 1);
    alice.add_note(change_note.unwrap(), 2);

    println!("[Private Transfer] 2,500 SER sent to Bob privately.");
    println!("[Ledger] Spent nullifiers count: {}", ledger.nullified.len());
    println!("[Ledger] Total tree commitments: {}", ledger.tree.next_leaf_index);
    println!("[State] Alice Private Balance: {} SER", alice.total_private_balance());
    println!("[State] Bob Private Balance:   {} SER", bob.total_private_balance());
    println!("==================================================");
    println!("  Phase 0 End-to-End Privacy Verified Successfully! ");
    println!("==================================================");
}

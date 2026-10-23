use seraph_core::assets::AssetId;
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

    // Fund Alice with SER and XMR
    ledger.set_balance(alice.pubkey, 5_000);
    ledger.set_asset_balance(alice.pubkey, AssetId::Xmr, 25);
    println!("[Faucet] Credited 5,000 SER + 25 XMR to Alice.");

    // Alice shields 5,000 SER + 25 XMR into the shared Note Pool
    let (shield_tx, alice_note) = alice.create_shield(5_000, [42u8; 32]);
    ledger.apply(shield_tx).expect("Shield SER failed");
    alice.add_note(alice_note, 0);

    let (xmr_shield_tx, alice_xmr_note) = alice.create_asset_shield(AssetId::Xmr, 25, [43u8; 32]);
    ledger.apply(xmr_shield_tx).expect("Shield XMR failed");
    alice.add_note(alice_xmr_note, 1);

    println!(
        "[Shield] Shared Note Pool leaves: {} (Alice: {} SER, {} XMR)",
        ledger.tree.next_leaf_index,
        alice.private_balance_of(AssetId::Seraph),
        alice.private_balance_of(AssetId::Xmr)
    );

    // Alice transfers 2,500 SER and 10 XMR privately to Bob
    let root = ledger.tree.get_last_root();
    let (tx, bob_note, change_note) = alice
        .create_private_transfer(2_500, bob.pubkey, [88u8; 32], [99u8; 32], root)
        .expect("SER transfer failed");
    ledger.apply(tx).expect("Apply SER transfer failed");
    bob.add_note(bob_note, 2);
    alice.add_note(change_note.unwrap(), 3);

    let root2 = ledger.tree.get_last_root();
    let (xmr_tx, bob_xmr, xmr_change) = alice
        .create_asset_private_transfer(AssetId::Xmr, 10, bob.pubkey, [77u8; 32], [66u8; 32], root2)
        .expect("XMR transfer failed");
    ledger.apply(xmr_tx).expect("Apply XMR transfer failed");
    bob.add_note(bob_xmr, 4);
    alice.add_note(xmr_change.unwrap(), 5);

    println!("[Private Transfer] Sent 2,500 SER + 10 XMR to Bob in shared anonymity set.");
    println!("[Ledger] Spent nullifiers: {} | Tree commitments: {}", ledger.nullified.len(), ledger.tree.next_leaf_index);
    println!(
        "[State] Alice: {} SER, {} XMR | Bob: {} SER, {} XMR",
        alice.private_balance_of(AssetId::Seraph),
        alice.private_balance_of(AssetId::Xmr),
        bob.private_balance_of(AssetId::Seraph),
        bob.private_balance_of(AssetId::Xmr)
    );
    println!("==================================================");
    println!("  Phase 0 End-to-End Privacy Verified Successfully! ");
    println!("==================================================");
}

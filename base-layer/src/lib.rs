pub mod assets;
pub mod note;
pub mod tree;
pub mod ledger;
pub mod wallet;

#[cfg(test)]
mod tests {
    use super::*;
    use assets::AssetId;
    use ledger::Ledger;
    use note::Note;
    use wallet::Wallet;

    #[test]
    fn test_phase0_end_to_end_privacy_flow() {
        let mut ledger = Ledger::new();

        let mut alice = Wallet::new([1u8; 32]);
        let mut bob = Wallet::new([2u8; 32]);

        ledger.set_balance(alice.pubkey, 1000);
        assert_eq!(ledger.get_balance(&alice.pubkey), 1000);

        let (shield_tx, alice_initial_note) = alice.create_shield(1000, [10u8; 32]);
        assert_eq!(ledger.apply(shield_tx), Ok(()));
        assert_eq!(ledger.get_balance(&alice.pubkey), 0);
        alice.add_note(alice_initial_note, 0);
        assert_eq!(alice.total_private_balance(), 1000);

        let root = ledger.tree.get_last_root();
        let (transfer_tx, bob_note, alice_change_note) = alice
            .create_private_transfer(600, bob.pubkey, [20u8; 32], [30u8; 32], root)
            .expect("Transfer creation failed");

        let replay_tx = transfer_tx.clone();
        assert_eq!(ledger.apply(transfer_tx), Ok(()));
        assert_eq!(ledger.tree.next_leaf_index, 3);

        bob.add_note(bob_note, 1);
        alice.add_note(alice_change_note.unwrap(), 2);

        assert_eq!(alice.total_private_balance(), 400);
        assert_eq!(bob.total_private_balance(), 600);

        assert_eq!(
            ledger.apply(replay_tx),
            Err("Double-spend detected: nullifier already spent")
        );

        let bob_transparent_addr = [99u8; 32];
        let root_after_transfer = ledger.tree.get_last_root();
        let unshield_tx = bob
            .create_unshield(600, bob_transparent_addr, root_after_transfer)
            .expect("Unshield creation failed");

        let replay_unshield = unshield_tx.clone();
        assert_eq!(ledger.apply(unshield_tx), Ok(()));
        assert_eq!(ledger.get_balance(&bob_transparent_addr), 600);
        assert_eq!(bob.total_private_balance(), 0);

        assert_eq!(
            ledger.apply(replay_unshield),
            Err("Double-spend detected: nullifier already spent")
        );
    }

    #[test]
    fn test_native_xmr_shared_anonymity_pool_and_view_key_memo() {
        let mut ledger = Ledger::new();
        let mut alice = Wallet::new([7u8; 32]);
        let mut bob = Wallet::new([8u8; 32]);

        // Fund Alice with 50 XMR and 500 SER in the same ledger
        ledger.set_asset_balance(alice.pubkey, AssetId::Xmr, 50);
        ledger.set_asset_balance(alice.pubkey, AssetId::Seraph, 500);

        // Shield both SER and XMR into the same shared Merkle tree
        let (ser_shield, ser_note) = alice.create_asset_shield(AssetId::Seraph, 500, [11u8; 32]);
        let (xmr_shield, xmr_note) = alice.create_asset_shield(AssetId::Xmr, 50, [12u8; 32]);

        assert_eq!(ledger.apply(ser_shield), Ok(()));
        alice.add_note(ser_note, 0);
        assert_eq!(ledger.apply(xmr_shield), Ok(()));
        alice.add_note(xmr_note, 1);

        // Transfer 20 XMR privately to Bob
        let root = ledger.tree.get_last_root();
        let (xmr_tx, bob_xmr, alice_xmr_change) = alice
            .create_asset_private_transfer(AssetId::Xmr, 20, bob.pubkey, [21u8; 32], [22u8; 32], root)
            .expect("XMR private transfer failed");

        assert_eq!(ledger.apply(xmr_tx), Ok(()));
        bob.add_note(bob_xmr, 2);
        alice.add_note(alice_xmr_change.unwrap(), 3);

        assert_eq!(alice.private_balance_of(AssetId::Xmr), 30);
        assert_eq!(bob.private_balance_of(AssetId::Xmr), 20);
        assert_eq!(alice.private_balance_of(AssetId::Seraph), 500);

        // Test view-key memo encryption/decryption
        let memo_plain = b"Invoice #1042 settled in XMR";
        let cipher = Note::xor_memo(&bob.view_key, &[21u8; 32], memo_plain);
        assert_ne!(&cipher[..], &memo_plain[..]);
        let decrypted = Note::xor_memo(&bob.view_key, &[21u8; 32], &cipher);
        assert_eq!(&decrypted[..], &memo_plain[..]);
    }
}

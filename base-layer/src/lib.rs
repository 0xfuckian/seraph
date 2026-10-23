pub mod note;
pub mod tree;
pub mod ledger;
pub mod wallet;

#[cfg(test)]
mod tests {
    use super::*;
    use ledger::Ledger;
    use wallet::Wallet;

    #[test]
    fn test_phase0_end_to_end_privacy_flow() {
        let mut ledger = Ledger::new();

        // 1. Setup Alice and Bob wallets
        let alice_spend_key = [1u8; 32];
        let bob_spend_key = [2u8; 32];

        let mut alice = Wallet::new(alice_spend_key);
        let mut bob = Wallet::new(bob_spend_key);

        // 2. Fund Alice's transparent balance with 1,000 SER
        ledger.set_balance(alice.pubkey, 1000);
        assert_eq!(ledger.get_balance(&alice.pubkey), 1000);

        // 3. Alice SHIELDS 1,000 SER into the private pool
        let (shield_tx, alice_initial_note) = alice.create_shield(1000, [10u8; 32]);
        assert_eq!(ledger.apply(shield_tx), Ok(()));
        assert_eq!(ledger.get_balance(&alice.pubkey), 0);
        alice.add_note(alice_initial_note, 0); // leaf_index 0 in tree
        assert_eq!(alice.total_private_balance(), 1000);

        // 4. Alice executes a PRIVATE TRANSFER of 600 SER to Bob (400 SER change to Alice)
        let root = ledger.tree.get_last_root();
        let (transfer_tx, bob_note, alice_change_note) = alice
            .create_private_transfer(600, bob.pubkey, [20u8; 32], [30u8; 32], root)
            .expect("Transfer creation failed");

        // Clone transfer_tx for double-spend testing later
        let replay_tx = transfer_tx.clone();

        // Apply private transfer to ledger
        assert_eq!(ledger.apply(transfer_tx), Ok(()));

        // Ledger leaf count is now 3 (1 initial + 2 outputs)
        assert_eq!(ledger.tree.next_leaf_index, 3);

        // Update wallets
        bob.add_note(bob_note, 1); // leaf_index 1
        alice.add_note(alice_change_note.unwrap(), 2); // leaf_index 2

        assert_eq!(alice.total_private_balance(), 400);
        assert_eq!(bob.total_private_balance(), 600);

        // 5. DOUBLE SPEND ATTEMPT: Replaying Alice's transfer must fail
        assert_eq!(
            ledger.apply(replay_tx),
            Err("Double-spend detected: nullifier already spent")
        );

        // 6. Bob UNSHIELDS his 600 SER to a transparent address
        let bob_transparent_addr = [99u8; 32];
        let root_after_transfer = ledger.tree.get_last_root();
        let unshield_tx = bob
            .create_unshield(600, bob_transparent_addr, root_after_transfer)
            .expect("Unshield creation failed");

        let replay_unshield = unshield_tx.clone();
        assert_eq!(ledger.apply(unshield_tx), Ok(()));

        // Bob's transparent balance is now 600 SER
        assert_eq!(ledger.get_balance(&bob_transparent_addr), 600);
        assert_eq!(bob.total_private_balance(), 0);

        // Replaying unshield must fail
        assert_eq!(
            ledger.apply(replay_unshield),
            Err("Double-spend detected: nullifier already spent")
        );
    }
}

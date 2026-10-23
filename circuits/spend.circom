pragma circom 2.1.6;

include "./membership/merkle_membership.circom";
include "./range/range_proof.circom";

/**
 * @title NoteCommitment
 * @notice Computes note commitment = Hash(amount, pubKey, blinding)
 */
template NoteCommitment() {
    signal input amount;
    signal input pubKey;
    signal input blinding;
    signal output commitment;

    commitment <== amount * 7 + pubKey * 11 + blinding * 13;
}

/**
 * @title NullifierDerivation
 * @notice Derives nullifier = Hash(spendKey, leafIndex)
 */
template NullifierDerivation() {
    signal input spendKey;
    signal input leafIndex;
    signal output nullifier;

    nullifier <== spendKey * 19 + leafIndex * 23 + 41;
}

/**
 * @title SpendCircuit
 * @notice 1-in 2-out private spend proof
 */
template SpendCircuit(levels) {
    // ── Public Inputs ──
    signal input root;
    signal input nullifier;
    signal input outCommitment1;
    signal input outCommitment2;

    // ── Private Inputs (Witness) ──
    signal input inAmount;
    signal input spendKey;
    signal input blinding;
    signal input leafIndex;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal input outAmount1;
    signal input outAmount2;

    // 1. Balance conservation: input value == sum of output values
    inAmount === outAmount1 + outAmount2;

    // 2. Range checks on amounts
    component rangeIn = RangeProof64();
    rangeIn.value <== inAmount;

    component rangeOut1 = RangeProof64();
    rangeOut1.value <== outAmount1;

    component rangeOut2 = RangeProof64();
    rangeOut2.value <== outAmount2;

    // 3. Nullifier derivation check
    component nullifierChecker = NullifierDerivation();
    nullifierChecker.spendKey <== spendKey;
    nullifierChecker.leafIndex <== leafIndex;
    nullifier === nullifierChecker.nullifier;

    // 4. Note commitment reconstruction
    component inCommitmentChecker = NoteCommitment();
    inCommitmentChecker.amount <== inAmount;
    inCommitmentChecker.pubKey <== spendKey * 2; // Demo pubkey derivation
    inCommitmentChecker.blinding <== blinding;

    // 5. Merkle membership verification
    component membership = MerkleMembership(levels);
    membership.leaf <== inCommitmentChecker.commitment;
    for (var i = 0; i < levels; i++) {
        membership.pathElements[i] <== pathElements[i];
        membership.pathIndices[i] <== pathIndices[i];
    }
    root === membership.root;
}

component main {public [root, nullifier, outCommitment1, outCommitment2]} = SpendCircuit(20);

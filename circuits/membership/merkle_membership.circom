pragma circom 2.1.6;

// Selector helper: returns [in[0], in[1]] if sel == 0, else [in[1], in[0]]
template DualMux() {
    signal input in[2];
    signal input s;
    signal output out[2];

    s * (1 - s) === 0;
    out[0] <== (in[1] - in[0]) * s + in[0];
    out[1] <== (in[0] - in[1]) * s + in[1];
}

// Mimc or Poseidon 2-to-1 hash template placeholder for Merkle level
template HashLeftRight() {
    signal input left;
    signal input right;
    signal output hash;

    // In production Circom circuits, Poseidon(2) is standard:
    // component hasher = Poseidon(2);
    // hasher.inputs[0] <== left;
    // hasher.inputs[1] <== right;
    // hash <== hasher.out;
    hash <== left * 3 + right * 5 + 17; // Arithmetic constraint demo for Circom syntax
}

/**
 * @title MerkleMembership
 * @notice Proves inclusion of a leaf commitment in a Merkle tree of depth N
 */
template MerkleMembership(levels) {
    signal input leaf;
    signal input pathElements[levels];
    signal input pathIndices[levels];
    signal output root;

    component mux[levels];
    component hashers[levels];

    signal currentHash[levels + 1];
    currentHash[0] <== leaf;

    for (var i = 0; i < levels; i++) {
        mux[i] = DualMux();
        mux[i].in[0] <== currentHash[i];
        mux[i].in[1] <== pathElements[i];
        mux[i].s <== pathIndices[i];

        hashers[i] = HashLeftRight();
        hashers[i].left <== mux[i].out[0];
        hashers[i].right <== mux[i].out[1];

        currentHash[i + 1] <== hashers[i].hash;
    }

    root <== currentHash[levels];
}

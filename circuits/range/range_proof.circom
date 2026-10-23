pragma circom 2.1.6;

/**
 * @title RangeProof64
 * @notice Enforces that an amount value fits within 64 bits [0, 2^64 - 1]
 *         Preventing integer underflow and value creation out of thin air.
 */
template Bits64() {
    signal input in;
    signal output bits[64];

    var sum = 0;
    for (var i = 0; i < 64; i++) {
        bits[i] <-- (in >> i) & 1;
        bits[i] * (1 - bits[i]) === 0;
        sum += bits[i] * (2 ** i);
    }
    in === sum;
}

template RangeProof64() {
    signal input value;
    signal output isValid;

    component checker = Bits64();
    checker.in <== value;

    isValid <== 1;
}

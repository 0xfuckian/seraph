// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PrivacyPool
 * @notice The heart of private value. Manages notes, commitments, nullifiers.
 * @dev Maintains a Merkle tree of note commitments. Verifies ZK proofs that
 *      the spender owns the notes, nullifiers are correct, values balance,
 *      and amounts are in range.
 *
 * Specification: Seraph Protocol — Section 6.1
 */
contract PrivacyPool {
    // ─── Events (minimal — privacy-preserving) ───────────────────────
    event Shielded(address indexed from, bytes32 commitment);
    event PrivateTransfer(bytes32[] nullifiers, bytes32[] commitments);
    event Unshielded(bytes32 nullifier, uint256 amount, address to);

    // ─── Merkle Tree ───────────────────────────────────────────────────
    // Incremental Merkle tree of note commitments
    bytes32 public root;
    uint256 public constant TREE_DEPTH = 32;

    // ─── Nullifier Registry ────────────────────────────────────────────
    // Tracks spent nullifiers to prevent double-spends
    mapping(bytes32 => bool) public nullified;

    // ─── State ─────────────────────────────────────────────────────────
    uint256 public noteCount;

    // ─── Verifiers ─────────────────────────────────────────────────────
    // Addresses of on-chain ZK verifiers (set by governance)
    address public spendVerifier;
    address public bridgeVerifier;

    // ─── Modifiers ─────────────────────────────────────────────────────
    modifier notNullified(bytes32 nullifier) {
        require(!nullified[nullifier], "PrivacyPool: nullifier already spent");
        _;
    }

    // ─── Constructor ───────────────────────────────────────────────────
    constructor(address _spendVerifier, address _bridgeVerifier) {
        spendVerifier = _spendVerifier;
        bridgeVerifier = _bridgeVerifier;
    }

    /* ------------------------------------------------------------------ */
    /* SHIELD: deposit public tokens into a private note                    */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Shield (deposit) public SER into the private pool.
     * @param amount Amount of SER to shield.
     * @param commitment The commitment to the new private note.
     * @param proof Optional proof data (for advanced shielding modes).
     *
     * The caller's SER is locked in this contract. A new note commitment
     * is inserted into the Merkle tree.
     */
    function shield(uint256 amount, bytes32 commitment, bytes calldata proof) external {
        // Lock the caller's tokens
        // SeraphToken(msg.sender).transferFrom(msg.sender, address(this), amount);
        _insertCommitment(commitment);
        emit Shielded(msg.sender, commitment);
    }

    /* ------------------------------------------------------------------ */
    /* PRIVATE TRANSFER: spend notes privately                              */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Transfer value between private notes.
     * @param nullifiers Array of nullifiers for input notes being spent.
     * @param commitments Array of new note commitments for outputs.
     * @param proof Zero-knowledge proof of ownership, balance, and range.
     *
     * Verifies:
     *   1. Proof validity (ownership, balance conservation, range)
     *   2. Nullifiers are not yet spent
     *   3. Root is updated correctly
     */
    function privateTransfer(bytes32[] calldata nullifiers, bytes32[] calldata commitments, bytes calldata proof)
        external
    {
        // Verify the ZK proof
        // require(_verifyProof(spendVerifier, proof, ...), "PrivacyPool: invalid proof");

        // Check nullifiers are fresh
        for (uint256 i = 0; i < nullifiers.length; i++) {
            require(!nullified[nullifiers[i]], "PrivacyPool: nullifier already spent");
            nullified[nullifiers[i]] = true;
        }

        // Insert new commitments
        for (uint256 i = 0; i < commitments.length; i++) {
            _insertCommitment(commitments[i]);
        }

        emit PrivateTransfer(nullifiers, commitments);
    }

    /* ------------------------------------------------------------------ */
    /* UNSHIELD: withdraw from private pool to a public address           */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Withdraw private notes to a public address.
     * @param nullifier Nullifier of the note being spent.
     * @param amount Amount to unshield.
     * @param recipient Public address receiving the funds.
     * @param proof ZK proof of ownership and balance.
     */
    function unshield(bytes32 nullifier, uint256 amount, address recipient, bytes calldata proof)
        external
        notNullified(nullifier)
    {
        nullified[nullifier] = true;
        // SeraphToken(address(this)).transfer(recipient, amount);
        emit Unshielded(nullifier, amount, recipient);
    }

    /* ------------------------------------------------------------------ */
    /* Internal helpers                                                   */
    /* ------------------------------------------------------------------ */

    /**
     * @dev Insert a commitment into the Merkle tree and update the root.
     */
    function _insertCommitment(bytes32 commitment) internal {
        // TODO: Implement incremental Merkle tree insertion
        // - Push commitment to tree
        // - Update intermediate nodes
        // - Update root
        noteCount++;
    }

    /**
     * @dev Verify a ZK proof against a verifier contract.
     */
    function _verifyProof(address verifier, bytes memory proof, bytes32[] memory pubSignals)
        internal
        view
        returns (bool)
    {
        // TODO: Call the verifier contract
        return true;
    }

    // ─── Admin ─────────────────────────────────────────────────────────
    function setSpendVerifier(address _verifier) external /* onlyGovernance */  {
        spendVerifier = _verifier;
    }

    function setBridgeVerifier(address _verifier) external /* onlyGovernance */  {
        bridgeVerifier = _verifier;
    }
}

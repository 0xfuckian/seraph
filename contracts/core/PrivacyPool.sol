// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PrivacyPool
 * @notice Core privacy pool for Seraph Protocol (Continuum Levels 1 & 2).
 * @dev Maintains an Incremental Merkle Tree of note commitments, tracks
 *      spent nullifiers to prevent double-spending, and handles shielding
 *      (deposits) and unshielding (withdrawals) of SER tokens.
 *
 * Specification: Seraph Protocol — Section 3.1 & 6.1
 */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IVerifier {
    function verifyProof(bytes calldata proof, uint256[] calldata pubSignals) external view returns (bool);
}

contract PrivacyPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Events ────────────────────────────────────────────────────────
    event Shielded(address indexed from, bytes32 indexed commitment, uint256 amount, uint32 leafIndex);
    event PrivateTransfer(bytes32[] nullifiers, bytes32[] commitments);
    event Unshielded(bytes32 indexed nullifier, uint256 amount, address indexed recipient);
    event VerifierUpdated(address indexed verifier, bool isSpend);
    event TreasuryUpdated(address indexed newTreasury);
    event Paused(address account);
    event Unpaused(address account);

    // ─── Constants & Immutables ─────────────────────────────────────────
    IERC20 public immutable token;
    address public treasury;

    uint32 public constant TREE_DEPTH = 20; // 2^20 = 1,048,576 notes capacity
    uint32 public constant ROOT_HISTORY_SIZE = 100; // Ring buffer for recent valid roots

    // ─── Merkle Tree State ──────────────────────────────────────────────
    uint32 public nextLeafIndex;
    bytes32[TREE_DEPTH] public filledSubtrees;
    bytes32[ROOT_HISTORY_SIZE] public roots;
    uint32 public currentRootIndex;
    bytes32[TREE_DEPTH] public zeros;

    // ─── Nullifier Registry ─────────────────────────────────────────────
    mapping(bytes32 => bool) public nullified;

    // ─── Verifiers ──────────────────────────────────────────────────────
    address public spendVerifier;
    address public bridgeVerifier;
    bool public paused;

    // ─── Modifiers ──────────────────────────────────────────────────────
    modifier onlyTreasury() {
        require(msg.sender == treasury, "PrivacyPool: not treasury");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "PrivacyPool: paused");
        _;
    }

    function setPaused(bool _paused) external onlyTreasury {
        paused = _paused;
        if (_paused) emit Paused(msg.sender);
        else emit Unpaused(msg.sender);
    }

    constructor(address _token, address _treasury, address _spendVerifier, address _bridgeVerifier) {
        token = IERC20(_token);
        treasury = _treasury;
        spendVerifier = _spendVerifier;
        bridgeVerifier = _bridgeVerifier;

        // Precompute zero hashes for each tree level
        bytes32 currentZero = keccak256("seraph_privacy_zero");
        zeros[0] = currentZero;
        filledSubtrees[0] = currentZero;

        for (uint32 i = 1; i < TREE_DEPTH; i++) {
            currentZero = _hashPair(currentZero, currentZero);
            zeros[i] = currentZero;
            filledSubtrees[i] = currentZero;
        }

        // Initial root is the top level zero hash
        bytes32 initialRoot = _hashPair(currentZero, currentZero);
        roots[0] = initialRoot;
    }

    /* ------------------------------------------------------------------ */
    /* SHIELD: deposit public tokens into a private note                  */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Shield (deposit) public SER into the private pool.
     * @param amount Amount of SER to shield.
     * @param commitment The commitment to the new private note.
     * @param proof Optional proof data (for advanced shielding modes).
     */
    function shield(uint256 amount, bytes32 commitment, bytes calldata proof) external returns (uint32 leafIndex) {
        return shieldFor(msg.sender, amount, commitment, proof);
    }

    /**
     * @notice Shield tokens on behalf of a specific depositor.
     */
    function shieldFor(address depositor, uint256 amount, bytes32 commitment, bytes calldata proof)
        public
        nonReentrant
        whenNotPaused
        returns (uint32 leafIndex)
    {
        proof; // Silences compiler warning for optional advanced shielding
        require(amount > 0, "PrivacyPool: amount must be > 0");
        require(commitment != bytes32(0), "PrivacyPool: invalid commitment");

        // Lock depositor's tokens in the privacy pool
        token.safeTransferFrom(depositor, address(this), amount);

        // Insert into the incremental Merkle tree
        leafIndex = _insertCommitment(commitment);

        emit Shielded(depositor, commitment, amount, leafIndex);
    }

    /* ------------------------------------------------------------------ */
    /* PRIVATE TRANSFER: spend notes privately                            */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Transfer value between private notes.
     * @param nullifiers Array of nullifiers for input notes being spent.
     * @param commitments Array of new note commitments for outputs.
     * @param root Historic Merkle root being proven against.
     * @param proof Zero-knowledge proof of ownership, balance, and range.
     */
    function privateTransfer(
        bytes32[] calldata nullifiers,
        bytes32[] calldata commitments,
        bytes32 root,
        bytes calldata proof
    ) external nonReentrant whenNotPaused {
        require(nullifiers.length > 0, "PrivacyPool: no nullifiers");
        require(commitments.length > 0, "PrivacyPool: no commitments");
        require(isKnownRoot(root), "PrivacyPool: unknown or expired root");

        // Fail-fast sanity checks on input nullifiers & commitments
        for (uint256 i = 0; i < nullifiers.length; i++) {
            bytes32 nullifier = nullifiers[i];
            require(nullifier != bytes32(0), "PrivacyPool: invalid nullifier");
            require(!nullified[nullifier], "PrivacyPool: nullifier already spent");
            nullified[nullifier] = true;
        }

        for (uint256 i = 0; i < commitments.length; i++) {
            require(commitments[i] != bytes32(0), "PrivacyPool: invalid commitment");
        }

        // Mandatory ZK proof verification: spendVerifier cannot be bypassed
        require(spendVerifier != address(0), "PrivacyPool: spend verifier not configured");
        require(_verifySpendProof(root, nullifiers, commitments, proof), "PrivacyPool: invalid proof");

        // Insert new note commitments into Merkle tree
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
     * @param root Historic Merkle root being proven against.
     * @param proof ZK proof of ownership and balance.
     */
    function unshield(bytes32 nullifier, uint256 amount, address recipient, bytes32 root, bytes calldata proof)
        external
        nonReentrant
        whenNotPaused
    {
        require(amount > 0, "PrivacyPool: amount must be > 0");
        require(recipient != address(0), "PrivacyPool: recipient is zero");
        require(nullifier != bytes32(0), "PrivacyPool: invalid nullifier");
        require(!nullified[nullifier], "PrivacyPool: nullifier already spent");
        require(isKnownRoot(root), "PrivacyPool: unknown or expired root");

        // Mandatory ZK proof verification: spendVerifier cannot be bypassed
        require(spendVerifier != address(0), "PrivacyPool: spend verifier not configured");
        require(_verifyUnshieldProof(root, nullifier, amount, recipient, proof), "PrivacyPool: invalid proof");

        nullified[nullifier] = true;

        // Release tokens from the privacy pool to recipient
        token.safeTransfer(recipient, amount);

        emit Unshielded(nullifier, amount, recipient);
    }

    /* ------------------------------------------------------------------ */
    /* Internal Tree Helpers                                              */
    /* ------------------------------------------------------------------ */

    /**
     * @dev Canonical sorted-pair hashing for deterministic Merkle tree.
     */
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /**
     * @dev Insert a commitment into the incremental Merkle tree and update root.
     */
    function _insertCommitment(bytes32 commitment) internal returns (uint32 leafIndex) {
        require(nextLeafIndex < 2 ** TREE_DEPTH, "PrivacyPool: tree is full");
        leafIndex = nextLeafIndex;
        uint32 currentIndex = leafIndex;
        bytes32 currentHash = commitment;

        for (uint32 i = 0; i < TREE_DEPTH; i++) {
            if (currentIndex % 2 == 0) {
                filledSubtrees[i] = currentHash;
                currentHash = _hashPair(currentHash, zeros[i]);
            } else {
                currentHash = _hashPair(filledSubtrees[i], currentHash);
            }
            currentIndex /= 2;
        }

        currentRootIndex = (currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        roots[currentRootIndex] = currentHash;
        nextLeafIndex = leafIndex + 1;
    }

    /**
     * @dev Check if a given root is currently in the recent valid root ring buffer.
     */
    function isKnownRoot(bytes32 _root) public view returns (bool) {
        if (_root == bytes32(0)) return false;
        uint32 i = currentRootIndex;
        for (uint32 count = 0; count < ROOT_HISTORY_SIZE; count++) {
            if (roots[i] == _root) return true;
            if (i == 0) i = ROOT_HISTORY_SIZE;
            i--;
        }
        return false;
    }

    /**
     * @notice Get the latest Merkle root of the commitment tree.
     */
    function getLastRoot() external view returns (bytes32) {
        return roots[currentRootIndex];
    }

    /**
     * @dev Verify spend proof against IVerifier.
     */
    function _verifySpendProof(
        bytes32 root,
        bytes32[] calldata nullifiers,
        bytes32[] calldata commitments,
        bytes calldata proof
    ) internal view returns (bool) {
        uint256[] memory pubSignals = new uint256[](1 + nullifiers.length + commitments.length);
        pubSignals[0] = uint256(root);
        for (uint256 i = 0; i < nullifiers.length; i++) {
            pubSignals[1 + i] = uint256(nullifiers[i]);
        }
        for (uint256 j = 0; j < commitments.length; j++) {
            pubSignals[1 + nullifiers.length + j] = uint256(commitments[j]);
        }
        return IVerifier(spendVerifier).verifyProof(proof, pubSignals);
    }

    /**
     * @dev Verify unshield proof against IVerifier.
     */
    function _verifyUnshieldProof(
        bytes32 root,
        bytes32 nullifier,
        uint256 amount,
        address recipient,
        bytes calldata proof
    ) internal view returns (bool) {
        uint256[] memory pubSignals = new uint256[](4);
        pubSignals[0] = uint256(root);
        pubSignals[1] = uint256(nullifier);
        pubSignals[2] = amount;
        pubSignals[3] = uint256(uint160(recipient));
        return IVerifier(spendVerifier).verifyProof(proof, pubSignals);
    }

    // ─── Admin ─────────────────────────────────────────────────────────
    address public pendingTreasury;
    event TreasuryTransferStarted(address indexed previousTreasury, address indexed newTreasury);

    function setSpendVerifier(address _verifier) external onlyTreasury {
        require(_verifier != address(0), "PrivacyPool: zero verifier not allowed");
        spendVerifier = _verifier;
        emit VerifierUpdated(_verifier, true);
    }

    function setBridgeVerifier(address _verifier) external onlyTreasury {
        require(_verifier != address(0), "PrivacyPool: zero verifier not allowed");
        bridgeVerifier = _verifier;
        emit VerifierUpdated(_verifier, false);
    }

    function setTreasury(address _treasury) external onlyTreasury {
        require(_treasury != address(0), "PrivacyPool: zero address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function transferTreasury(address _newTreasury) external onlyTreasury {
        require(_newTreasury != address(0), "PrivacyPool: zero address");
        pendingTreasury = _newTreasury;
        emit TreasuryTransferStarted(treasury, _newTreasury);
    }

    function acceptTreasury() external {
        require(msg.sender == pendingTreasury, "PrivacyPool: not pending treasury");
        treasury = pendingTreasury;
        pendingTreasury = address(0);
        emit TreasuryUpdated(treasury);
    }
}

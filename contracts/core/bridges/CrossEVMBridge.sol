// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMintableBurnableERC20 is IERC20 {
    function lockForBridge(address to, uint256 amount, bytes32 chainId) external;
    function receiveFromBridge(address to, uint256 amount) external;
}

/**
 * @title CrossEVMBridge
 * @notice Trust-minimized bridge connecting Seraph Base Layer, Seraph EVM, and XMR EVM.
 *         Uses bonded relayers, a fraud-proof challenge window on state roots, and
 *         nullifier-tagged message hashes to prevent cross-chain double-spends.
 */
contract CrossEVMBridge is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MIN_RELAYER_BOND = 1 ether;
    uint256 public constant CHALLENGE_WINDOW = 1 hours;

    struct StateBatch {
        bytes32 sourceChainId;
        bytes32 stateRoot;
        address relayer;
        uint64 submittedAt;
        bool challenged;
    }

    address public immutable token;
    address public guardian;
    bytes32 public immutable localChainId;

    mapping(address => uint256) public relayerBonds;
    mapping(address => uint64) public lastBatchSubmittedAt;
    mapping(uint256 => StateBatch) public batches;
    uint256 public nextBatchId;

    mapping(bytes32 => bool) public processedNullifiers;
    uint256 public outboundNonce;
    bool public paused;

    event RelayerBonded(address indexed relayer, uint256 totalBond);
    event RelayerUnbonded(address indexed relayer, uint256 amount, uint256 remainingBond);
    event BatchSubmitted(
        uint256 indexed batchId, bytes32 indexed sourceChainId, bytes32 stateRoot, address indexed relayer
    );
    event BatchChallenged(uint256 indexed batchId, address indexed challenger, address indexed slashedRelayer);
    event TokensLocked(
        uint256 indexed nonce, address indexed sender, address indexed recipient, uint256 amount, bytes32 destChainId
    );
    event TokensClaimed(uint256 indexed batchId, bytes32 indexed nullifier, address indexed recipient, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    error InsufficientBond();
    error Unauthorized();
    error InvalidBatch();
    error ChallengeWindowActive();
    error NullifierAlreadyUsed();
    error InvalidMerkleProof();
    error BridgePaused();

    modifier whenNotPaused() {
        if (paused) revert BridgePaused();
        _;
    }

    function setPaused(bool _paused) external {
        if (msg.sender != guardian) revert Unauthorized();
        paused = _paused;
        if (_paused) emit Paused(msg.sender);
        else emit Unpaused(msg.sender);
    }

    constructor(address _token, bytes32 _localChainId, address _guardian) {
        require(_token != address(0) && _guardian != address(0), "CrossEVMBridge: zero address");
        token = _token;
        localChainId = _localChainId;
        guardian = _guardian;
    }

    function bondRelayer() external payable {
        relayerBonds[msg.sender] += msg.value;
        if (relayerBonds[msg.sender] < MIN_RELAYER_BOND) revert InsufficientBond();
        emit RelayerBonded(msg.sender, relayerBonds[msg.sender]);
    }

    /**
     * @notice Withdraw relayer bond once all submitted batches have passed the challenge window.
     */
    function unbondRelayer(uint256 amount) external nonReentrant {
        if (amount == 0 || relayerBonds[msg.sender] < amount) revert InsufficientBond();
        uint64 lastSub = lastBatchSubmittedAt[msg.sender];
        if (lastSub > 0 && block.timestamp < uint256(lastSub) + CHALLENGE_WINDOW) {
            revert ChallengeWindowActive();
        }
        relayerBonds[msg.sender] -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "CrossEVMBridge: unbond transfer failed");
        emit RelayerUnbonded(msg.sender, amount, relayerBonds[msg.sender]);
    }

    function submitStateBatch(bytes32 sourceChainId, bytes32 stateRoot)
        external
        whenNotPaused
        returns (uint256 batchId)
    {
        if (relayerBonds[msg.sender] < MIN_RELAYER_BOND) revert InsufficientBond();
        if (sourceChainId == bytes32(0) || sourceChainId == localChainId || stateRoot == bytes32(0)) {
            revert InvalidBatch();
        }

        lastBatchSubmittedAt[msg.sender] = uint64(block.timestamp);
        batchId = nextBatchId++;
        batches[batchId] = StateBatch({
            sourceChainId: sourceChainId,
            stateRoot: stateRoot,
            relayer: msg.sender,
            submittedAt: uint64(block.timestamp),
            challenged: false
        });
        emit BatchSubmitted(batchId, sourceChainId, stateRoot, msg.sender);
    }

    /**
     * @notice Slashes a fraudulent batch and rewards the challenger.
     */
    function challengeBatch(uint256 batchId, address challenger) external nonReentrant {
        if (msg.sender != guardian) revert Unauthorized();
        if (challenger == address(0)) revert InvalidBatch();
        StateBatch storage b = batches[batchId];
        if (b.stateRoot == bytes32(0) || b.challenged) revert InvalidBatch();

        b.challenged = true;
        uint256 slashed = relayerBonds[b.relayer];
        relayerBonds[b.relayer] = 0;

        if (slashed > 0) {
            (bool ok,) = challenger.call{value: slashed}("");
            require(ok, "CrossEVMBridge: reward transfer failed");
        }
        emit BatchChallenged(batchId, challenger, b.relayer);
    }

    /**
     * @notice Lock tokens on the current chain to bridge to `destChainId`.
     */
    function bridgeOut(address recipient, uint256 amount, bytes32 destChainId)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 nonce)
    {
        require(
            recipient != address(0) && amount > 0 && destChainId != bytes32(0) && destChainId != localChainId,
            "CrossEVMBridge: invalid bridge params"
        );
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        nonce = outboundNonce++;
        emit TokensLocked(nonce, msg.sender, recipient, amount, destChainId);
    }

    /**
     * @notice Claim bridged tokens once the challenge window for `batchId` has passed.
     */
    function claimBridged(
        uint256 batchId,
        bytes32 nullifier,
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant whenNotPaused {
        StateBatch storage b = batches[batchId];
        if (b.stateRoot == bytes32(0) || b.challenged) revert InvalidBatch();
        if (recipient == address(0) || amount == 0 || nullifier == bytes32(0)) revert InvalidBatch();
        if (block.timestamp < b.submittedAt + CHALLENGE_WINDOW) revert ChallengeWindowActive();
        if (processedNullifiers[nullifier]) revert NullifierAlreadyUsed();

        bytes32 leaf = keccak256(abi.encodePacked(nullifier, recipient, amount, localChainId));
        if (!_verifyProof(merkleProof, b.stateRoot, leaf)) revert InvalidMerkleProof();

        processedNullifiers[nullifier] = true;
        IMintableBurnableERC20(token).receiveFromBridge(recipient, amount);
        emit TokensClaimed(batchId, nullifier, recipient, amount);
    }

    function _verifyProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 el = proof[i];
            computed =
                computed <= el ? keccak256(abi.encodePacked(computed, el)) : keccak256(abi.encodePacked(el, computed));
        }
        return computed == root;
    }
}

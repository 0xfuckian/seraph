// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GasRelayer
 * @notice Gas abstraction relayer for Seraph EVM and XMR EVM (Whitepaper Section 5).
 *         Allows users to pay execution fees in SERAPH or wXMR while bonded relayers
 *         submit the transaction on-chain without linking the user's gas funding source.
 */
contract GasRelayer is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable seraphToken;
    address public immutable xmrToken;
    address public owner;

    // Rate of fee token units per 1 wei of native gas (scaled by 1e18)
    mapping(address => uint256) public tokenGasRate;
    mapping(address => uint256) public voucherPoolBalance;
    mapping(bytes32 => bool) public usedVouchers;
    mapping(bytes32 => bool) public voucherCommitments;

    event RelayedCall(
        bytes32 indexed voucherNullifier,
        address indexed target,
        address indexed relayer,
        address feeToken,
        uint256 feePaid
    );

    error UnsupportedFeeToken();
    error VoucherAlreadyUsed();
    error CommitmentAlreadyExists();
    error InsufficientVoucherPool();
    error ForbiddenTarget();
    error TargetCallFailed();
    error Unauthorized();

    constructor(address _seraphToken, address _xmrToken, uint256 _serRate, uint256 _xmrRate) {
        owner = msg.sender;
        seraphToken = _seraphToken;
        xmrToken = _xmrToken;
        tokenGasRate[_seraphToken] = _serRate;
        tokenGasRate[_xmrToken] = _xmrRate;
    }

    function setTokenGasRate(address feeToken, uint256 rate) external {
        if (msg.sender != owner) revert Unauthorized();
        tokenGasRate[feeToken] = rate;
    }

    /**
     * @notice Deposit fee tokens (SER or wXMR) into the relayer pool backed by a voucher commitment.
     */
    function fundGasVoucher(address feeToken, uint256 amount, bytes32 voucherCommitment) external nonReentrant {
        if (tokenGasRate[feeToken] == 0) revert UnsupportedFeeToken();
        require(voucherCommitment != bytes32(0) && amount > 0, "GasRelayer: invalid voucher");
        if (voucherCommitments[voucherCommitment]) revert CommitmentAlreadyExists();
        voucherCommitments[voucherCommitment] = true;
        voucherPoolBalance[feeToken] += amount;
        IERC20(feeToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Execute an arbitrary call on `target` and compensate `msg.sender` (relayer) in `feeToken`.
     */
    function executeWithGasAbstraction(
        bytes32 voucherNullifier,
        address feeToken,
        uint256 feeAmount,
        address target,
        bytes calldata data
    ) external nonReentrant returns (bytes memory result) {
        if (tokenGasRate[feeToken] == 0) revert UnsupportedFeeToken();
        if (voucherNullifier == bytes32(0) || usedVouchers[voucherNullifier]) revert VoucherAlreadyUsed();
        if (
            target == address(0) ||
            target == address(this) ||
            target == seraphToken ||
            target == xmrToken ||
            tokenGasRate[target] != 0
        ) revert ForbiddenTarget();
        if (feeAmount > voucherPoolBalance[feeToken]) revert InsufficientVoucherPool();

        usedVouchers[voucherNullifier] = true;
        if (feeAmount > 0) {
            voucherPoolBalance[feeToken] -= feeAmount;
        }

        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) revert TargetCallFailed();

        if (feeAmount > 0) {
            IERC20(feeToken).safeTransfer(msg.sender, feeAmount);
        }

        emit RelayedCall(voucherNullifier, target, msg.sender, feeToken, feeAmount);
        return ret;
    }
}

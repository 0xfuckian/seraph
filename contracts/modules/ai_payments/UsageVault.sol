// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title UsageVault
 * @notice First-party Seraph module for AI Agent Payment Rails (Whitepaper Section 7).
 *         Enables unlinkable, metered micro-payments where users lock deposit commitments
 *         and AI providers redeem compute credits via nullifier-tagged tickets.
 */
contract UsageVault is ReentrancyGuard {
    IERC20 public immutable paymentToken;

    mapping(bytes32 => uint256) public creditCommitments;
    mapping(bytes32 => bool) public redeemedTickets;
    mapping(address => uint256) public providerEarnings;

    event CreditsDeposited(bytes32 indexed commitment, uint256 amount);
    event TicketRedeemed(bytes32 indexed ticketNullifier, address indexed provider, uint256 amount);
    event EarningsClaimed(address indexed provider, uint256 amount);

    error CommitmentAlreadyExists();
    error InsufficientCommitmentBalance();
    error TicketAlreadyRedeemed();
    error InvalidTicketProof();
    error NothingToClaim();

    constructor(address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
    }

    /**
     * @notice Lock SER or wXMR under a blinded commitment = keccak256(secret, salt).
     */
    function depositCredits(bytes32 commitment, uint256 amount) external nonReentrant {
        require(commitment != bytes32(0) && amount > 0, "UsageVault: invalid deposit");
        if (creditCommitments[commitment] != 0) revert CommitmentAlreadyExists();

        paymentToken.transferFrom(msg.sender, address(this), amount);
        creditCommitments[commitment] = amount;
        emit CreditsDeposited(commitment, amount);
    }

    /**
     * @notice AI agent/provider redeems a metered usage ticket against a commitment without
     *         revealing the caller's original funding wallet on-chain.
     */
    function redeemUsageTicket(
        bytes32 commitment,
        bytes32 ticketNullifier,
        uint256 amount,
        bytes32 secretPreimage
    ) external nonReentrant {
        if (redeemedTickets[ticketNullifier]) revert TicketAlreadyRedeemed();
        if (keccak256(abi.encodePacked(secretPreimage)) != commitment) revert InvalidTicketProof();
        if (creditCommitments[commitment] < amount) revert InsufficientCommitmentBalance();

        redeemedTickets[ticketNullifier] = true;
        creditCommitments[commitment] -= amount;
        providerEarnings[msg.sender] += amount;

        emit TicketRedeemed(ticketNullifier, msg.sender, amount);
    }

    function claimEarnings() external nonReentrant returns (uint256 amount) {
        amount = providerEarnings[msg.sender];
        if (amount == 0) revert NothingToClaim();
        providerEarnings[msg.sender] = 0;
        paymentToken.transfer(msg.sender, amount);
        emit EarningsClaimed(msg.sender, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title SeraphTimelock
 * @notice Protocol governance timelock for Seraph Protocol.
 * @dev Enforces a mandatory delay before executing privileged administrative operations,
 *      such as modifying ZK verifiers, adjusting cross-chain bridge parameters, or
 *      updating minters and tax rules.
 */
contract SeraphTimelock is TimelockController {
    uint256 public constant MINIMUM_PRODUCTION_DELAY = 1 days;

    event TimelockInitialized(uint256 minDelay, address admin);

    /**
     * @param minDelay Initial minimum delay in seconds (must be >= MINIMUM_PRODUCTION_DELAY).
     * @param proposers Accounts granted PROPOSER_ROLE and CANCELLER_ROLE.
     * @param executors Accounts granted EXECUTOR_ROLE (pass empty to allow anyone when executor is address(0)).
     * @param admin Optional admin for initial setup (should be renounced after configuration).
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {
        require(minDelay >= MINIMUM_PRODUCTION_DELAY, "SeraphTimelock: delay too short for production");
        emit TimelockInitialized(minDelay, admin);
    }
}

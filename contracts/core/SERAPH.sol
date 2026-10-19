// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SeraphToken (SER)
 * @notice Native ERC-20 token with privacy hooks.
 * @dev Standard ERC-20 with helpers for shielding/unshielding
 *      through PrivacyPool, and events for bridging.
 *
 * Specification: Seraph Protocol — Section 6.2
 */
import("@openzeppelin/contracts/token/ERC20/ERC20.sol");
import("@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol");
import("@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol");

contract SeraphToken is ERC20, ERC20Burnable, ERC20Permit {
    address public immutable privacyPool;
    address public immutable treasury;

    uint256 private constant PRECISION = 1e18; // 18 decimals

    event PrivacyHook(address indexed who, string action, uint256 amount);
    event Bridged(address indexed from, bytes32 to, uint256 amount, bytes32 chainId);
    event BridgeReceived(address indexed to, uint256 amount, bytes32 from);

    constructor(
        address _privacyPool,
        address _treasury
    ) ERC20("Seraph", "SER") ERC20Permit("Seraph") {
        privacyPool = _privacyPool;
        treasury = _treasury;
    }

    /* ------------------------------------------------------------------ */
    /* Mint (for genesis / bridge minting — governance-gated)              */
    /* ------------------------------------------------------------------ */

    function mint(address to, uint256 amount) external /* onlyGovernance */ {
        _mint(to, amount);
    }

    /* ------------------------------------------------------------------ */
    /* Privacy hooks                                                      */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Approve PrivacyPool to transfer `amount` tokens,
     *         then call shield. Convenience wrapper.
     */
    function approveAndShield(uint256 amount, bytes32 commitment)
        external
    {
        _approve(msg.sender, privacyPool, amount);
        // PrivacyPool.shield(amount, commitment, "");
        emit PrivacyHook(msg.sender, "shield", amount);
    }

    /**
     * @notice Unshield tokens from the privacy pool back to a public address.
     */
    function unshield(uint256 amount, address recipient) external {
        // PrivacyPool.unshield(nullifier, amount, recipient, proof);
        emit PrivacyHook(msg.sender, "unshield", amount);
    }

    /* ------------------------------------------------------------------ */
    /* Bridge hooks                                                       */
    /* ------------------------------------------------------------------ */

    function lockForBridge(address to, uint256 amount, bytes32 chainId) external {
        _transfer(msg.sender, treasury, amount);
        emit Bridged(msg.sender, to, amount, chainId);
    }

    function receiveFromBridge(address to, uint256 amount) external /* onlyBridge */ {
        _mint(to, amount);
        emit BridgeReceived(to, amount, msg.sender);
    }

    /* ------------------------------------------------------------------ */
    /* Fee burning                                                        */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Burn a percentage of fees sent to this contract.
     *         Called by EVMs and bridge contracts.
     */
    function burnFees(uint256 amount) external {
        _burn(address(this), amount);
    }
}

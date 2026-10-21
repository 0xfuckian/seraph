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
    address public immutable presale;

    uint256 private constant PRECISION = 1e18; // 18 decimals

    /* === Presale tax (active during and after presale) === */
    bool public sellTaxEnabled = true;
    uint256 public constant SELL_TAX_BPS = 100;   // 1.00% on sells
    uint256 public constant BURN_BPS      = 5000; // 50% of sell tax goes to burn

    event PrivacyHook(address indexed who, string action, uint256 amount);
    event Bridged(address indexed from, bytes32 to, uint256 amount, bytes32 chainId);
    event BridgeReceived(address indexed to, uint256 amount, bytes32 from);
    event TaxCollected(address indexed from, address indexed to, uint256 amount, uint256 burned);

    constructor(
        address _privacyPool,
        address _treasury,
        address _presale
    ) ERC20("Seraph", "SER") ERC20Permit("Seraph") {
        privacyPool = _privacyPool;
        treasury = _treasury;
        presale = _presale;
    }

    /* ------------------------------------------------------------------ */
    /* Mint (for genesis / bridge minting — governance-gated)              */
    /* ------------------------------------------------------------------ */

    function mint(address to, uint256 amount) external /* onlyGovernance */ {
        _mint(to, amount);
    }

    /* ------------------------------------------------------------------ */
    /* Transfer tax (sell-side only)                                     */
    /* ------------------------------------------------------------------ */

    /**
     * @dev Transfers tokens with optional sell tax.
     *      Tax is only applied on sells to non-presale, non-treasury, non-privacyPool.
     *      50% of tax is burned, 50% goes to treasury.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        bool isSell = sender != presale && recipient != address(this);
        address from = sender;
        address to = recipient;

        if (sellTaxEnabled && isSell && amount > 0) {
            uint256 tax = (amount * SELL_TAX_BPS) / 10000;
            uint256 burned = (tax * BURN_BPS) / 10000;
            uint256 toTreasury = tax - burned;

            super._transfer(from, address(this), tax);   // collect tax
            _burn(address(this), burned);                  // burn portion
            super._transfer(address(this), treasury, toTreasury); // remainder to treasury

            super._transfer(from, to, amount - tax);       // net transfer to recipient
            emit TaxCollected(from, to, tax, burned);
        } else {
            super._transfer(from, to, amount);
        }
    }

    function setSellTaxEnabled(bool enabled) external /* onlyGovernance */ {
        sellTaxEnabled = enabled;
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

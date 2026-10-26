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
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SeraphToken is ERC20, ERC20Burnable, ERC20Permit {
    address public privacyPool;
    address public treasury;
    address public presale; // settable — avoids circular deployment dependency

    // Authorized minters: presale (vesting claims), treasury (genesis), bridge (bridged mints)
    mapping(address => bool) public minters;

    modifier onlyMinter() {
        require(minters[msg.sender], "SeraphToken: not a minter");
        _;
    }

    uint256 private constant PRECISION = 1e18; // 18 decimals
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18; // Fixed 100M SER max supply

    /* === Presale tax (active during and after presale) === */
    bool public sellTaxEnabled = true;
    uint256 public constant SELL_TAX_BPS = 100; // 1.00% on sells
    uint256 public constant BURN_BPS = 5000; // 50% of sell tax goes to burn

    event PrivacyHook(address indexed who, string action, uint256 amount);
    event Bridged(address indexed from, address to, uint256 amount, bytes32 chainId);
    event BridgeReceived(address indexed to, uint256 amount, address from);
    event TaxCollected(address indexed from, address indexed to, uint256 amount, uint256 burned);
    event TaxExemptionUpdated(address indexed account, bool isExempt);

    mapping(address => bool) public taxExempt;

    constructor(address _privacyPool, address _treasury, address _presale)
        ERC20("Seraph", "SER")
        ERC20Permit("Seraph")
    {
        privacyPool = _privacyPool;
        treasury = _treasury;
        presale = _presale;
        minters[_treasury] = true; // treasury may mint genesis / burn-allocated supply
        if (_presale != address(0)) minters[_presale] = true; // presale mints TGE + vesting claims
    }

    /* ------------------------------------------------------------------ */
    /* Mint (for genesis / bridge minting — governance-gated)              */
    /* ------------------------------------------------------------------ */

    function mint(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount <= MAX_SUPPLY, "SeraphToken: max supply exceeded");
        _mint(to, amount);
    }

    /**
     * @dev Grant/revoke minting rights (e.g. a bridge, a second presale, governance).
     */
    function setMinter(address minter, bool allowed) external onlyTreasury {
        minters[minter] = allowed;
    }

    /* ------------------------------------------------------------------ */
    /* Transfer tax (sell-side only)                                     */
    /* ------------------------------------------------------------------ */

    /**
     * @dev Overrides _update (OZ v5 hook point) to apply sell-side tax.
     *      Tax is only applied on sells to non-presale, non-treasury, non-privacyPool,
     *      and never on mints (from == address(0)) or burns (to == address(0)).
     *      50% of tax is burned, 50% goes to treasury.
     *
     *      Uses multiple super._update() calls to handle tax split since
     *      OZ v5 keeps _balances/_totalSupply private.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Only apply sell tax on regular transfers (not mint/burn, not from presale, not from/to self, not exempt)
        bool isSell = from != address(0) && to != address(0) && from != address(this) && to != address(this)
            && from != presale && to != presale && from != treasury && to != treasury && from != privacyPool
            && to != privacyPool && !taxExempt[from] && !taxExempt[to];

        if (sellTaxEnabled && isSell && amount > 0) {
            uint256 tax = (amount * SELL_TAX_BPS) / 10000;
            uint256 burned = (tax * BURN_BPS) / 10000;
            uint256 toTreasury = tax - burned;
            uint256 remaining = amount - tax;

            // Net transfer to recipient
            super._update(from, to, remaining);

            // Treasury portion
            super._update(from, treasury, toTreasury);

            // Burn portion
            super._update(from, address(0), burned);

            emit TaxCollected(from, to, tax, burned);
        } else {
            super._update(from, to, amount);
        }
    }

    modifier onlyTreasury() {
        require(msg.sender == treasury, "SeraphToken: caller is not treasury");
        _;
    }

    function setSellTaxEnabled(bool enabled) external onlyTreasury {
        sellTaxEnabled = enabled;
    }

    function setPresale(address _presale) external onlyTreasury {
        presale = _presale;
        minters[_presale] = true; // presale remains able to mint TGE + vesting claims
    }

    function setPrivacyPool(address _privacyPool) external onlyTreasury {
        privacyPool = _privacyPool;
    }

    function setTaxExempt(address account, bool isExempt) external onlyTreasury {
        taxExempt[account] = isExempt;
        emit TaxExemptionUpdated(account, isExempt);
    }

    /* ------------------------------------------------------------------ */
    /* 2-Step Governance Handover                                         */
    /* ------------------------------------------------------------------ */

    address public pendingTreasury;
    event TreasuryTransferStarted(address indexed previousTreasury, address indexed newTreasury);
    event TreasuryTransferred(address indexed previousTreasury, address indexed newTreasury);

    function transferTreasury(address _newTreasury) external onlyTreasury {
        require(_newTreasury != address(0), "SeraphToken: zero address");
        pendingTreasury = _newTreasury;
        emit TreasuryTransferStarted(treasury, _newTreasury);
    }

    function acceptTreasury() external {
        require(msg.sender == pendingTreasury, "SeraphToken: not pending treasury");
        address oldTreasury = treasury;
        treasury = pendingTreasury;
        pendingTreasury = address(0);
        minters[treasury] = true;
        emit TreasuryTransferred(oldTreasury, treasury);
    }

    /* ------------------------------------------------------------------ */
    /* Privacy hooks                                                      */
    /* ------------------------------------------------------------------ */

    /**
     * @notice Approve PrivacyPool to transfer `amount` tokens,
     *         then call shield. Convenience wrapper.
     */
    function approveAndShield(uint256 amount, bytes32 commitment) external {
        require(privacyPool != address(0), "SeraphToken: privacyPool not set");
        _approve(msg.sender, privacyPool, amount);
        (bool success,) = privacyPool.call(
            abi.encodeWithSignature("shieldFor(address,uint256,bytes32,bytes)", msg.sender, amount, commitment, "")
        );
        require(success, "SeraphToken: shield call failed");
        emit PrivacyHook(msg.sender, "shield", amount);
    }

    /**
     * @notice Unshield tokens from the privacy pool back to a public address.
     */
    function unshield(bytes32 nullifier, uint256 amount, address recipient, bytes32 root, bytes calldata proof)
        external
    {
        require(privacyPool != address(0), "SeraphToken: privacyPool not set");
        (bool success,) = privacyPool.call(
            abi.encodeWithSignature(
                "unshield(bytes32,uint256,address,bytes32,bytes)", nullifier, amount, recipient, root, proof
            )
        );
        require(success, "SeraphToken: unshield call failed");
        emit PrivacyHook(msg.sender, "unshield", amount);
    }

    /* ------------------------------------------------------------------ */
    /* Bridge hooks                                                       */
    /* ------------------------------------------------------------------ */

    function lockForBridge(address to, uint256 amount, bytes32 chainId) external {
        _transfer(msg.sender, treasury, amount);
        emit Bridged(msg.sender, to, amount, chainId);
    }

    function receiveFromBridge(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount <= MAX_SUPPLY, "SeraphToken: max supply exceeded");
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

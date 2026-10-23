// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PrivateStablecoin (xUSD)
 * @notice Over-collateralized private stablecoin minted by CollateralVault.
 */
contract PrivateStablecoin is ERC20 {
    address public immutable vault;

    constructor(address _vault) ERC20("Seraph Private USD", "xUSD") {
        vault = _vault;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == vault, "xUSD: only vault");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == vault, "xUSD: only vault");
        _burn(from, amount);
    }
}

/**
 * @title CollateralVault
 * @notice First-party Seraph module for Private Stablecoins (Whitepaper Section 7).
 *         Over-collateralized CDP vault accepting SER or wXMR to mint xUSD at >= 150% CR.
 */
contract CollateralVault is ReentrancyGuard {
    uint256 public constant MIN_COLLATERAL_RATIO_BPS = 15_000; // 150%
    uint256 public constant BPS = 10_000;
    uint256 public constant PRICE_PRECISION = 1e18;

    IERC20 public immutable collateralToken;
    PrivateStablecoin public immutable xUSD;
    address public owner;
    uint256 public collateralPriceUsd; // Collateral USD price scaled by 1e18

    struct Position {
        uint256 collateral;
        uint256 debt;
    }

    mapping(address => Position) public positions;

    event CollateralDeposited(address indexed user, uint256 amount);
    event StablecoinMinted(address indexed user, uint256 amount);
    event StablecoinBurned(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);

    error InsufficientCollateralRatio();
    error Unauthorized();

    constructor(address _collateralToken, uint256 _initialPriceUsd) {
        owner = msg.sender;
        collateralToken = IERC20(_collateralToken);
        collateralPriceUsd = _initialPriceUsd;
        xUSD = new PrivateStablecoin(address(this));
    }

    function setCollateralPrice(uint256 newPriceUsd) external {
        if (msg.sender != owner) revert Unauthorized();
        collateralPriceUsd = newPriceUsd;
    }

    function depositAndMint(uint256 collateralAmount, uint256 mintAmount) external nonReentrant {
        Position storage pos = positions[msg.sender];
        if (collateralAmount > 0) {
            collateralToken.transferFrom(msg.sender, address(this), collateralAmount);
            pos.collateral += collateralAmount;
            emit CollateralDeposited(msg.sender, collateralAmount);
        }
        if (mintAmount > 0) {
            pos.debt += mintAmount;
            if (!_isHealthy(pos.collateral, pos.debt)) revert InsufficientCollateralRatio();
            xUSD.mint(msg.sender, mintAmount);
            emit StablecoinMinted(msg.sender, mintAmount);
        }
    }

    function burnAndWithdraw(uint256 burnAmount, uint256 withdrawCollateral) external nonReentrant {
        Position storage pos = positions[msg.sender];
        if (burnAmount > 0) {
            pos.debt -= burnAmount;
            xUSD.burn(msg.sender, burnAmount);
            emit StablecoinBurned(msg.sender, burnAmount);
        }
        if (withdrawCollateral > 0) {
            pos.collateral -= withdrawCollateral;
            if (!_isHealthy(pos.collateral, pos.debt)) revert InsufficientCollateralRatio();
            collateralToken.transfer(msg.sender, withdrawCollateral);
            emit CollateralWithdrawn(msg.sender, withdrawCollateral);
        }
    }

    function _isHealthy(uint256 collateral, uint256 debt) internal view returns (bool) {
        if (debt == 0) return true;
        uint256 collateralValueUsd = (collateral * collateralPriceUsd) / PRICE_PRECISION;
        return (collateralValueUsd * BPS) >= (debt * MIN_COLLATERAL_RATIO_BPS);
    }
}

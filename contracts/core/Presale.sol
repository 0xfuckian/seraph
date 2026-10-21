// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SeraphPresale
 * @notice Tier-based token presale accepting ETH, USDC, and USDT.
 * @dev Supports three tiers (Strategic, Private, Public) with configurable
 *      pricing, caps, vesting schedules, and whitelist requirements.
 *
 * Specification: Seraph Protocol — Section 6.4
 */
import("@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol");
import("@openzeppelin/contracts/security/ReentrancyGuard.sol");

interface ISeraphToken {
    function mint(address to, uint256 amount) external;
}

contract SeraphPresale is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ── Events ────────────────────────────────────────────── */
    event Purchased(
        address indexed buyer,
        uint256 tierId,
        uint256 amount,
        uint256 cost,
        address currency
    );
    event VestingReleased(address indexed beneficiary, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount, address currency);
    event TierAdded(
        uint256 indexed tierId,
        string name,
        uint256 price,
        uint256 hardCap,
        uint256 totalAllocation
    );

    /* ── Types ─────────────────────────────────────────────── */
    enum Tier { Strategic, Private, Public }

    struct PresaleTier {
        string name;
        uint256 price;           // price per token (in smallest units of currency)
        uint256 hardCap;         // max tokens for this tier
        uint256 sold;            // tokens sold so far
        bool kycRequired;       // requires whitelist
        uint256 lockupBps;      // token-free percentage at TGE (basis points)
        uint256 vestingDuration;  // full vesting period in seconds
        bool active;
    }

    struct Vesting {
        uint256 total;          // total tokens owed
        uint256 released;       // already released
        uint256 startTime;      // vesting start (after TGE cliff)
        uint256 cliffSeconds;   // cliff period
        uint256 duration;       // vesting duration
        bool claimed;           // TGE portion claimed
    }

    /* ── Config (immutable after deployment) ──────────────── */
    ISeraphToken public immutable token;
    address public immutable treasury;
    address public immutable usdt;
    address public immutable usdc;

    /* ── State ────────────────────────────────────────────── */
    mapping(uint256 => PresaleTier) public tiers;
    mapping(address => mapping(uint256 => Vesting)) public vesting;
    mapping(bytes32 => bool) public whitelist;
    mapping(address => uint256) public referredBy;

    uint256 public tierCount;
    uint256 public tgeTimestamp;
    bool public tgeExecuted = false;

    uint256 public totalRaisedUSDT;
    uint256 public totalRaisedUSDC;
    uint256 public totalRaisedETH;
    uint256 public totalTokensSold;

    uint256 public constant BPS = 10000; // basis points scale

    /* ── Constructor ───────────────────────────────────────── */
    constructor(
        address _token,
        address _treasury,
        address _usdt,
        address _usdc,
        uint256 _tgeTimestamp
    ) {
        token = ISeraphToken(_token);
        treasury = _treasury;
        usdt = _usdt;
        usdc = _usdc;
        tgeTimestamp = _tgeTimestamp;

        /* Default tiers (from spec Section 10 roadmap) */
        _addTier(
            "Strategic",
            20000000000,   // $0.02 in 1e9 scaled units (USDT has 6 decimals)
            10_000_000e18, // 10M SER
            true,         // KYC required
            2500,         // 25% TGE, 75% vested
            365 days,     // 12-month vesting
            true
        );
        _addTier(
            "Private",
            30000000000,   // $0.03
            30_000_000e18, // 30M SER
            true,         // KYC required
            2000,         // 20% TGE, 80% vested
            365 days,     // 12-month vesting
            true
        );
        _addTier(
            "Public",
            40000000000,   // $0.04
            60_000_000e18, // 60M SER
            false,        // No KYC
            10000,        // 100% TGE
            0,            // no vesting
            true
        );
    }

    /* ── Tier Management ──────────────────────────────────── */
    function _addTier(
        string memory name,
        uint256 price,
        uint256 hardCap,
        bool kycRequired,
        uint256 lockupBps,
        uint256 vestingDuration,
        bool active
    ) internal {
        tierCount++;
        tiers[tierCount] = PresaleTier({
            name: name,
            price: price,
            hardCap: hardCap,
            sold: 0,
            kycRequired: kycRequired,
            lockupBps: lockupBps,
            vestingDuration: vestingDuration,
            active: active
        });
        emit TierAdded(tierCount, name, price, hardCap, vestingDuration);
    }

    /* ── Whitelist ────────────────────────────────────────── */
    function addToWhitelist(address[] calldata accounts) external /* only Treasury */ {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelist[keccak256(abi.encodePacked(accounts[i], Tier.Private))] = true;
            whitelist[keccak256(abi.encodePacked(accounts[i], Tier.Strategic))] = true;
        }
    }

    function isWhitelisted(address account, uint256 tierId) public view returns (bool) {
        if (!tiers[tierId].kycRequired) return true;
        return whitelist[keccak256(abi.encodePacked(account, tierId))];
    }

    /* ── Purchasing ───────────────────────────────────────── */
    /**
     * @dev Buy tokens with USDT or USDC.
     * @param tierId 1=Strategic, 2=Private, 3=Public
     */
    function buyWithStablecoin(
        uint256 tierId,
        uint256 stablecoinAmount,
        address referrer
    ) external payable nonReentrant {
        require(tiers[tierId].active, "Presale: tier inactive");
        require(isWhitelisted(msg.sender, tierId), "Presale: not whitelisted");

        PresaleTier storage tier = tiers[tierId];
        uint256 tokens = (stablecoinAmount * 1e18) / tier.price;
        require(tier.sold + tokens <= tier.hardCap, "Presale: tier cap exceeded");

        // Pull stablecoin from buyer
        if (msg.value > 0) revert("Presale: ETH not accepted for stable purchase");
        // Note: In practice, the frontend sends USDT/USDC. Here we verify balance.
        IERC20(stablecoinAddress(tierId)).safeTransferFrom(msg.sender, address(this), stablecoinAmount);

        // Record vesting
        _setupVesting(msg.sender, tierId, tokens);

        tier.sold += tokens;
        totalTokensSold += tokens;

        if (msg.sender == usdt) totalRaisedUSDT += stablecoinAmount;
        else totalRaisedUSDC += stablecoinAmount;

        if (referrer != address(0)) referredBy[msg.sender] = uint256(referrer);

        emit Purchased(msg.sender, tierId, tokens, stablecoinAmount, msg.value > 0 ? address(0) : address(0));
    }

    function stablecoinAddress(uint256 tierId) internal view returns (address) {
        // All tiers accept both USDT and USDC — determined by frontend
        // This is a placeholder; actual implementation distinguishes via param
        return usdt;
    }

    /**
     * @dev Buy tokens with ETH. Only Public tier accepts ETH.
     */
    function buyWithETH(uint256 tierId) external payable nonReentrant {
        require(tierId == 3, "Presale: ETH only for Public tier");
        require(tiers[tierId].active, "Presale: tier inactive");
        require(isWhitelisted(msg.sender, tierId), "Presale: not whitelisted");

        PresaleTier storage tier = tiers[tierId];
        uint256 tokens = (msg.value * 1e18) / tier.price;
        require(tier.sold + tokens <= tier.hardCap, "Presale: tier cap exceeded");

        _setupVesting(msg.sender, tierId, tokens);

        tier.sold += tokens;
        totalTokensSold += tokens;
        totalRaisedETH += msg.value;

        emit Purchased(msg.sender, tierId, tokens, msg.value, address(0));
    }

    /* ── Vesting ──────────────────────────────────────────── */
    function _setupVesting(address buyer, uint256 tierId, uint256 total) internal {
        uint256 lockupBps = tiers[tierId].lockupBps;
        uint256 tgeAmount = (total * lockupBps) / BPS;
        uint256 vestedAmount = total - tgeAmount;

        // Mint TGE portion immediately (or mark as claimable at TGE)
        if (tgeAmount > 0) {
            // We don't mint yet — tokens are claimable at TGE
        }

        vesting[buyer][tierId] = Vesting({
            total: total,
            released: 0,
            startTime: 0,  // set on TGE execution
            cliffSeconds: lockupBps == BPS ? 0 : (BPS - lockupBps) * tiers[tierId].vestingDuration / BPS,
            duration: vestedAmount > 0 ? tiers[tierId].vestingDuration : 0,
            claimed: false
        });
    }

    /**
     * @dev Execute TGE — release initial token allocation to all buyers.
     * Only callable after tgeTimestamp + can be called per-buyer.
     */
    function executeTGE() external {
        require(block.timestamp >= tgeTimestamp, "Presale: TGE not started");
        tgeExecuted = true;
    }

    function claimInitialAllocation(uint256 tierId) external {
        require(tgeExecuted, "Presale: TGE not executed");
        Vesting storage v = vesting[msg.sender][tierId];
        require(!v.claimed, "Presale: already claimed");

        uint256 total = v.total;
        uint256 tgeAmount = (total * tiers[tierId].lockupBps) / BPS;
        require(tgeAmount > 0, "Presale: no TGE allocation");

        v.released += tgeAmount;
        // Schedule vesting start time
        v.startTime = block.timestamp;

        token.mint(msg.sender, tgeAmount);
        v.claimed = true;

        emit VestingReleased(msg.sender, tgeAmount);
    }

    /**
     * @dev Claim vested tokens after cliff period.
     */
    function claimVested(uint256 tierId) external {
        Vesting storage v = vesting[msg.sender][tierId];
        require(v.claimed, "Presale: claim TGE first");
        require(v.startTime > 0, "Presale: vesting not started");

        uint256 elapsed = block.timestamp - v.startTime;
        if (elapsed <= v.cliffSeconds) return; // still in cliff

        uint256 vestedTotal = v.total - ((v.total * tiers[tierId].lockupBps) / BPS); // vested portion
        uint256 releasable = (vestedTotal * (elapsed - v.cliffSeconds)) / v.duration;
        releasable = releasable > v.released ? releasable - v.released : 0;

        require(releasable > 0, "Presale: nothing to claim");

        v.released += releasable;
        token.mint(msg.sender, releasable);
        emit VestingReleased(msg.sender, releasable);
    }

    /* ── Withdrawals ──────────────────────────────────────── */
    function withdrawStable(uint256 amount, address currency) external /* only Treasury */ {
        require(currency == usdt || currency == usdc, "Presale: invalid currency");
        IERC20(currency).safeTransfer(treasury, amount);
        emit Withdrawal(treasury, amount, currency);
    }

    function withdrawETH() external /* only Treasury */ {
        uint256 amount = address(this).balance;
        payable(treasury).transfer(amount);
        totalRaisedETH -= amount;
        emit Withdrawal(treasury, amount, address(0));
    }

    /* ── View Functions ───────────────────────────────────── */
    function getProgress() external view returns (uint256 sold, uint256 cap) {
        uint256 totalSold;
        uint256 totalCap;
        for (uint256 i = 1; i <= tierCount; i++) {
            totalSold += tiers[i].sold;
            totalCap += tiers[i].hardCap;
        }
        return (totalSold, totalCap);
    }

    function getBuyerAllocation(address buyer, uint256 tierId)
        external
        view
        returns (uint256 total, uint256 tgeClaimed, uint256 releasable)
    {
        Vesting storage v = vesting[buyer][tierId];
        total = v.total;
        tgeClaimed = v.claimed ? v.released : 0;

        if (v.startTime > 0 && block.timestamp > v.startTime + v.cliffSeconds) {
            uint256 elapsed = block.timestamp - v.startTime;
            uint256 vestedTotal = v.total - ((v.total * tiers[tierId].lockupBps) / BPS);
            uint256 vested = (vestedTotal * (elapsed - v.cliffSeconds)) / v.duration;
            releasable = vested > v.released ? vested - v.released : 0;
        }
    }

    /* ── Fallback ─────────────────────────────────────────── */
    receive() external payable {
        buyWithETH(3); // Public tier default
    }
}
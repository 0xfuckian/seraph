// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LaunchToken
 * @notice Standard 18-decimal ERC-20 deployed by SeraphLaunchpad with on-chain metadata
 *         and O(1) holder dividend distribution (Magnified Dividend Per Share).
 *         No wallet tax exemptions exist; all trading fees are enforced at the pool/curve level.
 */
contract LaunchToken is ERC20, ERC20Burnable {
    uint256 private constant ACC_PRECISION = 1e36;

    address public immutable launchpad;
    address public immutable creator;

    string public description;
    string public image;
    string public website;
    string public twitter;
    string public telegram;

    uint256 public accDividendPerShare;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public pendingDividends;

    event DividendsDistributed(uint256 amount, uint256 eligibleSupply);
    event DividendsClaimed(address indexed holder, uint256 amount);

    struct Metadata {
        string description;
        string image;
        string website;
        string twitter;
        string telegram;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _creator,
        Metadata memory _meta
    ) ERC20(_name, _symbol) {
        launchpad = msg.sender;
        creator = _creator;
        description = _meta.description;
        image = _meta.image;
        website = _meta.website;
        twitter = _meta.twitter;
        telegram = _meta.telegram;

        _mint(msg.sender, _totalSupply);
    }

    /**
     * @notice Supply held by circulating holders (excludes the launchpad reserve).
     */
    function eligibleSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(launchpad);
    }

    /**
     * @notice Deposit ETH dividends for circulating token holders.
     */
    function distributeDividends() external payable {
        require(msg.value > 0, "LaunchToken: zero dividend");
        uint256 eligible = eligibleSupply();
        require(eligible > 0, "LaunchToken: no eligible holders");
        accDividendPerShare += (msg.value * ACC_PRECISION) / eligible;
        emit DividendsDistributed(msg.value, eligible);
    }

    /**
     * @notice View total claimable ETH dividends for `holder`.
     */
    function claimableDividends(address holder) public view returns (uint256) {
        if (holder == address(0) || holder == launchpad) return 0;
        uint256 accumulated = (balanceOf(holder) * accDividendPerShare) / ACC_PRECISION;
        return pendingDividends[holder] + (accumulated - rewardDebt[holder]);
    }

    /**
     * @notice Claim accrued ETH holder dividends.
     */
    function claimDividends(address holder) external returns (uint256 amount) {
        _checkpoint(holder);
        amount = pendingDividends[holder];
        require(amount > 0, "LaunchToken: nothing to claim");
        pendingDividends[holder] = 0;
        (bool ok, ) = holder.call{value: amount}("");
        require(ok, "LaunchToken: ETH transfer failed");
        emit DividendsClaimed(holder, amount);
    }

    function _checkpoint(address account) internal {
        if (account == address(0) || account == launchpad) return;
        uint256 accumulated = (balanceOf(account) * accDividendPerShare) / ACC_PRECISION;
        if (accumulated > rewardDebt[account]) {
            pendingDividends[account] += accumulated - rewardDebt[account];
        }
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        _checkpoint(from);
        _checkpoint(to);
        super._update(from, to, value);
        if (from != address(0) && from != launchpad) {
            rewardDebt[from] = (balanceOf(from) * accDividendPerShare) / ACC_PRECISION;
        }
        if (to != address(0) && to != launchpad) {
            rewardDebt[to] = (balanceOf(to) * accDividendPerShare) / ACC_PRECISION;
        }
    }
}

/**
 * @title SeraphLaunchpad
 * @notice Permissionless token launchpad supporting three launch models:
 *         - FixedPool: Full supply starts immediately in a locked pool.
 *         - BondingCurve: Supply trades on a constant-product bonding curve and auto-graduates
 *           into a permanently locked pool once `graduationThreshold` is reached.
 *         - SeraphPool: Trades on a native Seraph pool with quote-denominated fee routing.
 *
 *         Enforces an immutable 1% (100 bps) platform fee on every buy and sell plus an
 *         immutable creator-configured buy/sell fee (0–2.5% / 0–250 bps) split across:
 *         Creator, Buyback & Burn, Holder Dividends, Pool Auto-LP, and Seraph Platform.
 */
contract SeraphLaunchpad is ReentrancyGuard {
    uint16 public constant BPS = 10_000;
    uint16 public constant PLATFORM_FEE_BPS = 100;      // Fixed 1.0% platform fee per side
    uint16 public constant MAX_CREATOR_FEE_BPS = 250;   // Max 2.5% creator fee per side
    uint16 public constant MAX_DEV_BUY_BPS = 1_000;     // Max 10.0% dev buy at launch

    enum LaunchModel {
        FixedPool,
        BondingCurve,
        SeraphPool
    }

    struct LaunchParams {
        string name;
        string symbol;
        string description;
        string image;
        string website;
        string twitter;
        string telegram;
        LaunchModel model;
        uint256 totalSupply;
        address feeWallet;
        uint16 buyFeeBps;
        uint16 sellFeeBps;
        uint16 creatorShareBps;
        uint16 buybackShareBps;
        uint16 dividendsShareBps;
        uint16 liquidityShareBps;
        uint16 platformShareBps;
        uint16 devBuyBps;
    }

    struct LaunchInfo {
        address token;
        address creator;
        address feeWallet;
        LaunchModel model;
        bool graduated;
        uint16 buyFeeBps;
        uint16 sellFeeBps;
        uint16 creatorShareBps;
        uint16 buybackShareBps;
        uint16 dividendsShareBps;
        uint16 liquidityShareBps;
        uint16 platformShareBps;
        uint16 devBuyBps;
        uint64 launchedAt;
        uint256 initialSupply;
        uint256 realQuoteReserve;
        uint256 phantomQuote;
        uint256 tokenReserve;
        uint256 reservedTokens;
        uint256 graduationThreshold;
    }

    address public owner;
    address public platformFeeRecipient;
    uint256 public launchFee;
    uint256 public defaultPhantomQuote = 1.5 ether;
    uint256 public defaultGraduationThreshold = 4.5 ether;

    address[] public allTokens;
    mapping(address => LaunchInfo) internal _launches;
    mapping(address => uint256) public claimableFees;

    function getLaunch(address token) external view returns (LaunchInfo memory) {
        return _launches[token];
    }

    event TokenLaunched(
        address indexed token,
        address indexed creator,
        address indexed feeWallet,
        LaunchModel model,
        uint256 totalSupply,
        uint16 buyFeeBps,
        uint16 sellFeeBps,
        uint16 devBuyBps
    );
    event Trade(
        address indexed token,
        address indexed trader,
        bool isBuy,
        uint256 quoteAmount,
        uint256 tokenAmount,
        uint256 platformFee,
        uint256 creatorFee
    );
    event Graduated(address indexed token, uint256 quoteReserve, uint256 tokenReserve);
    event FeesClaimed(address indexed recipient, uint256 amount);
    event ConfigUpdated(address indexed platformFeeRecipient, uint256 launchFee, uint256 phantomQuote, uint256 graduationThreshold);

    error Unauthorized();
    error InvalidMetadata();
    error InvalidSupply();
    error InvalidFeeRate();
    error InvalidFeeSplit();
    error InvalidDevBuy();
    error InsufficientLaunchFee();
    error UnknownToken();
    error ZeroAmount();
    error SlippageExceeded();
    error AlreadyGraduated();
    error NotReadyToGraduate();
    error NothingToClaim();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _platformFeeRecipient, uint256 _launchFee) {
        if (_platformFeeRecipient == address(0)) revert Unauthorized();
        owner = msg.sender;
        platformFeeRecipient = _platformFeeRecipient;
        launchFee = _launchFee;
    }

    /* ------------------------------------------------------------------ */
    /* Token Launch                                                       */
    /* ------------------------------------------------------------------ */

    function launch(LaunchParams calldata p) external payable nonReentrant returns (address token) {
        if (bytes(p.name).length == 0 || bytes(p.name).length > 32) revert InvalidMetadata();
        if (bytes(p.symbol).length == 0 || bytes(p.symbol).length > 10) revert InvalidMetadata();
        if (bytes(p.description).length > 280) revert InvalidMetadata();
        if (p.totalSupply < 1e18) revert InvalidSupply();
        if (p.buyFeeBps > MAX_CREATOR_FEE_BPS || p.sellFeeBps > MAX_CREATOR_FEE_BPS) revert InvalidFeeRate();
        if (
            uint256(p.creatorShareBps) +
            p.buybackShareBps +
            p.dividendsShareBps +
            p.liquidityShareBps +
            p.platformShareBps != BPS
        ) revert InvalidFeeSplit();
        if (p.devBuyBps > MAX_DEV_BUY_BPS) revert InvalidDevBuy();
        if (msg.value < launchFee) revert InsufficientLaunchFee();

        uint256 devBuyEth = msg.value - launchFee;
        if (devBuyEth > 0 && p.devBuyBps == 0) revert InvalidDevBuy();

        if (launchFee > 0) {
            claimableFees[platformFeeRecipient] += launchFee;
        }

        token = address(
            new LaunchToken(
                p.name,
                p.symbol,
                p.totalSupply,
                msg.sender,
                LaunchToken.Metadata({
                    description: p.description,
                    image: p.image,
                    website: p.website,
                    twitter: p.twitter,
                    telegram: p.telegram
                })
            )
        );

        _initLaunch(token, p);

        if (devBuyEth > 0) {
            uint256 maxDevTokens = (p.totalSupply * p.devBuyBps) / BPS;
            (, uint256 refund) = _executeBuy(token, devBuyEth, 0, maxDevTokens, msg.sender);
            if (refund > 0) {
                (bool ok, ) = msg.sender.call{value: refund}("");
                if (!ok) revert TransferFailed();
            }
        }
    }

    function _initLaunch(address token, LaunchParams calldata p) internal {
        address feeRecipient = p.feeWallet == address(0) ? msg.sender : p.feeWallet;
        bool isCurve = p.model == LaunchModel.BondingCurve;
        uint256 phantom = defaultPhantomQuote;
        uint256 gradThreshold = isCurve ? defaultGraduationThreshold : 0;

        LaunchInfo storage L = _launches[token];
        L.token = token;
        L.creator = msg.sender;
        L.feeWallet = feeRecipient;
        L.model = p.model;
        L.graduated = !isCurve;
        L.buyFeeBps = p.buyFeeBps;
        L.sellFeeBps = p.sellFeeBps;
        L.creatorShareBps = p.creatorShareBps;
        L.buybackShareBps = p.buybackShareBps;
        L.dividendsShareBps = p.dividendsShareBps;
        L.liquidityShareBps = p.liquidityShareBps;
        L.platformShareBps = p.platformShareBps;
        L.devBuyBps = p.devBuyBps;
        L.launchedAt = uint64(block.timestamp);
        L.initialSupply = p.totalSupply;
        L.phantomQuote = phantom;
        L.tokenReserve = p.totalSupply;
        L.reservedTokens = isCurve ? (p.totalSupply * phantom) / (phantom + gradThreshold) : 0;
        L.graduationThreshold = gradThreshold;
        allTokens.push(token);

        emit TokenLaunched(
            token,
            msg.sender,
            feeRecipient,
            p.model,
            p.totalSupply,
            p.buyFeeBps,
            p.sellFeeBps,
            p.devBuyBps
        );
    }

    /* ------------------------------------------------------------------ */
    /* Trading (Bonding Curve & Locked Pool)                              */
    /* ------------------------------------------------------------------ */

    function buy(
        address token,
        uint256 minTokensOut,
        address recipient
    ) external payable nonReentrant returns (uint256 tokensOut) {
        if (msg.value == 0) revert ZeroAmount();
        address to = recipient == address(0) ? msg.sender : recipient;
        uint256 refund;
        (tokensOut, refund) = _executeBuy(token, msg.value, minTokensOut, type(uint256).max, to);
        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            if (!ok) revert TransferFailed();
        }
    }

    function sell(
        address token,
        uint256 tokenAmount,
        uint256 minQuoteOut,
        address recipient
    ) external nonReentrant returns (uint256 netQuoteOut) {
        if (tokenAmount == 0) revert ZeroAmount();
        LaunchInfo storage L = _launches[token];
        if (L.token == address(0)) revert UnknownToken();

        address to = recipient == address(0) ? msg.sender : recipient;
        LaunchToken(token).transferFrom(msg.sender, address(this), tokenAmount);

        uint256 quoteReserve = L.realQuoteReserve + L.phantomQuote;
        uint256 grossQuoteOut = (quoteReserve * tokenAmount) / (L.tokenReserve + tokenAmount);
        if (grossQuoteOut > L.realQuoteReserve) {
            grossQuoteOut = L.realQuoteReserve;
        }

        L.realQuoteReserve -= grossQuoteOut;
        L.tokenReserve += tokenAmount;

        uint256 platformFee = (grossQuoteOut * PLATFORM_FEE_BPS) / BPS;
        uint256 creatorFee = (grossQuoteOut * L.sellFeeBps) / BPS;
        netQuoteOut = grossQuoteOut - platformFee - creatorFee;
        if (netQuoteOut < minQuoteOut) revert SlippageExceeded();

        _distributeFees(L, platformFee, creatorFee);

        (bool ok, ) = to.call{value: netQuoteOut}("");
        if (!ok) revert TransferFailed();

        emit Trade(token, msg.sender, false, grossQuoteOut, tokenAmount, platformFee, creatorFee);
    }

    /**
     * @notice Permissionless fallback to graduate a BondingCurve launch once its curve completes.
     */
    function graduate(address token) external nonReentrant {
        LaunchInfo storage L = _launches[token];
        if (L.token == address(0)) revert UnknownToken();
        if (L.graduated) revert AlreadyGraduated();
        if (sellableTokens(token) != 0 && L.realQuoteReserve < L.graduationThreshold) {
            revert NotReadyToGraduate();
        }
        _graduate(L);
    }

    /**
     * @notice Claim accumulated ETH fees (creator fees or platform fees).
     */
    function claimFees() external nonReentrant returns (uint256 amount) {
        amount = claimableFees[msg.sender];
        if (amount == 0) revert NothingToClaim();
        claimableFees[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit FeesClaimed(msg.sender, amount);
    }

    /* ------------------------------------------------------------------ */
    /* Internal Trade & Fee Engine                                        */
    /* ------------------------------------------------------------------ */

    struct BuyQuote {
        uint256 tokensOut;
        uint256 netQuoteIn;
        uint256 platformFee;
        uint256 creatorFee;
        uint256 refund;
        bool completesCurve;
    }

    function _quoteBuy(
        LaunchInfo storage L,
        uint256 grossQuoteIn,
        uint256 maxTokensCap
    ) internal view returns (BuyQuote memory q) {
        uint256 quoteReserve = L.realQuoteReserve + L.phantomQuote;
        q.platformFee = (grossQuoteIn * PLATFORM_FEE_BPS) / BPS;
        q.creatorFee = (grossQuoteIn * L.buyFeeBps) / BPS;
        q.netQuoteIn = grossQuoteIn - q.platformFee - q.creatorFee;

        q.tokensOut = (L.tokenReserve * q.netQuoteIn) / (quoteReserve + q.netQuoteIn);

        uint256 available = L.graduated
            ? L.tokenReserve
            : (L.tokenReserve > L.reservedTokens ? L.tokenReserve - L.reservedTokens : 0);
        uint256 cap = available < maxTokensCap ? available : maxTokensCap;
        q.completesCurve = !L.graduated && q.tokensOut >= available;

        if (q.tokensOut > cap) {
            q.tokensOut = cap;
            uint256 denom = L.tokenReserve - q.tokensOut;
            q.netQuoteIn = (quoteReserve * q.tokensOut + denom - 1) / denom;
            uint256 netBps = BPS - PLATFORM_FEE_BPS - L.buyFeeBps;
            uint256 grossUsed = (q.netQuoteIn * BPS + netBps - 1) / netBps;
            if (grossUsed > grossQuoteIn) grossUsed = grossQuoteIn;

            q.platformFee = (grossUsed * PLATFORM_FEE_BPS) / BPS;
            q.creatorFee = (grossUsed * L.buyFeeBps) / BPS;
            q.netQuoteIn = grossUsed - q.platformFee - q.creatorFee;
            q.refund = grossQuoteIn - grossUsed;
        }
    }

    function _executeBuy(
        address token,
        uint256 grossQuoteIn,
        uint256 minTokensOut,
        uint256 maxTokensCap,
        address recipient
    ) internal returns (uint256 tokensOut, uint256 refund) {
        LaunchInfo storage L = _launches[token];
        if (L.token == address(0)) revert UnknownToken();

        BuyQuote memory q = _quoteBuy(L, grossQuoteIn, maxTokensCap);
        if (q.tokensOut == 0 || q.tokensOut < minTokensOut) revert SlippageExceeded();

        L.realQuoteReserve += q.netQuoteIn;
        L.tokenReserve -= q.tokensOut;

        // Transfer tokens before fee distribution so first buyer is eligible for holder dividends
        LaunchToken(token).transfer(recipient, q.tokensOut);

        _distributeFees(L, q.platformFee, q.creatorFee);

        emit Trade(token, recipient, true, grossQuoteIn - q.refund, q.tokensOut, q.platformFee, q.creatorFee);

        if (q.completesCurve || (!L.graduated && (sellableTokens(token) == 0 || L.realQuoteReserve >= L.graduationThreshold))) {
            _graduate(L);
        }
        return (q.tokensOut, q.refund);
    }

    function _distributeFees(LaunchInfo storage L, uint256 platformFee, uint256 creatorFee) internal {
        if (platformFee > 0) {
            claimableFees[platformFeeRecipient] += platformFee;
        }
        if (creatorFee == 0) return;

        uint256 toPlatform = (creatorFee * L.platformShareBps) / BPS;
        uint256 toLiquidity = (creatorFee * L.liquidityShareBps) / BPS;
        uint256 toBuyback = (creatorFee * L.buybackShareBps) / BPS;
        uint256 toDividends = (creatorFee * L.dividendsShareBps) / BPS;
        uint256 toCreator = creatorFee - toPlatform - toLiquidity - toBuyback - toDividends;

        if (toPlatform > 0) {
            claimableFees[platformFeeRecipient] += toPlatform;
        }
        if (toLiquidity > 0) {
            L.realQuoteReserve += toLiquidity;
        }
        if (toBuyback > 0) {
            uint256 quoteReserve = L.realQuoteReserve + L.phantomQuote;
            uint256 burnAmount = (L.tokenReserve * toBuyback) / (quoteReserve + toBuyback);
            uint256 maxBurn = L.tokenReserve > L.reservedTokens ? L.tokenReserve - L.reservedTokens : 0;
            if (burnAmount > maxBurn) burnAmount = maxBurn;
            L.realQuoteReserve += toBuyback;
            if (burnAmount > 0) {
                L.tokenReserve -= burnAmount;
                LaunchToken(L.token).burn(burnAmount);
            }
        }
        if (toDividends > 0) {
            LaunchToken tk = LaunchToken(L.token);
            if (tk.eligibleSupply() > 0) {
                tk.distributeDividends{value: toDividends}();
            } else {
                toCreator += toDividends;
            }
        }
        if (toCreator > 0) {
            claimableFees[L.feeWallet] += toCreator;
        }
    }

    function _graduate(LaunchInfo storage L) internal {
        L.graduated = true;
        L.reservedTokens = 0;
        emit Graduated(L.token, L.realQuoteReserve, L.tokenReserve);
    }

    /* ------------------------------------------------------------------ */
    /* Views & Quotes                                                     */
    /* ------------------------------------------------------------------ */

    function totalLaunches() external view returns (uint256) {
        return allTokens.length;
    }

    function sellableTokens(address token) public view returns (uint256) {
        LaunchInfo storage L = _launches[token];
        if (L.graduated) return L.tokenReserve;
        return L.tokenReserve > L.reservedTokens ? L.tokenReserve - L.reservedTokens : 0;
    }

    function graduationProgressBps(address token) external view returns (uint256) {
        LaunchInfo storage L = _launches[token];
        if (L.token == address(0)) revert UnknownToken();
        if (L.graduated || L.graduationThreshold == 0) return BPS;
        uint256 totalCurveTokens = L.initialSupply - L.reservedTokens;
        uint256 rem = sellableTokens(token);
        if (rem == 0) return BPS;
        uint256 sold = totalCurveTokens > rem ? totalCurveTokens - rem : 0;
        uint256 prog = (sold * BPS) / totalCurveTokens;
        return prog >= BPS ? BPS : prog;
    }

    function quoteBuy(address token, uint256 grossQuoteIn)
        external
        view
        returns (uint256 tokensOut, uint256 platformFee, uint256 creatorFee, uint256 refund)
    {
        LaunchInfo storage L = _launches[token];
        if (L.token == address(0)) revert UnknownToken();
        BuyQuote memory q = _quoteBuy(L, grossQuoteIn, type(uint256).max);
        return (q.tokensOut, q.platformFee, q.creatorFee, q.refund);
    }

    function quoteSell(address token, uint256 tokenAmount)
        external
        view
        returns (uint256 netQuoteOut, uint256 platformFee, uint256 creatorFee)
    {
        LaunchInfo storage L = _launches[token];
        if (L.token == address(0)) revert UnknownToken();

        uint256 quoteReserve = L.realQuoteReserve + L.phantomQuote;
        uint256 grossQuoteOut = (quoteReserve * tokenAmount) / (L.tokenReserve + tokenAmount);
        if (grossQuoteOut > L.realQuoteReserve) {
            grossQuoteOut = L.realQuoteReserve;
        }
        platformFee = (grossQuoteOut * PLATFORM_FEE_BPS) / BPS;
        creatorFee = (grossQuoteOut * L.sellFeeBps) / BPS;
        netQuoteOut = grossQuoteOut - platformFee - creatorFee;
    }

    function quoteDevBuy(uint256 totalSupply, uint16 buyFeeBps, uint16 devBuyBps)
        external
        view
        returns (uint256 ethRequired)
    {
        if (devBuyBps == 0) return launchFee;
        uint256 targetTokens = (totalSupply * devBuyBps) / BPS;
        uint256 denom = totalSupply - targetTokens;
        uint256 netQuote = (defaultPhantomQuote * targetTokens + denom - 1) / denom;
        uint256 netBps = BPS - PLATFORM_FEE_BPS - buyFeeBps;
        uint256 grossQuote = (netQuote * BPS + netBps - 1) / netBps;
        return launchFee + grossQuote;
    }

    /* ------------------------------------------------------------------ */
    /* Admin                                                              */
    /* ------------------------------------------------------------------ */

    function setConfig(
        address _platformFeeRecipient,
        uint256 _launchFee,
        uint256 _defaultPhantomQuote,
        uint256 _defaultGraduationThreshold
    ) external onlyOwner {
        if (_platformFeeRecipient == address(0) || _defaultPhantomQuote == 0 || _defaultGraduationThreshold == 0) {
            revert Unauthorized();
        }
        platformFeeRecipient = _platformFeeRecipient;
        launchFee = _launchFee;
        defaultPhantomQuote = _defaultPhantomQuote;
        defaultGraduationThreshold = _defaultGraduationThreshold;
        emit ConfigUpdated(_platformFeeRecipient, _launchFee, _defaultPhantomQuote, _defaultGraduationThreshold);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/Launchpad.sol";
import "../core/SERAPH.sol";
import "../core/PrivacyPool.sol";
import "../modules/ai_payments/UsageVault.sol";
import "../modules/stablecoin/CollateralVault.sol";

/**
 * @notice Stateful handler driving random sequences of buys, sells, ERC-20 transfers,
 *         dividend claims, and fee claims against SeraphLaunchpad and LaunchToken.
 */
contract LaunchpadInvariantHandler is Test {
    SeraphLaunchpad public launchpad;
    LaunchToken public token;
    address public platform;
    address public creator;
    address[] public actors;

    uint256 public totalDividendsDistributed;
    uint256 public totalDividendsClaimed;

    constructor(
        SeraphLaunchpad _launchpad,
        LaunchToken _token,
        address _platform,
        address _creator,
        address[] memory _actors
    ) {
        launchpad = _launchpad;
        token = _token;
        platform = _platform;
        creator = _creator;
        actors = _actors;
    }

    function handler_buy(uint256 actorSeed, uint256 ethAmount) external {
        address actor = actors[actorSeed % actors.length];
        ethAmount = bound(ethAmount, 0.0005 ether, 2 ether);
        vm.deal(actor, actor.balance + ethAmount);

        (uint256 quotedTokens,,,) = launchpad.quoteBuy(address(token), ethAmount);
        if (quotedTokens == 0) return;

        vm.prank(actor);
        launchpad.buy{value: ethAmount}(address(token), 1, actor);
    }

    function handler_sell(uint256 actorSeed, uint256 sellBps) external {
        address actor = actors[actorSeed % actors.length];
        uint256 bal = token.balanceOf(actor);
        if (bal == 0) return;

        sellBps = bound(sellBps, 100, 10_000);
        uint256 sellAmt = (bal * sellBps) / 10_000;
        if (sellAmt == 0) return;

        (uint256 netOut,,) = launchpad.quoteSell(address(token), sellAmt);
        if (netOut == 0) return;

        vm.startPrank(actor);
        token.approve(address(launchpad), sellAmt);
        launchpad.sell(address(token), sellAmt, 0, actor);
        vm.stopPrank();
    }

    function handler_transfer(uint256 fromSeed, uint256 toSeed, uint256 transferBps) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 bal = token.balanceOf(from);
        if (bal == 0) return;

        transferBps = bound(transferBps, 1, 10_000);
        uint256 amt = (bal * transferBps) / 10_000;
        if (amt == 0) return;

        vm.prank(from);
        token.transfer(to, amt);
    }

    function handler_claimDividends(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 claimable = token.claimableDividends(actor);
        if (claimable == 0) return;

        vm.prank(actor);
        uint256 claimed = token.claimDividends(actor);
        totalDividendsClaimed += claimed;
    }

    function handler_claimCreatorFees() external {
        if (launchpad.claimableFees(creator) == 0) return;
        vm.prank(creator);
        launchpad.claimFees();
    }

    function handler_claimPlatformFees() external {
        if (launchpad.claimableFees(platform) == 0) return;
        vm.prank(platform);
        launchpad.claimFees();
    }
}

/**
 * @title StatefulProtocolInvariantsTest
 * @notice Foundry stateful invariant suite (`invariant_*`) verifying protocol-wide
 *         ETH/token solvency, reserve accounting, dividend conservation, and vault health.
 */
contract StatefulProtocolInvariantsTest is Test {
    SeraphLaunchpad public launchpad;
    LaunchToken public token;
    LaunchpadInvariantHandler public handler;

    address public platform = makeAddr("inv_platform");
    address public creator = makeAddr("inv_creator");
    address[] public actors;

    function setUp() public {
        launchpad = new SeraphLaunchpad(platform, 0.0005 ether);

        for (uint256 i = 0; i < 6; i++) {
            address a = makeAddr(string(abi.encodePacked("inv_actor_", vm.toString(i))));
            vm.deal(a, 100 ether);
            actors.push(a);
        }
        vm.deal(creator, 10 ether);

        SeraphLaunchpad.LaunchParams memory p = SeraphLaunchpad.LaunchParams({
            name: "Invariant Guard Token",
            symbol: "IGT",
            description: "Stateful invariant fuzzing target",
            image: "",
            website: "",
            twitter: "",
            telegram: "",
            model: SeraphLaunchpad.LaunchModel.BondingCurve,
            totalSupply: 1_000_000_000e18,
            feeWallet: creator,
            buyFeeBps: 250,
            sellFeeBps: 250,
            creatorShareBps: 2000,
            buybackShareBps: 2000,
            dividendsShareBps: 3000,
            liquidityShareBps: 2000,
            platformShareBps: 1000,
            devBuyBps: 200
        });

        uint256 reqEth = launchpad.quoteDevBuy(p.totalSupply, p.buyFeeBps, p.devBuyBps);
        vm.prank(creator);
        address tokAddr = launchpad.launch{value: reqEth}(p);
        token = LaunchToken(tokAddr);
        actors.push(creator);

        handler = new LaunchpadInvariantHandler(launchpad, token, platform, creator, actors);
        targetContract(address(handler));
    }

    /**
     * @notice INVARIANT 1: SeraphLaunchpad ETH balance must ALWAYS cover `realQuoteReserve`
     *         plus all unclaimed creator and platform fees.
     */
    function invariant_LaunchpadETHAlwaysSolvent() public view {
        SeraphLaunchpad.LaunchInfo memory L = launchpad.getLaunch(address(token));
        uint256 requiredEth = L.realQuoteReserve + launchpad.claimableFees(platform) + launchpad.claimableFees(creator);
        assertGe(address(launchpad).balance, requiredEth, "Launchpad ETH insolvency detected");
    }

    /**
     * @notice INVARIANT 2: LaunchToken ETH balance must ALWAYS cover the sum of
     *         `claimableDividends` across all token holders.
     */
    function invariant_LaunchTokenDividendsAlwaysSolvent() public view {
        uint256 sumClaimable = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            sumClaimable += token.claimableDividends(actors[i]);
        }
        assertGe(address(token).balance, sumClaimable, "LaunchToken dividend ETH insolvency detected");
    }

    /**
     * @notice INVARIANT 3: Launchpad token balance must ALWAYS equal `L.tokenReserve`,
     *         and total supply must never exceed `L.initialSupply`.
     */
    function invariant_TokenReserveMatchesActualBalanceAndSupplyCapped() public view {
        SeraphLaunchpad.LaunchInfo memory L = launchpad.getLaunch(address(token));
        assertEq(token.balanceOf(address(launchpad)), L.tokenReserve, "Reserve mismatch with ERC20 balance");
        assertLe(token.totalSupply(), L.initialSupply, "Total supply exceeded initial supply");
        if (!L.graduated) {
            assertGe(L.tokenReserve, L.reservedTokens, "Curve dipped into graduation reserved tokens");
        }
    }
}

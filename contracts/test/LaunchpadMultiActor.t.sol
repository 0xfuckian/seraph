// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/Launchpad.sol";

/**
 * @notice Malicious contract that rejects all incoming ETH transfers to simulate
 *         a honeypot feeWallet or griefing dividend holder.
 */
contract RevertingEthReceiver {
    error EthRejected();

    receive() external payable {
        revert EthRejected();
    }

    fallback() external payable {
        revert EthRejected();
    }

    function tryClaimFees(SeraphLaunchpad launchpad) external returns (uint256) {
        return launchpad.claimFees();
    }

    function tryClaimDividends(LaunchToken token) external returns (uint256) {
        return token.claimDividends(address(this));
    }
}

/**
 * @title LaunchpadMultiActorTest
 * @notice Comprehensive multi-actor stress, lifecycle, preset, graduation, adversarial,
 *         and fuzz test suite for SeraphLaunchpad and LaunchToken.
 */
contract LaunchpadMultiActorTest is Test {
    SeraphLaunchpad public launchpad;

    address public platformWallet = makeAddr("platformWallet");
    address public creator = makeAddr("creator");
    address public creatorFeeWallet = makeAddr("creatorFeeWallet");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public buyer3 = makeAddr("buyer3");
    address public whale = makeAddr("whale");

    uint256 public constant DEFAULT_SUPPLY = 1_000_000_000 ether; // 1B tokens (18 decimals)
    uint256 public constant LAUNCH_FEE = 0.001 ether;

    function setUp() public {
        launchpad = new SeraphLaunchpad(platformWallet, LAUNCH_FEE);

        vm.deal(creator, 500 ether);
        vm.deal(buyer1, 500 ether);
        vm.deal(buyer2, 500 ether);
        vm.deal(buyer3, 500 ether);
        vm.deal(whale, 2_000 ether);
    }

    /* ================================================================== */
    /* Helpers                                                            */
    /* ================================================================== */

    function _baseParams() internal view returns (SeraphLaunchpad.LaunchParams memory p) {
        p = SeraphLaunchpad.LaunchParams({
            name: "Seraph MultiActor",
            symbol: "SMA",
            description: "Multi-actor stress test token on Seraph Launchpad",
            image: "ipfs://QmSeraphMultiActor",
            website: "https://seraph.finance",
            twitter: "@seraph_defi",
            telegram: "t.me/seraph_defi",
            model: SeraphLaunchpad.LaunchModel.BondingCurve,
            totalSupply: DEFAULT_SUPPLY,
            feeWallet: creatorFeeWallet,
            buyFeeBps: 200, // 2.0% creator buy fee (+ 1.0% platform = 3.0% total)
            sellFeeBps: 200, // 2.0% creator sell fee (+ 1.0% platform = 3.0% total)
            creatorShareBps: 2_000,
            buybackShareBps: 2_000,
            dividendsShareBps: 2_000,
            liquidityShareBps: 2_000,
            platformShareBps: 2_000,
            devBuyBps: 0
        });
    }

    function _spotPrice(address token) internal view returns (uint256) {
        SeraphLaunchpad.LaunchInfo memory info = launchpad.getLaunch(token);
        return ((info.realQuoteReserve + info.phantomQuote) * 1e18) / info.tokenReserve;
    }

    /* ================================================================== */
    /* 1. Multi-Actor Lifecycle Tests                                     */
    /* ================================================================== */

    /**
     * @notice Creator launches tokens with a 5-way fee split and atomic dev buy at
     *         all UI presets: 1% (100 bps), 2% (200 bps), 5% (500 bps), and 10% (1000 bps).
     */
    function test_AtomicDevBuy_1_2_5_10Percent() public {
        uint16[4] memory devBuyTiers = [uint16(100), uint16(200), uint16(500), uint16(1_000)];

        for (uint256 i = 0; i < devBuyTiers.length; i++) {
            uint16 bps = devBuyTiers[i];
            SeraphLaunchpad.LaunchParams memory p = _baseParams();
            p.devBuyBps = bps;
            // Ensure no buyback burn during dev buy check so initial supply cap math is exact
            p.creatorShareBps = 2_500;
            p.buybackShareBps = 0;
            p.dividendsShareBps = 2_500;
            p.liquidityShareBps = 2_500;
            p.platformShareBps = 2_500;

            uint256 quotedEth = launchpad.quoteDevBuy(p.totalSupply, p.buyFeeBps, bps);
            uint256 extraEth = 0.25 ether;
            uint256 creatorBalBefore = creator.balance;

            vm.prank(creator);
            address token = launchpad.launch{value: quotedEth + extraEth}(p);

            uint256 expectedTokens = (p.totalSupply * bps) / 10_000;
            assertEq(
                LaunchToken(token).balanceOf(creator),
                expectedTokens,
                "Creator should receive exact devBuyBps share of totalSupply"
            );

            // Creator should have been refunded the extraEth
            uint256 ethSpent = creatorBalBefore - creator.balance;
            assertLe(ethSpent, quotedEth, "ETH spent should not exceed quoteDevBuy");
            assertApproxEqAbs(ethSpent, quotedEth, 2, "ETH spent should match quoteDevBuy within 2 wei");
        }
    }

    /**
     * @notice Multiple buyers (Buyer1, Buyer2, Buyer3, Whale) buy and sell in sequence on
     *         the bonding curve, verifying spot price rises strictly monotonically on buys
     *         and falls strictly monotonically on sells.
     */
    function test_MultiActor_MonotonicPriceAndReserveTracking() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        // Use Creator-backed preset so reserve changes come purely from curve trades
        p.creatorShareBps = 10_000;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 0;
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address token = launchpad.launch{value: LAUNCH_FEE}(p);

        uint256 p0 = _spotPrice(token);

        vm.prank(buyer1);
        uint256 out1 = launchpad.buy{value: 0.4 ether}(token, 1, buyer1);
        uint256 p1 = _spotPrice(token);
        assertGt(p1, p0, "Price must increase after Buyer1 buy");

        vm.prank(buyer2);
        uint256 out2 = launchpad.buy{value: 0.4 ether}(token, 1, buyer2);
        uint256 p2 = _spotPrice(token);
        assertGt(p2, p1, "Price must increase after Buyer2 buy");
        assertLt(out2, out1, "Equal ETH buy at higher curve point must yield fewer tokens");

        vm.prank(buyer3);
        uint256 out3 = launchpad.buy{value: 0.4 ether}(token, 1, buyer3);
        uint256 p3 = _spotPrice(token);
        assertGt(p3, p2, "Price must increase after Buyer3 buy");
        assertLt(out3, out2, "Equal ETH buy at higher curve point must yield fewer tokens");

        // Sequential sells must monotonically decrease spot price
        vm.startPrank(buyer3);
        LaunchToken(token).approve(address(launchpad), out3);
        launchpad.sell(token, out3, 1, buyer3);
        vm.stopPrank();
        uint256 pAfterSell3 = _spotPrice(token);
        assertLt(pAfterSell3, p3, "Price must fall after Buyer3 sell");

        vm.startPrank(buyer2);
        LaunchToken(token).approve(address(launchpad), out2);
        launchpad.sell(token, out2, 1, buyer2);
        vm.stopPrank();
        uint256 pAfterSell2 = _spotPrice(token);
        assertLt(pAfterSell2, pAfterSell3, "Price must fall after Buyer2 sell");

        vm.startPrank(buyer1);
        LaunchToken(token).approve(address(launchpad), out1);
        launchpad.sell(token, out1, 1, buyer1);
        vm.stopPrank();
        uint256 pAfterSell1 = _spotPrice(token);
        assertLt(pAfterSell1, pAfterSell2, "Price must fall after Buyer1 sell");
        assertEq(pAfterSell1, p0, "Price must return to initial spot price when all tokens sold back");
    }

    /**
     * @notice Buyers transfer LaunchToken directly wallet-to-wallet between dividend distributions,
     *         verifying accDividendPerShare, rewardDebt, pendingDividends, and claimableDividends
     *         remain 100% accurate and never over- or under-pay after secondary ERC-20 transfers.
     */
    function test_MultiActor_SecondaryTransfersBetweenDividends() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 250;
        p.sellFeeBps = 250;
        p.creatorShareBps = 0;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 10_000; // 100% of creator fee to dividends
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        // Step 1: Buyer1 buys 1 ETH worth. Since Buyer1 is the only holder when dividends distribute
        // on this buy, Buyer1 gets 100% of the first dividend distribution.
        vm.prank(buyer1);
        uint256 b1Tokens = launchpad.buy{value: 1 ether}(tokenAddr, 1, buyer1);
        uint256 div1 = (1 ether * 250) / 10_000; // 0.025 ether
        assertApproxEqAbs(token.claimableDividends(buyer1), div1, 1, "Buyer1 should own 100% of div1");
        assertEq(token.claimableDividends(buyer2), 0, "Buyer2 has no tokens yet");
        assertEq(token.claimableDividends(buyer3), 0, "Buyer3 has no tokens yet");

        // Step 2: Buyer1 transfers exactly 50% of their tokens directly to Buyer2 (secondary transfer)
        uint256 halfB1 = b1Tokens / 2;
        vm.prank(buyer1);
        token.transfer(buyer2, halfB1);

        // Verify transfer checkpointed Buyer1's div1 into pendingDividends and set Buyer2's rewardDebt
        assertApproxEqAbs(token.claimableDividends(buyer1), div1, 1, "Buyer1 claimable unchanged after transfer");
        assertEq(token.claimableDividends(buyer2), 0, "Buyer2 must not retroactively earn div1");
        assertApproxEqAbs(
            token.rewardDebt(buyer2),
            (token.balanceOf(buyer2) * token.accDividendPerShare()) / 1e36,
            1,
            "Buyer2 rewardDebt must match current accDividendPerShare"
        );

        // Step 3: Distribute 1.0 ETH directly into dividends while Buyer1 and Buyer2 hold 50% / 50%
        token.distributeDividends{value: 1 ether}();

        assertApproxEqAbs(
            token.claimableDividends(buyer1),
            div1 + 0.5 ether,
            2,
            "Buyer1 should have div1 + 50% of 1 ETH"
        );
        assertApproxEqAbs(
            token.claimableDividends(buyer2),
            0.5 ether,
            2,
            "Buyer2 should have 50% of 1 ETH"
        );

        // Step 4: Buyer2 transfers half of their tokens (25% of circulating) to Buyer3,
        // and Buyer1 transfers ALL of their remaining tokens (50% of circulating) to Buyer3!
        // Now Buyer1 holds 0%, Buyer2 holds 25%, Buyer3 holds 75%.
        uint256 halfB2 = token.balanceOf(buyer2) / 2;
        vm.prank(buyer2);
        token.transfer(buyer3, halfB2);

        uint256 remB1 = token.balanceOf(buyer1);
        vm.prank(buyer1);
        token.transfer(buyer3, remB1);

        assertEq(token.balanceOf(buyer1), 0, "Buyer1 balance should be 0");
        assertEq(token.rewardDebt(buyer1), 0, "Buyer1 rewardDebt should be 0");
        assertEq(token.claimableDividends(buyer3), 0, "Buyer3 has 0 claimable right after receiving tokens");

        // Step 5: Distribute 2.0 ETH in dividends while Buyer1 = 0%, Buyer2 = 25%, Buyer3 = 75%
        token.distributeDividends{value: 2 ether}();

        {
            uint256 expectedB1 = div1 + 0.5 ether; // 0% of the 2 ETH
            uint256 expectedB2 = 0.5 ether + 0.5 ether; // 0.5 ETH from round 2 + 25% of 2 ETH
            uint256 expectedB3 = 1.5 ether; // 75% of 2 ETH

            assertApproxEqAbs(token.claimableDividends(buyer1), expectedB1, 3, "Buyer1 claimable after exit");
            assertApproxEqAbs(token.claimableDividends(buyer2), expectedB2, 3, "Buyer2 claimable (25% share)");
            assertApproxEqAbs(token.claimableDividends(buyer3), expectedB3, 3, "Buyer3 claimable (75% share)");
        }

        // Step 6: All three holders claim and verify exact ETH payouts
        {
            uint256 b1EthBefore = buyer1.balance;
            uint256 b2EthBefore = buyer2.balance;
            uint256 b3EthBefore = buyer3.balance;

            uint256 claimed1 = token.claimDividends(buyer1);
            uint256 claimed2 = token.claimDividends(buyer2);
            uint256 claimed3 = token.claimDividends(buyer3);

            assertEq(buyer1.balance - b1EthBefore, claimed1);
            assertEq(buyer2.balance - b2EthBefore, claimed2);
            assertEq(buyer3.balance - b3EthBefore, claimed3);

            uint256 totalDistributed = div1 + 3 ether;
            assertApproxEqAbs(
                claimed1 + claimed2 + claimed3,
                totalDistributed,
                5,
                "Sum of claimed dividends must conserve total distributed ETH"
            );
            assertLe(claimed1 + claimed2 + claimed3, totalDistributed, "Never overpay dividends");
        }

        // Buyer1 exited completely so pendingDividends[buyer1] and balanceOf(buyer1) are both 0
        assertEq(token.claimableDividends(buyer1), 0);
        assertEq(token.pendingDividends(buyer1), 0);
        assertEq(token.pendingDividends(buyer2), 0);
        assertEq(token.pendingDividends(buyer3), 0);
        vm.expectRevert("LaunchToken: nothing to claim");
        token.claimDividends(buyer1);
    }

    /**
     * @notice Creator and Platform both call claimFees() multiple times as trades occur
     *         and verify exact wei balances at every checkpoint.
     */
    function test_MultiActor_RepeatedFeeClaims_CreatorAndPlatform() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 200; // 2.0%
        p.sellFeeBps = 250; // 2.5%
        // 60% creator, 40% platform share of creator fee
        p.creatorShareBps = 6_000;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 0;
        p.liquidityShareBps = 0;
        p.platformShareBps = 4_000;

        vm.prank(creator);
        address token = launchpad.launch{value: LAUNCH_FEE}(p);

        // Checkpoint 1: After launch + Buyer1 buy (1 ETH)
        vm.prank(buyer1);
        uint256 b1Tokens = launchpad.buy{value: 1 ether}(token, 1, buyer1);

        // Buy 1 ETH: platformFee = 0.01 ETH, creatorFee = 0.02 ETH (40% = 0.008 ETH to platform, 60% = 0.012 ETH to creator)
        uint256 expectedPlat1 = LAUNCH_FEE + 0.01 ether + 0.008 ether;
        uint256 expectedCreator1 = 0.012 ether;

        assertEq(launchpad.claimableFees(platformWallet), expectedPlat1, "Platform claimable after trade 1");
        assertEq(launchpad.claimableFees(creatorFeeWallet), expectedCreator1, "Creator claimable after trade 1");

        uint256 platBal1 = platformWallet.balance;
        vm.prank(platformWallet);
        uint256 platClaim1 = launchpad.claimFees();
        assertEq(platClaim1, expectedPlat1);
        assertEq(platformWallet.balance - platBal1, expectedPlat1);
        assertEq(launchpad.claimableFees(platformWallet), 0);

        uint256 creatorBal1 = creatorFeeWallet.balance;
        vm.prank(creatorFeeWallet);
        uint256 creatorClaim1 = launchpad.claimFees();
        assertEq(creatorClaim1, expectedCreator1);
        assertEq(creatorFeeWallet.balance - creatorBal1, expectedCreator1);
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0);

        // Checkpoint 2: Buyer2 buys 2 ETH, Buyer1 sells half their tokens
        vm.prank(buyer2);
        launchpad.buy{value: 2 ether}(token, 1, buyer2);

        (, uint256 sellPlatFee, uint256 sellCreatorFee) = launchpad.quoteSell(token, b1Tokens / 2);
        vm.startPrank(buyer1);
        LaunchToken(token).approve(address(launchpad), b1Tokens / 2);
        launchpad.sell(token, b1Tokens / 2, 1, buyer1);
        vm.stopPrank();

        uint256 buy2Plat = 0.02 ether + (0.04 ether * 4_000) / 10_000;
        uint256 buy2Creator = (0.04 ether * 6_000) / 10_000;
        uint256 sellCreatorToPlat = (sellCreatorFee * 4_000) / 10_000;
        uint256 sellCreatorToCreator = sellCreatorFee - sellCreatorToPlat;

        uint256 expectedPlat2 = buy2Plat + sellPlatFee + sellCreatorToPlat;
        uint256 expectedCreator2 = buy2Creator + sellCreatorToCreator;

        assertEq(launchpad.claimableFees(platformWallet), expectedPlat2, "Platform claimable after trade 2 & 3");
        assertEq(launchpad.claimableFees(creatorFeeWallet), expectedCreator2, "Creator claimable after trade 2 & 3");

        uint256 platBal2 = platformWallet.balance;
        vm.prank(platformWallet);
        launchpad.claimFees();
        assertEq(platformWallet.balance - platBal2, expectedPlat2);

        uint256 creatorBal2 = creatorFeeWallet.balance;
        vm.prank(creatorFeeWallet);
        launchpad.claimFees();
        assertEq(creatorFeeWallet.balance - creatorBal2, expectedCreator2);

        // Immediate re-claim must revert with NothingToClaim
        vm.prank(creatorFeeWallet);
        vm.expectRevert(SeraphLaunchpad.NothingToClaim.selector);
        launchpad.claimFees();
    }

    /**
     * @notice Complete end-to-end multi-actor lifecycle combining 5-way split launch,
     *         5% atomic dev buy, multi-buyer curve buys, secondary transfers, partial sells,
     *         Whale graduation, and post-graduation trading.
     */
    function test_FullMultiActorLifecycle_EndToEnd() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.devBuyBps = 500; // 5% dev buy
        uint256 reqEth = launchpad.quoteDevBuy(p.totalSupply, p.buyFeeBps, p.devBuyBps);

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: reqEth}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        assertEq(token.balanceOf(creator), (DEFAULT_SUPPLY * 500) / 10_000);

        // Buyer1, Buyer2, Buyer3 buy on bonding curve
        vm.prank(buyer1);
        uint256 b1 = launchpad.buy{value: 0.5 ether}(tokenAddr, 1, buyer1);
        vm.prank(buyer2);
        uint256 b2 = launchpad.buy{value: 0.8 ether}(tokenAddr, 1, buyer2);
        vm.prank(buyer3);
        uint256 b3 = launchpad.buy{value: 1.0 ether}(tokenAddr, 1, buyer3);

        assertGt(b1, 0);
        assertGt(b2, 0);
        assertGt(b3, 0);

        // Buyer1 transfers 25% of tokens to Buyer2
        vm.prank(buyer1);
        token.transfer(buyer2, b1 / 4);

        // Buyer2 sells a portion on the curve
        vm.startPrank(buyer2);
        token.approve(address(launchpad), b2 / 3);
        launchpad.sell(tokenAddr, b2 / 3, 1, buyer2);
        vm.stopPrank();

        // Whale graduates the curve
        vm.prank(whale);
        launchpad.buy{value: 10 ether}(tokenAddr, 1, whale);
        assertTrue(launchpad.getLaunch(tokenAddr).graduated, "Token should be graduated after Whale buy");

        // Post-graduation trades by Buyer3 and Buyer1
        vm.prank(buyer3);
        launchpad.buy{value: 0.5 ether}(tokenAddr, 1, buyer3);

        // Everyone claims dividends and fees
        assertGt(token.claimDividends(creator), 0);
        assertGt(token.claimDividends(buyer1), 0);
        assertGt(token.claimDividends(buyer2), 0);
        assertGt(token.claimDividends(buyer3), 0);

        vm.prank(creatorFeeWallet);
        assertGt(launchpad.claimFees(), 0);
        vm.prank(platformWallet);
        assertGt(launchpad.claimFees(), 0);
    }

    /* ================================================================== */
    /* 2. All 6 UI Fee Presets Tested End-to-End                          */
    /* ================================================================== */

    /**
     * @notice Preset 1: Creator-backed (100% creator share).
     */
    function test_Preset1_CreatorBacked_100PercentCreator() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 200; // 2.0%
        p.sellFeeBps = 250; // 2.5%
        p.creatorShareBps = 10_000;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 0;
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address token = launchpad.launch{value: LAUNCH_FEE}(p);

        vm.prank(buyer1);
        uint256 tokensOut = launchpad.buy{value: 1 ether}(token, 1, buyer1);

        // 2.0% of 1 ETH = 0.02 ETH to creatorFeeWallet; 1.0% = 0.01 ETH + LAUNCH_FEE to platform
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0.02 ether);
        assertEq(launchpad.claimableFees(platformWallet), LAUNCH_FEE + 0.01 ether);
        assertEq(LaunchToken(token).totalSupply(), DEFAULT_SUPPLY, "No tokens should be burned");
        assertEq(LaunchToken(token).accDividendPerShare(), 0, "No dividends should be distributed");

        // Buyer1 sells half
        (, uint256 sellPlatFee, uint256 sellCreatorFee) = launchpad.quoteSell(token, tokensOut / 2);
        vm.startPrank(buyer1);
        LaunchToken(token).approve(address(launchpad), tokensOut / 2);
        launchpad.sell(token, tokensOut / 2, 1, buyer1);
        vm.stopPrank();

        assertEq(launchpad.claimableFees(creatorFeeWallet), 0.02 ether + sellCreatorFee);
        assertEq(launchpad.claimableFees(platformWallet), LAUNCH_FEE + 0.01 ether + sellPlatFee);
    }

    /**
     * @notice Preset 2: Diamond hands (100% holder dividends claimed by 3 different holders
     *         strictly proportional to their token balances: 50%, 30%, 20%).
     */
    function test_Preset2_DiamondHands_100PercentDividends_ThreeHolders() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 250; // 2.5%
        p.sellFeeBps = 250; // 2.5%
        p.creatorShareBps = 0;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 10_000; // 100% holder dividends
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        // Whale acquires an initial batch and distributes exact 50% / 30% / 20% balances to Buyer1, Buyer2, Buyer3
        vm.prank(whale);
        uint256 totalBatch = launchpad.buy{value: 1 ether}(tokenAddr, 1, whale);
        // Whale claims the initial buy dividend so we measure clean proportional accrual across the 3 holders
        token.claimDividends(whale);

        uint256 share1 = (totalBatch * 50) / 100;
        uint256 share2 = (totalBatch * 30) / 100;
        uint256 share3 = totalBatch - share1 - share2; // 20%

        vm.startPrank(whale);
        token.transfer(buyer1, share1);
        token.transfer(buyer2, share2);
        token.transfer(buyer3, share3);
        vm.stopPrank();

        assertEq(token.balanceOf(whale), 0);
        assertEq(token.eligibleSupply(), totalBatch);

        // NowCreator buys and immediately sells to generate trading fee dividends while Buyer1/2/3 hold 50:30:20
        // Note: on Creator's buy, Creator also holds tokens during that buy's dividend distribution.
        // To test pure 50:30:20 proportional distribution from both trading and direct dividends:
        vm.prank(creator);
        uint256 creatorTokens = launchpad.buy{value: 2 ether}(tokenAddr, 1, creator);

        vm.startPrank(creator);
        token.approve(address(launchpad), creatorTokens);
        launchpad.sell(tokenAddr, creatorTokens, 1, creator);
        vm.stopPrank();

        uint256 claim1 = token.claimDividends(buyer1);
        uint256 claim2 = token.claimDividends(buyer2);
        uint256 claim3 = token.claimDividends(buyer3);

        // Verify 50 : 30 : 20 ratio among Buyer1, Buyer2, Buyer3
        // claim1 / 50 == claim2 / 30 == claim3 / 20
        assertApproxEqRel(claim1 * 30, claim2 * 50, 1e12, "Buyer1 and Buyer2 dividends must be in 50:30 ratio");
        assertApproxEqRel(claim1 * 20, claim3 * 50, 1e12, "Buyer1 and Buyer3 dividends must be in 50:20 ratio");
        assertApproxEqRel(claim2 * 20, claim3 * 30, 1e12, "Buyer2 and Buyer3 dividends must be in 30:20 ratio");
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0, "Creator feeWallet gets 0 in Diamond Hands preset");
    }

    /**
     * @notice Preset 3: Deflationary (100% buyback and burn — verify totalSupply() decreases
     *         on every single buy and every single sell).
     */
    function test_Preset3_Deflationary_100PercentBuybackAndBurn() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 250; // 2.5%
        p.sellFeeBps = 250; // 2.5%
        p.creatorShareBps = 0;
        p.buybackShareBps = 10_000; // 100% buyback & burn
        p.dividendsShareBps = 0;
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        uint256 supply0 = token.totalSupply();
        assertEq(supply0, DEFAULT_SUPPLY);

        // Buy 1 by Buyer1
        vm.prank(buyer1);
        uint256 b1 = launchpad.buy{value: 0.5 ether}(tokenAddr, 1, buyer1);
        uint256 supply1 = token.totalSupply();
        assertLt(supply1, supply0, "totalSupply must decrease on Buy 1");

        // Buy 2 by Buyer2
        vm.prank(buyer2);
        uint256 b2 = launchpad.buy{value: 0.7 ether}(tokenAddr, 1, buyer2);
        uint256 supply2 = token.totalSupply();
        assertLt(supply2, supply1, "totalSupply must decrease on Buy 2");

        // Sell 1 by Buyer1
        vm.startPrank(buyer1);
        token.approve(address(launchpad), b1 / 2);
        launchpad.sell(tokenAddr, b1 / 2, 1, buyer1);
        vm.stopPrank();
        uint256 supply3 = token.totalSupply();
        assertLt(supply3, supply2, "totalSupply must decrease on Sell 1");

        // Sell 2 by Buyer2
        vm.startPrank(buyer2);
        token.approve(address(launchpad), b2 / 2);
        launchpad.sell(tokenAddr, b2 / 2, 1, buyer2);
        vm.stopPrank();
        uint256 supply4 = token.totalSupply();
        assertLt(supply4, supply3, "totalSupply must decrease on Sell 2");

        // Verify token balance of launchpad equals tokenReserve
        assertEq(
            token.balanceOf(address(launchpad)),
            launchpad.getLaunch(tokenAddr).tokenReserve,
            "Launchpad token balance must equal tokenReserve after burns"
        );
    }

    /**
     * @notice Preset 4: Auto-LP (100% pool liquidity — verify realQuoteReserve grows faster
     *         and raises floor price compared to a baseline token with identical trades).
     */
    function test_Preset4_AutoLP_100PercentPoolLiquidity() public {
        // Launch Token A: Auto-LP (100% liquidityShareBps)
        SeraphLaunchpad.LaunchParams memory pAuto = _baseParams();
        pAuto.symbol = "AUTOLP";
        pAuto.buyFeeBps = 250;
        pAuto.sellFeeBps = 250;
        pAuto.creatorShareBps = 0;
        pAuto.buybackShareBps = 0;
        pAuto.dividendsShareBps = 0;
        pAuto.liquidityShareBps = 10_000;
        pAuto.platformShareBps = 0;

        // Launch Token B: Creator-backed baseline (100% creatorShareBps)
        SeraphLaunchpad.LaunchParams memory pBase = _baseParams();
        pBase.symbol = "BASE";
        pBase.buyFeeBps = 250;
        pBase.sellFeeBps = 250;
        pBase.creatorShareBps = 10_000;
        pBase.buybackShareBps = 0;
        pBase.dividendsShareBps = 0;
        pBase.liquidityShareBps = 0;
        pBase.platformShareBps = 0;

        vm.startPrank(creator);
        address autoToken = launchpad.launch{value: LAUNCH_FEE}(pAuto);
        address baseToken = launchpad.launch{value: LAUNCH_FEE}(pBase);
        vm.stopPrank();

        // Buyer1 buys 1 ETH on both tokens
        vm.startPrank(buyer1);
        uint256 outAuto1 = launchpad.buy{value: 1 ether}(autoToken, 1, buyer1);
        uint256 outBase1 = launchpad.buy{value: 1 ether}(baseToken, 1, buyer1);
        vm.stopPrank();
        assertEq(outAuto1, outBase1, "First buy outputs are equal before Auto-LP fee compounds");

        // Verify realQuoteReserve is already higher on Auto-LP token by the 2.5% creator fee (0.025 ETH)
        assertEq(
            launchpad.getLaunch(autoToken).realQuoteReserve,
            launchpad.getLaunch(baseToken).realQuoteReserve + 0.025 ether,
            "Auto-LP realQuoteReserve must grow by netQuoteIn + creatorFee"
        );

        // Buyer2 buys and sells on both tokens to compound Auto-LP
        vm.startPrank(buyer2);
        uint256 outAuto2 = launchpad.buy{value: 1.5 ether}(autoToken, 1, buyer2);
        uint256 outBase2 = launchpad.buy{value: 1.5 ether}(baseToken, 1, buyer2);

        LaunchToken(autoToken).approve(address(launchpad), outAuto2);
        launchpad.sell(autoToken, outAuto2, 1, buyer2);

        LaunchToken(baseToken).approve(address(launchpad), outBase2);
        launchpad.sell(baseToken, outBase2, 1, buyer2);
        vm.stopPrank();

        // Compare Buyer1's floor sell quote for outAuto1 (which equals outBase1)
        (uint256 floorQuoteAuto, , ) = launchpad.quoteSell(autoToken, outAuto1);
        (uint256 floorQuoteBase, , ) = launchpad.quoteSell(baseToken, outBase1);

        assertGt(
            launchpad.getLaunch(autoToken).realQuoteReserve,
            launchpad.getLaunch(baseToken).realQuoteReserve,
            "Auto-LP realQuoteReserve must be strictly greater"
        );
        assertGt(floorQuoteAuto, floorQuoteBase, "Auto-LP must raise floor sell value for holders");
    }

    /**
     * @notice Preset 5: Send to Seraph (100% to platform — verify claimableFees(platform)
     *         receives 1% mandatory + full creator fee on every buy and sell).
     */
    function test_Preset5_SendToSeraph_100PercentPlatform() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 250; // 2.5%
        p.sellFeeBps = 150; // 1.5%
        p.creatorShareBps = 0;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 0;
        p.liquidityShareBps = 0;
        p.platformShareBps = 10_000; // 100% to Seraph platform

        vm.prank(creator);
        address token = launchpad.launch{value: LAUNCH_FEE}(p);

        vm.prank(buyer1);
        uint256 tokensOut = launchpad.buy{value: 2 ether}(token, 1, buyer1);

        // On 2 ETH buy: mandatory 1% = 0.02 ETH, creator 2.5% = 0.05 ETH -> total 0.07 ETH to platform
        uint256 expectedAfterBuy = LAUNCH_FEE + 0.02 ether + 0.05 ether;
        assertEq(launchpad.claimableFees(platformWallet), expectedAfterBuy);
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0);

        // On sell: mandatory 1% + creator 1.5% = 2.5% total to platform
        (, uint256 sellPlatFee, uint256 sellCreatorFee) = launchpad.quoteSell(token, tokensOut);
        vm.startPrank(buyer1);
        LaunchToken(token).approve(address(launchpad), tokensOut);
        launchpad.sell(token, tokensOut, 1, buyer1);
        vm.stopPrank();

        assertEq(
            launchpad.claimableFees(platformWallet),
            expectedAfterBuy + sellPlatFee + sellCreatorFee,
            "Platform must receive 100% of mandatory + creator fees on buy and sell"
        );
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0);
    }

    /**
     * @notice Preset 6: Custom arbitrary 5-way splits across FixedPool, BondingCurve, and SeraphPool.
     */
    function test_Preset6_CustomArbitraryFiveWaySplit_AllModels() public {
        SeraphLaunchpad.LaunchModel[3] memory models = [
            SeraphLaunchpad.LaunchModel.FixedPool,
            SeraphLaunchpad.LaunchModel.BondingCurve,
            SeraphLaunchpad.LaunchModel.SeraphPool
        ];

        for (uint256 i = 0; i < models.length; i++) {
            SeraphLaunchpad.LaunchParams memory p = _baseParams();
            p.model = models[i];
            p.buyFeeBps = 237; // 2.37%
            p.sellFeeBps = 189; // 1.89%
            // Non-round 5-way split summing to 10_000
            p.creatorShareBps = 3_333;
            p.buybackShareBps = 1_777;
            p.dividendsShareBps = 2_222;
            p.liquidityShareBps = 1_555;
            p.platformShareBps = 1_113;

            uint256 platBefore = launchpad.claimableFees(platformWallet);
            uint256 creatorBefore = launchpad.claimableFees(creatorFeeWallet);

            vm.prank(creator);
            address token = launchpad.launch{value: LAUNCH_FEE}(p);

            vm.prank(buyer1);
            uint256 out = launchpad.buy{value: 1.234567 ether}(token, 1, buyer1);

            uint256 platFee = (1.234567 ether * 100) / 10_000;
            uint256 creatorFee = (1.234567 ether * 237) / 10_000;

            uint256 toPlatform = (creatorFee * 1_113) / 10_000;
            uint256 toLiquidity = (creatorFee * 1_555) / 10_000;
            uint256 toBuyback = (creatorFee * 1_777) / 10_000;
            uint256 toDividends = (creatorFee * 2_222) / 10_000;
            uint256 toCreator = creatorFee - toPlatform - toLiquidity - toBuyback - toDividends;

            assertEq(
                launchpad.claimableFees(platformWallet) - platBefore,
                LAUNCH_FEE + platFee + toPlatform,
                "Exact platform fee accounting on custom split"
            );
            assertEq(
                launchpad.claimableFees(creatorFeeWallet) - creatorBefore,
                toCreator,
                "Exact creator fee accounting including remainder wei on custom split"
            );
            assertApproxEqAbs(
                LaunchToken(token).claimableDividends(buyer1),
                toDividends,
                1,
                "Exact dividend distribution on custom split"
            );
            assertLt(LaunchToken(token).totalSupply(), DEFAULT_SUPPLY, "Buyback burned tokens on custom split");
            assertGt(out, 0);
        }
    }

    /* ================================================================== */
    /* 3. Graduation & Post-Graduation Pool Trading                       */
    /* ================================================================== */

    /**
     * @notice Whale sends a huge ETH buy (50 ETH) that far exceeds sellableTokens(),
     *         verifying fill is clamped to sellableTokens(), excess ETH is refunded in the same tx,
     *         graduated becomes true, reservedTokens unlocks into the pool, and Buyer1/Buyer2/Buyer3
     *         can buy and sell continuously in the graduated pool.
     */
    function test_WhaleGraduation_ClampingRefundUnlockAndPostGradTrading() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        // Zero out buyback burn so we can verify exact 75% curve sellable tokens and 25% reserved unlock
        p.creatorShareBps = 5_000;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 2_500;
        p.liquidityShareBps = 0;
        p.platformShareBps = 2_500;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        SeraphLaunchpad.LaunchInfo memory infoBefore = launchpad.getLaunch(tokenAddr);
        assertFalse(infoBefore.graduated);
        uint256 reservedBefore = infoBefore.reservedTokens;
        uint256 sellableBefore = launchpad.sellableTokens(tokenAddr);
        assertEq(reservedBefore, DEFAULT_SUPPLY / 4, "25% of supply reserved for pool");
        assertEq(sellableBefore, (DEFAULT_SUPPLY * 3) / 4, "75% of supply sellable on curve");

        // Buyer1 buys a small amount first
        vm.prank(buyer1);
        uint256 b1CurveTokens = launchpad.buy{value: 0.5 ether}(tokenAddr, 1, buyer1);
        uint256 remainingCurveTokens = launchpad.sellableTokens(tokenAddr);
        assertEq(remainingCurveTokens, sellableBefore - b1CurveTokens);

        // Whale sends 50 ETH (way more than needed to buy remainingCurveTokens)
        {
            uint256 whaleBalBefore = whale.balance;
            (uint256 quotedWhaleTokens, , , uint256 quotedRefund) = launchpad.quoteBuy(tokenAddr, 50 ether);
            assertEq(quotedWhaleTokens, remainingCurveTokens, "Quote must clamp to remaining sellableTokens");
            assertGt(quotedRefund, 45 ether, "Excess ETH (>45 ETH) must be quoted as refund");

            vm.prank(whale);
            uint256 whaleTokensOut = launchpad.buy{value: 50 ether}(tokenAddr, remainingCurveTokens, whale);

            assertEq(whaleTokensOut, remainingCurveTokens, "Whale fill clamped to exact sellableTokens");
            assertEq(whaleBalBefore - whale.balance, 50 ether - quotedRefund, "Whale refunded excess ETH in same tx");
        }

        // Verify graduation state & reservedTokens unlocked into pool
        {
            SeraphLaunchpad.LaunchInfo memory infoGrad = launchpad.getLaunch(tokenAddr);
            assertTrue(infoGrad.graduated, "graduated must be true");
            assertEq(infoGrad.reservedTokens, 0, "reservedTokens must unlock to 0");
            assertEq(infoGrad.tokenReserve, reservedBefore, "Pool tokenReserve now holds the unlocked reservedTokens");
            assertEq(launchpad.sellableTokens(tokenAddr), reservedBefore, "Unlocked reserve is now sellable in pool");
            assertEq(launchpad.graduationProgressBps(tokenAddr), 10_000, "Graduation progress must be 100%");
        }

        // Post-graduation continuous trading by Buyer1, Buyer2, Buyer3
        {
            vm.prank(buyer2);
            uint256 b2PoolTokens = launchpad.buy{value: 1 ether}(tokenAddr, 1, buyer2);
            assertGt(b2PoolTokens, 0, "Buyer2 can buy from graduated pool");

            vm.prank(buyer3);
            uint256 b3PoolTokens = launchpad.buy{value: 1.5 ether}(tokenAddr, 1, buyer3);
            assertGt(b3PoolTokens, 0, "Buyer3 can buy from graduated pool");

            // Buyer1 sells their curve tokens into the graduated pool at profit
            uint256 b1EthBefore = buyer1.balance;
            vm.startPrank(buyer1);
            token.approve(address(launchpad), b1CurveTokens);
            uint256 b1NetOut = launchpad.sell(tokenAddr, b1CurveTokens, 1, buyer1);
            vm.stopPrank();
            assertGt(b1NetOut, 0.5 ether, "Early curve Buyer1 sells into graduated pool at profit");
            assertEq(buyer1.balance - b1EthBefore, b1NetOut);

            // Buyer2 and Buyer3 also sell portions in the graduated pool
            vm.startPrank(buyer2);
            token.approve(address(launchpad), b2PoolTokens / 2);
            launchpad.sell(tokenAddr, b2PoolTokens / 2, 1, buyer2);
            vm.stopPrank();

            vm.startPrank(buyer3);
            token.approve(address(launchpad), b3PoolTokens / 2);
            launchpad.sell(tokenAddr, b3PoolTokens / 2, 1, buyer3);
            vm.stopPrank();
        }
    }

    /**
     * @notice Verifies graduate() permissionless fallback and revert conditions.
     */
    function test_PermissionlessGraduateFallback_AndReverts() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        vm.prank(creator);
        address token = launchpad.launch{value: LAUNCH_FEE}(p);

        // Cannot call graduate() before threshold reached
        vm.expectRevert(SeraphLaunchpad.NotReadyToGraduate.selector);
        launchpad.graduate(token);

        // Unknown token reverts
        vm.expectRevert(SeraphLaunchpad.UnknownToken.selector);
        launchpad.graduate(makeAddr("nonExistentToken"));

        // Graduate via Whale buy, then verify calling graduate() again reverts with AlreadyGraduated
        vm.prank(whale);
        launchpad.buy{value: 10 ether}(token, 1, whale);
        assertTrue(launchpad.getLaunch(token).graduated);

        vm.expectRevert(SeraphLaunchpad.AlreadyGraduated.selector);
        launchpad.graduate(token);
    }

    /* ================================================================== */
    /* 4. Adversarial & Edge-Case Scenarios                               */
    /* ================================================================== */

    /**
     * @notice Malicious creator sets feeWallet to a contract that reverts on receive():
     *         verify trades (buy and sell) still succeed because fees use pull-escrow (claimFees()),
     *         preventing honeypot attacks, and verify claimFees() reverts only for the malicious feeWallet.
     */
    function test_Adversarial_RevertingFeeWallet_PullEscrowPreventsHoneypot() public {
        RevertingEthReceiver maliciousFeeWallet = new RevertingEthReceiver();

        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.feeWallet = address(maliciousFeeWallet);
        p.buyFeeBps = 250;
        p.sellFeeBps = 250;
        p.creatorShareBps = 8_000;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 2_000;
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);

        // Buyer1, Buyer2, Buyer3 buy and sell freely without reverting despite malicious feeWallet
        vm.prank(buyer1);
        uint256 b1 = launchpad.buy{value: 1 ether}(tokenAddr, 1, buyer1);

        vm.prank(buyer2);
        uint256 b2 = launchpad.buy{value: 1.5 ether}(tokenAddr, 1, buyer2);

        // Buyer1 can sell without being honeypotted!
        vm.startPrank(buyer1);
        LaunchToken(tokenAddr).approve(address(launchpad), b1);
        uint256 netOut1 = launchpad.sell(tokenAddr, b1, 1, buyer1);
        vm.stopPrank();
        assertGt(netOut1, 0, "Buyer1 must be able to sell even when creator feeWallet reverts on ETH receive");

        // Buyer2 can sell and claim dividends without issue
        vm.startPrank(buyer2);
        LaunchToken(tokenAddr).approve(address(launchpad), b2 / 2);
        uint256 netOut2 = launchpad.sell(tokenAddr, b2 / 2, 1, buyer2);
        uint256 divClaimed2 = LaunchToken(tokenAddr).claimDividends(buyer2);
        vm.stopPrank();
        assertGt(netOut2, 0);
        assertGt(divClaimed2, 0);

        // Platform can still claim its fees
        vm.prank(platformWallet);
        uint256 platClaimed = launchpad.claimFees();
        assertGt(platClaimed, 0);

        // Only the malicious feeWallet itself fails when attempting to claim its accrued fees
        assertGt(launchpad.claimableFees(address(maliciousFeeWallet)), 0);
        vm.expectRevert(SeraphLaunchpad.TransferFailed.selector);
        maliciousFeeWallet.tryClaimFees(launchpad);
    }

    /**
     * @notice Adversarial dividend holder that rejects ETH on receive() cannot block trades
     *         or prevent honest holders from claiming dividends.
     */
    function test_Adversarial_RevertingDividendHolder_DoesNotBlockOtherHoldersOrTrades() public {
        RevertingEthReceiver griefingHolder = new RevertingEthReceiver();

        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.dividendsShareBps = 10_000;
        p.creatorShareBps = 0;
        p.buybackShareBps = 0;
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        // Buyer1 buys and sends tokens to griefingHolder
        vm.prank(buyer1);
        launchpad.buy{value: 1 ether}(tokenAddr, 1, address(griefingHolder));

        // Buyer2 buys and sells while griefingHolder holds tokens
        vm.prank(buyer2);
        uint256 b2 = launchpad.buy{value: 1 ether}(tokenAddr, 1, buyer2);

        vm.startPrank(buyer2);
        token.approve(address(launchpad), b2 / 2);
        launchpad.sell(tokenAddr, b2 / 2, 1, buyer2);
        vm.stopPrank();

        // Honest Buyer2 claims dividends without issue
        uint256 b2Div = token.claimDividends(buyer2);
        assertGt(b2Div, 0);

        // Griefing holder fails only when it calls claimDividends itself
        vm.expectRevert("LaunchToken: ETH transfer failed");
        griefingHolder.tryClaimDividends(token);
    }

    /**
     * @notice Slippage protection reverts (minTokensOut on buy, minQuoteOut on sell),
     *         including sandwich / frontrun simulation.
     */
    function test_EdgeCase_SlippageProtectionReverts_BuyAndSell() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        vm.prank(creator);
        address token = launchpad.launch{value: LAUNCH_FEE}(p);

        // 1. Direct minTokensOut check on buy
        (uint256 expectedTokens, , , ) = launchpad.quoteBuy(token, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(SeraphLaunchpad.SlippageExceeded.selector);
        launchpad.buy{value: 1 ether}(token, expectedTokens + 1, buyer1);

        // 2. Frontrun simulation on buy: Buyer1 quotes with 1% slippage tolerance, Whale frontruns
        uint256 minOutWith1PctSlippage = (expectedTokens * 99) / 100;
        vm.prank(whale);
        launchpad.buy{value: 2 ether}(token, 1, whale);

        vm.prank(buyer1);
        vm.expectRevert(SeraphLaunchpad.SlippageExceeded.selector);
        launchpad.buy{value: 1 ether}(token, minOutWith1PctSlippage, buyer1);

        // Buyer1 succeeds when quoting fresh after Whale's buy
        (uint256 freshQuote, , , ) = launchpad.quoteBuy(token, 1 ether);
        vm.prank(buyer1);
        uint256 b1Tokens = launchpad.buy{value: 1 ether}(token, freshQuote, buyer1);

        // 3. Direct minQuoteOut check on sell
        (uint256 expectedEthOut, , ) = launchpad.quoteSell(token, b1Tokens);
        vm.startPrank(buyer1);
        LaunchToken(token).approve(address(launchpad), b1Tokens);
        vm.expectRevert(SeraphLaunchpad.SlippageExceeded.selector);
        launchpad.sell(token, b1Tokens, expectedEthOut + 1, buyer1);
        vm.stopPrank();

        // 4. Frontrun simulation on sell: Whale dumps before Buyer1 sells
        uint256 whaleTokens = LaunchToken(token).balanceOf(whale);
        vm.startPrank(whale);
        LaunchToken(token).approve(address(launchpad), whaleTokens);
        launchpad.sell(token, whaleTokens, 1, whale);
        vm.stopPrank();

        vm.prank(buyer1);
        vm.expectRevert(SeraphLaunchpad.SlippageExceeded.selector);
        launchpad.sell(token, b1Tokens, (expectedEthOut * 95) / 100, buyer1);
    }

    /**
     * @notice Zero-fee creator launch (buyFeeBps = 0, sellFeeBps = 0) still charges
     *         the mandatory 1% (100 bps) Seraph platform fee on every buy and sell.
     */
    function test_EdgeCase_ZeroFeeCreatorLaunch_MandatoryPlatformFeeAlwaysCharged() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 0;
        p.sellFeeBps = 0;

        vm.prank(creator);
        address token = launchpad.launch{value: LAUNCH_FEE}(p);

        uint256 platExpected = LAUNCH_FEE;

        // Buyer1 buys 1 ETH
        vm.prank(buyer1);
        uint256 b1 = launchpad.buy{value: 1 ether}(token, 1, buyer1);
        platExpected += 0.01 ether; // 1% of 1 ETH
        assertEq(launchpad.claimableFees(platformWallet), platExpected, "1% platform fee on Buyer1 buy");
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0, "0 creator fee");

        // Buyer2 buys 2.5 ETH
        vm.prank(buyer2);
        uint256 b2 = launchpad.buy{value: 2.5 ether}(token, 1, buyer2);
        platExpected += 0.025 ether; // 1% of 2.5 ETH
        assertEq(launchpad.claimableFees(platformWallet), platExpected, "1% platform fee on Buyer2 buy");

        // Buyer1 sells all b1 tokens
        (uint256 netOut1, uint256 sellPlat1, uint256 sellCreator1) = launchpad.quoteSell(token, b1);
        assertEq(sellCreator1, 0, "Creator sell fee must be 0");
        assertGt(sellPlat1, 0, "Platform sell fee must be > 0");
        // Verify grossQuoteOut = netOut1 + sellPlat1 and sellPlat1 == grossQuoteOut / 100
        assertEq(sellPlat1, (netOut1 + sellPlat1) / 100, "Platform sell fee must be exact 1% (100 bps)");

        vm.startPrank(buyer1);
        LaunchToken(token).approve(address(launchpad), b1);
        launchpad.sell(token, b1, netOut1, buyer1);
        vm.stopPrank();

        platExpected += sellPlat1;
        assertEq(launchpad.claimableFees(platformWallet), platExpected, "1% platform fee accrued on sell");
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0);
        assertGt(b2, 0);
    }

    /**
     * @notice Edge case: When all circulating tokens are burned by holders so eligibleSupply() == 0,
     *         or on the last holder's full sell, dividends fall back to creator feeWallet instead of reverting.
     */
    function test_EdgeCase_ZeroEligibleSupplyOnFullSell_DividendsFallbackToCreator() public {
        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 200;
        p.sellFeeBps = 200;
        p.creatorShareBps = 0;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 10_000; // 100% dividends
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        // Buyer1 buys as sole holder; on buy, tokens are transferred BEFORE _distributeFees,
        // so Buyer1 receives the buy dividend.
        vm.prank(buyer1);
        uint256 b1 = launchpad.buy{value: 1 ether}(tokenAddr, 1, buyer1);
        assertEq(launchpad.claimableFees(creatorFeeWallet), 0);
        assertApproxEqAbs(token.claimableDividends(buyer1), 0.02 ether, 1);

        // Now Buyer1 sells 100% of circulating tokens back to the launchpad!
        // During sell(), tokens are transferred to launchpad BEFORE _distributeFees(),
        // making eligibleSupply() == 0. The contract must gracefully route the sell dividend to toCreator!
        (, , uint256 sellCreatorFee) = launchpad.quoteSell(tokenAddr, b1);
        vm.startPrank(buyer1);
        token.approve(address(launchpad), b1);
        launchpad.sell(tokenAddr, b1, 1, buyer1);
        vm.stopPrank();

        assertEq(token.eligibleSupply(), 0);
        assertEq(
            launchpad.claimableFees(creatorFeeWallet),
            sellCreatorFee,
            "When eligibleSupply is 0 on full sell, dividend share must fall back to creator feeWallet"
        );
    }

    /* ================================================================== */
    /* 5. Multi-Actor Fuzz Tests                                          */
    /* ================================================================== */

    /**
     * @notice Fuzz test across 5 random traders buying, transferring, and selling random amounts
     *         with fuzzed fee rates, verifying Launchpad ETH solvency and reserve invariants.
     */
    function testFuzz_FiveTraders_RandomBuysSellsAndSolvency(
        uint96[5] memory rawBuys,
        uint16 buyFeeBps,
        uint16 sellFeeBps,
        uint16 sellFracBps
    ) public {
        address tokenAddr;
        {
            SeraphLaunchpad.LaunchParams memory p = _baseParams();
            p.buyFeeBps = uint16(bound(buyFeeBps, 0, 250));
            p.sellFeeBps = uint16(bound(sellFeeBps, 0, 250));

            vm.prank(creator);
            tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        }

        address[5] memory traders = [buyer1, buyer2, buyer3, creator, whale];

        // All 5 traders buy random ETH amounts
        for (uint256 i = 0; i < 5; i++) {
            uint256 buyAmt = bound(uint256(rawBuys[i]), 0.01 ether, 2.5 ether);
            if (launchpad.sellableTokens(tokenAddr) > 0) {
                (uint256 qOut, , , ) = launchpad.quoteBuy(tokenAddr, buyAmt);
                if (qOut > 0) {
                    vm.prank(traders[i]);
                    launchpad.buy{value: buyAmt}(tokenAddr, 1, traders[i]);
                }
            }
        }

        // Secondary wallet-to-wallet transfers between traders
        {
            uint256 bal0 = LaunchToken(tokenAddr).balanceOf(traders[0]);
            if (bal0 > 2) {
                vm.prank(traders[0]);
                LaunchToken(tokenAddr).transfer(traders[1], bal0 / 2);
            }
        }

        // All 5 traders sell a fuzzed fraction of their holdings
        uint256 boundedSellFrac = bound(uint256(sellFracBps), 500, 10_000);
        for (uint256 i = 0; i < 5; i++) {
            uint256 bal = LaunchToken(tokenAddr).balanceOf(traders[i]);
            uint256 sellAmt = (bal * boundedSellFrac) / 10_000;
            if (sellAmt > 0) {
                (uint256 netOut, , ) = launchpad.quoteSell(tokenAddr, sellAmt);
                if (netOut > 0) {
                    vm.startPrank(traders[i]);
                    LaunchToken(tokenAddr).approve(address(launchpad), sellAmt);
                    launchpad.sell(tokenAddr, sellAmt, 1, traders[i]);
                    vm.stopPrank();
                }
            }
        }

        // Verify Launchpad ETH solvency: balance must cover realQuoteReserve + all claimableFees
        SeraphLaunchpad.LaunchInfo memory info = launchpad.getLaunch(tokenAddr);
        uint256 totalLiabilities = info.realQuoteReserve +
            launchpad.claimableFees(platformWallet) +
            launchpad.claimableFees(creatorFeeWallet);

        assertEq(
            address(launchpad).balance,
            totalLiabilities,
            "Launchpad ETH balance must exactly equal realQuoteReserve + claimableFees"
        );
        assertEq(
            LaunchToken(tokenAddr).balanceOf(address(launchpad)),
            info.tokenReserve,
            "Launchpad token balance must exactly equal tokenReserve"
        );
    }

    /**
     * @notice Fuzz test verifying dividend conservation across random multi-actor buys,
     *         secondary transfers, and claims.
     */
    function testFuzz_MultiHolderDividendConservation_WithTransfers(
        uint96 rawBuy1,
        uint96 rawBuy2,
        uint96 rawBuy3,
        uint16 transferBps1,
        uint16 transferBps2
    ) public {
        uint256 bAmt1 = bound(uint256(rawBuy1), 0.05 ether, 1.0 ether);
        uint256 bAmt2 = bound(uint256(rawBuy2), 0.05 ether, 1.0 ether);
        uint256 bAmt3 = bound(uint256(rawBuy3), 0.05 ether, 1.0 ether);
        transferBps1 = uint16(bound(transferBps1, 0, 10_000));
        transferBps2 = uint16(bound(transferBps2, 0, 10_000));

        SeraphLaunchpad.LaunchParams memory p = _baseParams();
        p.buyFeeBps = 250;
        p.sellFeeBps = 250;
        p.creatorShareBps = 0;
        p.buybackShareBps = 0;
        p.dividendsShareBps = 10_000;
        p.liquidityShareBps = 0;
        p.platformShareBps = 0;

        vm.prank(creator);
        address tokenAddr = launchpad.launch{value: LAUNCH_FEE}(p);
        LaunchToken token = LaunchToken(tokenAddr);

        vm.prank(buyer1);
        launchpad.buy{value: bAmt1}(tokenAddr, 1, buyer1);

        // Buyer1 transfers a random fraction to Buyer3 before Buyer2 buys
        uint256 t1 = (token.balanceOf(buyer1) * transferBps1) / 10_000;
        if (t1 > 0) {
            vm.prank(buyer1);
            token.transfer(buyer3, t1);
        }

        vm.prank(buyer2);
        launchpad.buy{value: bAmt2}(tokenAddr, 1, buyer2);

        // Buyer2 transfers a random fraction to Buyer3 before Buyer3 buys
        uint256 t2 = (token.balanceOf(buyer2) * transferBps2) / 10_000;
        if (t2 > 0) {
            vm.prank(buyer2);
            token.transfer(buyer3, t2);
        }

        vm.prank(buyer3);
        launchpad.buy{value: bAmt3}(tokenAddr, 1, buyer3);

        uint256 totalDivPool = address(token).balance;
        uint256 c1 = token.claimableDividends(buyer1);
        uint256 c2 = token.claimableDividends(buyer2);
        uint256 c3 = token.claimableDividends(buyer3);

        assertApproxEqAbs(
            c1 + c2 + c3,
            totalDivPool,
            15,
            "Total claimable dividends must match LaunchToken ETH balance within integer rounding dust"
        );
    }
}

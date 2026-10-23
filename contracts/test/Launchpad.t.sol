// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/Launchpad.sol";

contract LaunchpadTest is Test {
    SeraphLaunchpad public pad;

    address public platform = makeAddr("seraphPlatform");
    address public creator = makeAddr("creator");
    address public feeWallet = makeAddr("feeWallet");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant SUPPLY = 1_000_000_000e18;
    uint256 public constant LAUNCH_FEE = 0.001 ether;

    function setUp() public {
        pad = new SeraphLaunchpad(platform, LAUNCH_FEE);
        vm.deal(creator, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _defaultParams() internal view returns (SeraphLaunchpad.LaunchParams memory) {
        return SeraphLaunchpad.LaunchParams({
            name: "Alpha Token",
            symbol: "ALPHA",
            description: "Test launch on Seraph Launchpad",
            image: "ipfs://alpha",
            website: "https://seraphprotocol.tech",
            twitter: "@seraph",
            telegram: "@seraph_tg",
            model: SeraphLaunchpad.LaunchModel.BondingCurve,
            totalSupply: SUPPLY,
            feeWallet: feeWallet,
            buyFeeBps: 250,          // 2.5% creator buy fee
            sellFeeBps: 250,         // 2.5% creator sell fee
            creatorShareBps: 10000,  // 100% to creator
            buybackShareBps: 0,
            dividendsShareBps: 0,
            liquidityShareBps: 0,
            platformShareBps: 0,
            devBuyBps: 0
        });
    }

    function test_LaunchAllThreeModels() public {
        SeraphLaunchpad.LaunchParams memory p = _defaultParams();

        vm.startPrank(creator);
        p.model = SeraphLaunchpad.LaunchModel.FixedPool;
        address tFixed = pad.launch{value: LAUNCH_FEE}(p);

        p.model = SeraphLaunchpad.LaunchModel.BondingCurve;
        address tCurve = pad.launch{value: LAUNCH_FEE}(p);

        p.model = SeraphLaunchpad.LaunchModel.SeraphPool;
        address tSeraph = pad.launch{value: LAUNCH_FEE}(p);
        vm.stopPrank();

        assertEq(pad.totalLaunches(), 3);
        assertEq(pad.claimableFees(platform), LAUNCH_FEE * 3);

        SeraphLaunchpad.LaunchInfo memory i1 = pad.getLaunch(tFixed);
        SeraphLaunchpad.LaunchInfo memory i2 = pad.getLaunch(tCurve);
        SeraphLaunchpad.LaunchInfo memory i3 = pad.getLaunch(tSeraph);

        assertEq(uint8(i1.model), uint8(SeraphLaunchpad.LaunchModel.FixedPool));
        assertTrue(i1.graduated);

        assertEq(uint8(i2.model), uint8(SeraphLaunchpad.LaunchModel.BondingCurve));
        assertFalse(i2.graduated);
        assertEq(i2.reservedTokens, (SUPPLY * 1.5 ether) / 6.0 ether); // 25% reserved for pool

        assertEq(uint8(i3.model), uint8(SeraphLaunchpad.LaunchModel.SeraphPool));
        assertTrue(i3.graduated);
    }

    function test_LaunchValidationReverts() public {
        SeraphLaunchpad.LaunchParams memory p = _defaultParams();
        vm.startPrank(creator);

        // Fee rate > 2.5% (250 bps)
        p.buyFeeBps = 300;
        vm.expectRevert(SeraphLaunchpad.InvalidFeeRate.selector);
        pad.launch{value: LAUNCH_FEE}(p);
        p.buyFeeBps = 250;

        // Fee split != 100% (10000 bps)
        p.creatorShareBps = 5000;
        vm.expectRevert(SeraphLaunchpad.InvalidFeeSplit.selector);
        pad.launch{value: LAUNCH_FEE}(p);
        p.creatorShareBps = 10000;

        // Dev buy > 10% (1000 bps)
        p.devBuyBps = 1500;
        vm.expectRevert(SeraphLaunchpad.InvalidDevBuy.selector);
        pad.launch{value: LAUNCH_FEE}(p);
        vm.stopPrank();
    }

    function test_AtomicDevBuyAndCapRefund() public {
        SeraphLaunchpad.LaunchParams memory p = _defaultParams();
        p.devBuyBps = 500; // 5% dev buy

        uint256 quotedEth = pad.quoteDevBuy(SUPPLY, p.buyFeeBps, p.devBuyBps);
        uint256 balBefore = creator.balance;

        // Send extra ETH above what 5% requires; excess must be refunded
        vm.prank(creator);
        address token = pad.launch{value: quotedEth + 1 ether}(p);

        uint256 spent = balBefore - creator.balance;
        assertApproxEqAbs(spent, quotedEth, 2);
        assertEq(LaunchToken(token).balanceOf(creator), (SUPPLY * 500) / 10000);
    }

    function test_FiveWayFeeSplitAndMandatoryPlatformFee() public {
        SeraphLaunchpad.LaunchParams memory p = _defaultParams();
        // Custom 5-way split: 20% each (creator, buyback, dividends, liquidity, platform)
        p.creatorShareBps = 2000;
        p.buybackShareBps = 2000;
        p.dividendsShareBps = 2000;
        p.liquidityShareBps = 2000;
        p.platformShareBps = 2000;

        vm.prank(creator);
        address token = pad.launch{value: LAUNCH_FEE}(p);
        LaunchToken tk = LaunchToken(token);

        // Alice buys with 1 ETH:
        // Mandatory platform fee = 1% (0.01 ETH)
        // Creator fee = 2.5% (0.025 ETH), split 20% (0.005 ETH) to each of the 5 buckets
        vm.prank(alice);
        uint256 aliceTokens = pad.buy{value: 1 ether}(token, 0, alice);
        assertGt(aliceTokens, 0);

        // Platform got LAUNCH_FEE + 0.01 ETH (mandatory 1%) + 0.005 ETH (20% of creator fee)
        assertEq(pad.claimableFees(platform), LAUNCH_FEE + 0.015 ether);
        // Creator feeWallet got 0.005 ETH (20% of creator fee)
        assertEq(pad.claimableFees(feeWallet), 0.005 ether);
        // Buyback & burn reduced totalSupply
        assertLt(tk.totalSupply(), SUPPLY);

        // Alice (the circulating holder) can claim her 0.005 ETH holder dividend
        uint256 claimable = tk.claimableDividends(alice);
        assertApproxEqAbs(claimable, 0.005 ether, 1e6);

        uint256 aliceEthBefore = alice.balance;
        vm.prank(alice);
        tk.claimDividends(alice);
        assertEq(alice.balance - aliceEthBefore, claimable);

        // Fee recipients can claim their ETH
        uint256 feeWalletBefore = feeWallet.balance;
        vm.prank(feeWallet);
        pad.claimFees();
        assertEq(feeWallet.balance - feeWalletBefore, 0.005 ether);
    }

    function test_BondingCurveGraduationAndLockedPoolTrading() public {
        SeraphLaunchpad.LaunchParams memory p = _defaultParams();
        vm.prank(creator);
        address token = pad.launch{value: LAUNCH_FEE}(p);
        LaunchToken tk = LaunchToken(token);

        // Alice buys part of the curve
        vm.prank(alice);
        pad.buy{value: 2 ether}(token, 0, alice);
        assertGt(pad.graduationProgressBps(token), 0);
        assertLt(pad.graduationProgressBps(token), 10000);

        // Bob sends 10 ETH (more than needed to finish the 4.5 ETH curve);
        // curve clamps fill to remaining sellableTokens, refunds excess ETH, and graduates
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        pad.buy{value: 10 ether}(token, 0, bob);

        SeraphLaunchpad.LaunchInfo memory info = pad.getLaunch(token);
        assertTrue(info.graduated);
        assertEq(info.reservedTokens, 0);
        assertGe(info.realQuoteReserve, 4.5 ether);
        // Bob was refunded well over 5 ETH
        assertGt(bob.balance, bobBefore - 5 ether);
        assertEq(pad.graduationProgressBps(token), 10000);

        // Post-graduation: trading continues seamlessly in the locked pool
        vm.prank(alice);
        uint256 postGradBuy = pad.buy{value: 0.5 ether}(token, 0, alice);
        assertGt(postGradBuy, 0);

        uint256 sellAmt = tk.balanceOf(alice) / 2;
        vm.startPrank(alice);
        tk.approve(address(pad), sellAmt);
        uint256 ethOut = pad.sell(token, sellAmt, 0, alice);
        vm.stopPrank();
        assertGt(ethOut, 0);
    }
}

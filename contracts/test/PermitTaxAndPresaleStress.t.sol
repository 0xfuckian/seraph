// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/Presale.sol";
import "./MockERC20.sol";

/**
 * @title PermitTaxAndPresaleStressTest
 * @notice Security & stress test suite covering:
 *         1. EIP-2612 `permit()` cryptographic security and sell-tax interaction.
 *         2. `SeraphToken` supply conservation, burns (`burn`, `burnFrom`, `burnFees`), and bridge hooks.
 *         3. 20-buyer multi-tier, multi-currency `SeraphPresale` stress test with dynamic ETH/USD pricing
 *            and full 14-day cliff + 12-month vesting schedule verification.
 */
contract PermitTaxAndPresaleStressTest is Test {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    SeraphToken internal token;
    SeraphPresale internal presale;
    MockERC20 internal usdt;
    MockERC20 internal usdc;

    address internal treasury = makeAddr("treasury");
    address internal privacyPool = makeAddr("privacyPool");
    address internal bridge = makeAddr("bridge");

    uint256 internal ownerPk = 0xA11CE;
    address internal ownerAddr;
    uint256 internal spenderPk = 0xB0B;
    address internal spenderAddr;
    address internal recipient = makeAddr("recipient");

    uint256 internal tgeTime;

    function setUp() public {
        ownerAddr = vm.addr(ownerPk);
        spenderAddr = vm.addr(spenderPk);

        usdt = new MockERC20("Tether USD", "USDT", 6, 100_000_000);
        usdc = new MockERC20("USD Coin", "USDC", 6, 100_000_000);

        token = new SeraphToken(privacyPool, treasury, address(0));

        tgeTime = block.timestamp + 7 days;
        presale = new SeraphPresale(address(token), treasury, address(usdt), address(usdc), tgeTime);

        vm.startPrank(treasury);
        token.setPresale(address(presale));
        token.setMinter(bridge, true);
        vm.stopPrank();
    }

    /* ====================================================================== */
    /* Helpers                                                                */
    /* ====================================================================== */

    function _signPermit(
        uint256 pk,
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, _nonce, _deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(pk, digest);
    }

    /* ====================================================================== */
    /* 1. EIP-2612 permit() Cryptographic Security                            */
    /* ====================================================================== */

    function test_Permit_ValidSignatureAndTransferFromWithSellTax() public {
        uint256 mintAmount = 10_000e18;
        uint256 permitAmount = 4_000e18;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(treasury);
        token.mint(ownerAddr, mintAmount);

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(ownerPk, ownerAddr, spenderAddr, permitAmount, token.nonces(ownerAddr), deadline);

        token.permit(ownerAddr, spenderAddr, permitAmount, deadline, v, r, s);

        assertEq(token.allowance(ownerAddr, spenderAddr), permitAmount, "Allowance must match permitted value");
        assertEq(token.nonces(ownerAddr), 1, "Owner nonce must increment to 1");

        uint256 supplyBefore = token.totalSupply();
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(spenderAddr);
        token.transferFrom(ownerAddr, recipient, permitAmount);

        // 1% sell tax = 40e18; 50% burned (20e18), 50% to treasury (20e18), 99% to recipient (3,960e18)
        uint256 expectedTax = (permitAmount * token.SELL_TAX_BPS()) / 10000;
        uint256 expectedBurn = (expectedTax * token.BURN_BPS()) / 10000;
        uint256 expectedTreasury = expectedTax - expectedBurn;
        uint256 expectedNet = permitAmount - expectedTax;

        assertEq(token.balanceOf(recipient), expectedNet, "Recipient should receive 99% after 1% sell tax");
        assertEq(token.balanceOf(treasury), treasuryBefore + expectedTreasury, "Treasury should receive 0.5% tax");
        assertEq(token.totalSupply(), supplyBefore - expectedBurn, "Total supply should drop by 0.5% burn");
        assertEq(token.allowance(ownerAddr, spenderAddr), 0, "Allowance should be fully consumed");
    }

    function test_Permit_ReplaySignatureReverts() public {
        uint256 value = 1_000e18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(ownerPk, ownerAddr, spenderAddr, value, token.nonces(ownerAddr), deadline);

        token.permit(ownerAddr, spenderAddr, value, deadline, v, r, s);
        assertEq(token.nonces(ownerAddr), 1);

        // Replaying the identical signature now hashes against nonce = 1, recovering a mismatched address
        vm.expectRevert();
        token.permit(ownerAddr, spenderAddr, value, deadline, v, r, s);
    }

    function test_Permit_ExpiredDeadlineReverts() public {
        uint256 value = 500e18;
        uint256 deadline = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(ownerPk, ownerAddr, spenderAddr, value, token.nonces(ownerAddr), deadline);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        token.permit(ownerAddr, spenderAddr, value, deadline, v, r, s);
    }

    function test_Permit_TamperedValueReverts() public {
        uint256 signedValue = 1_000e18;
        uint256 tamperedValue = 1_000e18 + 1;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(ownerPk, ownerAddr, spenderAddr, signedValue, token.nonces(ownerAddr), deadline);

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        token.permit(ownerAddr, spenderAddr, tamperedValue, deadline, v, r, s);
    }

    function test_Permit_TamperedSpenderReverts() public {
        uint256 value = 1_000e18;
        uint256 deadline = block.timestamp + 1 hours;
        address attacker = makeAddr("attacker");

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(ownerPk, ownerAddr, spenderAddr, value, token.nonces(ownerAddr), deadline);

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        token.permit(ownerAddr, attacker, value, deadline, v, r, s);
    }

    function test_Permit_TamperedOwnerReverts() public {
        uint256 value = 1_000e18;
        uint256 deadline = block.timestamp + 1 hours;
        address otherOwner = makeAddr("otherOwner");

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(ownerPk, ownerAddr, spenderAddr, value, token.nonces(ownerAddr), deadline);

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        token.permit(otherOwner, spenderAddr, value, deadline, v, r, s);
    }

    function test_Permit_WrongPrivateKeyReverts() public {
        uint256 wrongPk = 0xDEAD;
        address wrongSigner = vm.addr(wrongPk);
        uint256 value = 1_000e18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(wrongPk, ownerAddr, spenderAddr, value, token.nonces(ownerAddr), deadline);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, wrongSigner, ownerAddr));
        token.permit(ownerAddr, spenderAddr, value, deadline, v, r, s);
    }

    function test_Permit_SequentialNoncesAndBurnFrom() public {
        vm.prank(treasury);
        token.mint(ownerAddr, 5_000e18);

        uint256 deadline = block.timestamp + 2 hours;

        for (uint256 i = 0; i < 3; i++) {
            uint256 amount = (i + 1) * 1_000e18;
            (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPk, ownerAddr, spenderAddr, amount, i, deadline);
            token.permit(ownerAddr, spenderAddr, amount, deadline, v, r, s);
            assertEq(token.nonces(ownerAddr), i + 1);
            assertEq(token.allowance(ownerAddr, spenderAddr), amount);
        }

        // Spender burns 2,500 SER via burnFrom (burns are tax-exempt)
        uint256 treasuryBefore = token.balanceOf(treasury);
        vm.prank(spenderAddr);
        token.burnFrom(ownerAddr, 2_500e18);

        assertEq(token.balanceOf(ownerAddr), 2_500e18, "Owner balance reduced by exact burnFrom amount");
        assertEq(token.totalSupply(), 2_500e18, "Total supply reduced by exact burnFrom amount");
        assertEq(token.balanceOf(treasury), treasuryBefore, "No sell tax charged on burnFrom");
        assertEq(token.allowance(ownerAddr, spenderAddr), 500e18, "Remaining allowance is 500 SER");
    }

    function testFuzz_Permit_ArbitraryAmountsAndDeadlines(uint256 rawPk, uint256 amount, uint256 timeOffset) public {
        uint256 pk = bound(rawPk, 1, SECP256K1_ORDER - 1);
        address signerAddr = vm.addr(pk);
        vm.assume(
            signerAddr != address(0) && signerAddr != treasury && signerAddr != address(presale)
                && signerAddr != privacyPool && signerAddr != address(token) && signerAddr != recipient
        );

        amount = bound(amount, 1, token.MAX_SUPPLY());
        uint256 deadline = block.timestamp + bound(timeOffset, 0, 3650 days);

        vm.prank(treasury);
        token.mint(signerAddr, amount);

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(pk, signerAddr, spenderAddr, amount, token.nonces(signerAddr), deadline);
        token.permit(signerAddr, spenderAddr, amount, deadline, v, r, s);

        vm.prank(spenderAddr);
        token.transferFrom(signerAddr, recipient, amount);

        uint256 expectedTax = (amount * token.SELL_TAX_BPS()) / 10000;
        uint256 expectedBurn = (expectedTax * token.BURN_BPS()) / 10000;
        uint256 expectedTreasury = expectedTax - expectedBurn;

        assertEq(token.balanceOf(recipient), amount - expectedTax);
        assertEq(token.balanceOf(treasury), expectedTreasury);
        assertEq(token.totalSupply(), amount - expectedBurn);
    }

    /* ====================================================================== */
    /* 2. SeraphToken Supply Conservation, Burns & Bridge Hooks               */
    /* ====================================================================== */

    function test_SupplyConservation_BurnAndBridgeLifecycle() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 totalMinted = 0;
        uint256 totalBurned = 0;

        // Step 1: Mint 1,000,000 SER to Alice
        vm.prank(treasury);
        token.mint(alice, 1_000_000e18);
        totalMinted += 1_000_000e18;
        assertEq(token.totalSupply() + totalBurned, totalMinted);

        // Step 2: Alice transfers 200,000 SER to Bob (sell tax enabled: 1% = 2,000 SER; 1,000 burned, 1,000 to treasury)
        vm.prank(alice);
        token.transfer(bob, 200_000e18);
        totalBurned += 1_000e18;
        assertEq(token.totalSupply() + totalBurned, totalMinted);
        assertEq(token.balanceOf(bob), 198_000e18);
        assertEq(token.balanceOf(treasury), 1_000e18);

        // Step 3: Disable sell tax, Bob transfers 50,000 SER to Alice (0 tax)
        vm.prank(treasury);
        token.setSellTaxEnabled(false);
        vm.prank(bob);
        token.transfer(alice, 50_000e18);
        assertEq(token.totalSupply() + totalBurned, totalMinted);

        // Re-enable sell tax
        vm.prank(treasury);
        token.setSellTaxEnabled(true);

        // Step 4: Direct burn by Alice (10,000 SER)
        vm.prank(alice);
        token.burn(10_000e18);
        totalBurned += 10_000e18;
        assertEq(token.totalSupply() + totalBurned, totalMinted);

        // Step 5: burnFrom on Bob by Alice (20,000 SER)
        vm.prank(bob);
        token.approve(alice, 20_000e18);
        vm.prank(alice);
        token.burnFrom(bob, 20_000e18);
        totalBurned += 20_000e18;
        assertEq(token.totalSupply() + totalBurned, totalMinted);

        // Step 6: Transfer fees to token contract (exempt from sell tax) and call burnFees
        vm.prank(alice);
        token.transfer(address(token), 15_000e18);
        assertEq(token.balanceOf(address(token)), 15_000e18, "Transfer to token contract itself is tax-exempt");
        token.burnFees(15_000e18);
        totalBurned += 15_000e18;
        assertEq(token.totalSupply() + totalBurned, totalMinted);

        // Step 7: Alice locks 100,000 SER for bridge (transfers to treasury without tax)
        uint256 treasuryBeforeLock = token.balanceOf(treasury);
        vm.prank(alice);
        token.lockForBridge(bob, 100_000e18, bytes32(uint256(8453)));
        assertEq(token.balanceOf(treasury), treasuryBeforeLock + 100_000e18, "Bridge lock transfers to treasury untaxed");
        assertEq(token.totalSupply() + totalBurned, totalMinted);

        // Step 8: Bridge mints 75,000 SER to Bob via receiveFromBridge
        vm.prank(bridge);
        token.receiveFromBridge(bob, 75_000e18);
        totalMinted += 75_000e18;
        assertEq(token.totalSupply() + totalBurned, totalMinted);
        assertLe(token.totalSupply(), token.MAX_SUPPLY());
    }

    function test_SupplyConservation_MaxSupplyEnforcementOnMintAndBridge() public {
        address user = makeAddr("user");
        uint256 maxSupply = token.MAX_SUPPLY();

        vm.prank(treasury);
        token.mint(user, maxSupply);
        assertEq(token.totalSupply(), maxSupply);

        // Minting 1 extra wei reverts via mint() and receiveFromBridge()
        vm.prank(treasury);
        vm.expectRevert("SeraphToken: max supply exceeded");
        token.mint(user, 1);

        vm.prank(bridge);
        vm.expectRevert("SeraphToken: max supply exceeded");
        token.receiveFromBridge(user, 1);

        // Burn 500e18 and verify bridge can now mint up to MAX_SUPPLY again
        vm.prank(user);
        token.burn(500e18);
        assertEq(token.totalSupply(), maxSupply - 500e18);

        vm.prank(bridge);
        token.receiveFromBridge(user, 500e18);
        assertEq(token.totalSupply(), maxSupply);
    }

    function testFuzz_SupplyConservation_RandomActionSequence(uint256 seed, uint256[16] memory rawAmounts) public {
        address[4] memory actors = [
            makeAddr("actor0"),
            makeAddr("actor1"),
            makeAddr("actor2"),
            makeAddr("actor3")
        ];

        uint256 totalMinted = 0;
        uint256 totalBurned = 0;

        for (uint256 i = 0; i < 16; i++) {
            uint256 action = uint256(keccak256(abi.encode(seed, i))) % 7;
            address actor = actors[i % 4];
            address counterparty = actors[(i + 1) % 4];

            if (action == 0) {
                // mint
                uint256 headroom = token.MAX_SUPPLY() - token.totalSupply();
                if (headroom > 0) {
                    uint256 amt = bound(rawAmounts[i], 1, headroom > 5_000_000e18 ? 5_000_000e18 : headroom);
                    vm.prank(treasury);
                    token.mint(actor, amt);
                    totalMinted += amt;
                }
            } else if (action == 1) {
                // transfer with current sellTaxEnabled state
                uint256 bal = token.balanceOf(actor);
                if (bal > 0) {
                    uint256 amt = bound(rawAmounts[i], 1, bal);
                    bool taxOn = (rawAmounts[i] & 1) == 1;
                    vm.prank(treasury);
                    token.setSellTaxEnabled(taxOn);

                    vm.prank(actor);
                    token.transfer(counterparty, amt);

                    if (taxOn) {
                        uint256 tax = (amt * token.SELL_TAX_BPS()) / 10000;
                        uint256 burned = (tax * token.BURN_BPS()) / 10000;
                        totalBurned += burned;
                    }
                }
            } else if (action == 2) {
                // burn
                uint256 bal = token.balanceOf(actor);
                if (bal > 0) {
                    uint256 amt = bound(rawAmounts[i], 1, bal);
                    vm.prank(actor);
                    token.burn(amt);
                    totalBurned += amt;
                }
            } else if (action == 3) {
                // burnFrom
                uint256 bal = token.balanceOf(actor);
                if (bal > 0) {
                    uint256 amt = bound(rawAmounts[i], 1, bal);
                    vm.prank(actor);
                    token.approve(counterparty, amt);
                    vm.prank(counterparty);
                    token.burnFrom(actor, amt);
                    totalBurned += amt;
                }
            } else if (action == 4) {
                // transfer to token contract + burnFees
                uint256 bal = token.balanceOf(actor);
                if (bal > 0) {
                    uint256 amt = bound(rawAmounts[i], 1, bal);
                    vm.prank(actor);
                    token.transfer(address(token), amt);
                    token.burnFees(amt);
                    totalBurned += amt;
                }
            } else if (action == 5) {
                // lockForBridge
                uint256 bal = token.balanceOf(actor);
                if (bal > 0) {
                    uint256 amt = bound(rawAmounts[i], 1, bal);
                    vm.prank(actor);
                    token.lockForBridge(counterparty, amt, bytes32(uint256(1)));
                }
            } else {
                // receiveFromBridge
                uint256 headroom = token.MAX_SUPPLY() - token.totalSupply();
                if (headroom > 0) {
                    uint256 amt = bound(rawAmounts[i], 1, headroom > 5_000_000e18 ? 5_000_000e18 : headroom);
                    vm.prank(bridge);
                    token.receiveFromBridge(actor, amt);
                    totalMinted += amt;
                }
            }

            // Invariants checked after every step
            assertEq(token.totalSupply() + totalBurned, totalMinted, "Invariant violated: totalSupply + totalBurned != totalMinted");
            assertLe(token.totalSupply(), token.MAX_SUPPLY(), "Invariant violated: totalSupply > MAX_SUPPLY");

            uint256 sumBalances = token.balanceOf(treasury) + token.balanceOf(address(token))
                + token.balanceOf(actors[0]) + token.balanceOf(actors[1])
                + token.balanceOf(actors[2]) + token.balanceOf(actors[3]);
            assertEq(sumBalances, token.totalSupply(), "Invariant violated: sum of balances != totalSupply");
        }
    }

    /* ====================================================================== */
    /* 3. 20-Buyer Multi-Tier Multi-Currency Presale Stress Test              */
    /* ====================================================================== */

    struct ShadowState {
        uint256 usdtFees;
        uint256 usdcFees;
        uint256 ethFees;
        uint256 raisedUSDT;
        uint256 raisedUSDC;
        uint256 raisedETH;
        uint256 soldTier1;
        uint256 soldTier2;
        uint256 soldTier3;
        uint256[4][20] expectedBuyerTierTotal; // buyerIdx -> tierId (1..3) -> total tokens
    }

    function test_PresaleStress_20Buyers_MultiTierMultiCurrencyAndFullVesting() public {
        address[20] memory buyers;
        address[] memory wl = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            buyers[i] = makeAddr(string(abi.encodePacked("presaleBuyer_", vm.toString(i))));
            wl[i] = buyers[i];
            vm.deal(buyers[i], 100 ether);
            usdt.mint(buyers[i], 500_000 * 1e6);
            usdc.mint(buyers[i], 500_000 * 1e6);

            vm.startPrank(buyers[i]);
            usdt.approve(address(presale), type(uint256).max);
            usdc.approve(address(presale), type(uint256).max);
            vm.stopPrank();
        }

        vm.prank(treasury);
        presale.addToWhitelist(wl);

        ShadowState memory s;

        // ── Phase 1: ETH price = $1,800 (Buyers 0..6) ──
        vm.prank(treasury);
        presale.updateEthUsdPrice(1800);
        assertEq(presale.ethUsdPrice(), 1800);

        // Buyers 0..3: Strategic (Tier 1) with USDT & USDC
        _execStableBuy(buyers[0], 0, 1, 10_000 * 1e6, address(usdt), buyers[19], s);
        _execStableBuy(buyers[1], 1, 1, 15_500 * 1e6, address(usdc), address(0), s);
        _execStableBuy(buyers[2], 2, 1, 8_250 * 1e6, address(usdt), buyers[0], s);
        _execStableBuy(buyers[3], 3, 1, 20_000 * 1e6, address(usdc), address(0), s);

        // Buyers 4..6: Private (Tier 2) with USDT & Public (Tier 3) with ETH @ $1,800
        _execStableBuy(buyers[4], 4, 2, 12_000 * 1e6, address(usdt), address(0), s);
        _execEthBuy(buyers[5], 5, 2.5 ether, false, 1800, s);
        _execEthBuy(buyers[6], 6, 1.75 ether, true, 1800, s); // via direct receive()

        // ── Phase 2: ETH price = $2,500 (Buyers 7..13) ──
        vm.prank(treasury);
        presale.updateEthUsdPrice(2500);
        assertEq(presale.ethUsdPrice(), 2500);

        _execStableBuy(buyers[7], 7, 1, 14_000 * 1e6, address(usdt), address(0), s);
        _execStableBuy(buyers[8], 8, 2, 18_000 * 1e6, address(usdc), buyers[1], s);
        _execStableBuy(buyers[9], 9, 2, 9_900 * 1e6, address(usdt), address(0), s);
        _execStableBuy(buyers[10], 10, 3, 6_400 * 1e6, address(usdc), address(0), s);
        _execEthBuy(buyers[11], 11, 3 ether, false, 2500, s);
        _execEthBuy(buyers[12], 12, 1.2 ether, true, 2500, s); // via direct receive()
        _execStableBuy(buyers[13], 13, 2, 25_000 * 1e6, address(usdc), address(0), s);

        // ── Phase 3: ETH price = $3,200 (Buyers 14..19 + multi-tier repeat buys) ──
        vm.prank(treasury);
        presale.updateEthUsdPrice(3200);
        assertEq(presale.ethUsdPrice(), 3200);

        _execStableBuy(buyers[14], 14, 1, 5_000 * 1e6, address(usdc), address(0), s);
        _execStableBuy(buyers[15], 15, 2, 11_100 * 1e6, address(usdt), address(0), s);
        _execStableBuy(buyers[16], 16, 3, 7_777 * 1e6, address(usdt), address(0), s);
        _execStableBuy(buyers[17], 17, 3, 13_333 * 1e6, address(usdc), address(0), s);
        _execEthBuy(buyers[18], 18, 4 ether, false, 3200, s);
        _execEthBuy(buyers[19], 19, 2.25 ether, true, 3200, s); // via direct receive()

        // Additional multi-tier & repeat purchases for existing buyers
        _execStableBuy(buyers[0], 0, 2, 6_000 * 1e6, address(usdc), address(0), s); // Buyer 0 also in Tier 2
        _execEthBuy(buyers[0], 0, 1 ether, false, 3200, s); // Buyer 0 also in Tier 3
        _execStableBuy(buyers[4], 4, 2, 3_000 * 1e6, address(usdc), address(0), s); // Buyer 4 top-up in Tier 2

        // ── Verify exact fee, raised, and progress accounting ──
        assertEq(presale.totalRaisedUSDT(), s.raisedUSDT, "totalRaisedUSDT mismatch");
        assertEq(presale.totalRaisedUSDC(), s.raisedUSDC, "totalRaisedUSDC mismatch");
        assertEq(presale.totalRaisedETH(), s.raisedETH, "totalRaisedETH mismatch");
        assertEq(presale.totalTokensSold(), s.soldTier1 + s.soldTier2 + s.soldTier3, "totalTokensSold mismatch");

        (uint256 usdtFees, uint256 usdcFees, uint256 ethFees, uint256 totalFeesUSD) = presale.getFeesCollected();
        assertEq(usdtFees, s.usdtFees, "feesCollectedUSDT mismatch");
        assertEq(usdcFees, s.usdcFees, "feesCollectedUSDC mismatch");
        assertEq(ethFees, s.ethFees, "feesCollectedETH mismatch");
        assertEq(
            totalFeesUSD,
            s.usdtFees + s.usdcFees + (s.ethFees * 3200) / 1e18,
            "totalFeesUSD formula mismatch"
        );

        (uint256 sold, uint256 cap) = presale.getProgress();
        assertEq(sold, s.soldTier1 + s.soldTier2 + s.soldTier3, "getProgress sold mismatch");
        assertEq(cap, 25_000_000e18, "getProgress cap must be 25M SER");

        // ── Execute TGE and have all 20 buyers claim TGE allocations ──
        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();
        assertTrue(presale.tgeExecuted());

        _claimAndVerifyTGE(buyers, s);

        // ── During the 14-day cliff, claimVested is a no-op (releases 0 tokens) ──
        vm.warp(tgeTime + 14 days);
        for (uint256 i = 0; i < 20; i++) {
            for (uint256 tierId = 1; tierId <= 2; tierId++) {
                if (s.expectedBuyerTierTotal[i][tierId] > 0) {
                    uint256 balBefore = token.balanceOf(buyers[i]);
                    vm.prank(buyers[i]);
                    presale.claimVested(tierId);
                    assertEq(token.balanceOf(buyers[i]), balBefore, "Zero tokens may vest during cliff");
                }
            }
        }

        // ── Warp across 12 monthly intervals after the 14-day cliff ──
        uint256 cliffEnd = tgeTime + 14 days;
        _runMonthlyVestingClaims(buyers, s, cliffEnd);

        // ── Prove 100.000000% release for all 20 buyers and 0 extra wei claimable ──
        _verifyFinalVestingCompleteness(buyers, s, cliffEnd);

        assertEq(token.totalSupply(), presale.totalTokensSold(), "Total minted SER must equal totalTokensSold to the exact wei");
    }

    function _runMonthlyVestingClaims(
        address[20] memory buyers,
        ShadowState memory s,
        uint256 cliffEnd
    ) internal {
        for (uint256 month = 1; month <= 12; month++) {
            uint256 targetTime = month < 12 ? cliffEnd + (month * 30 days) : cliffEnd + 365 days;
            vm.warp(targetTime);

            for (uint256 i = 0; i < 20; i++) {
                for (uint256 tierId = 1; tierId <= 2; tierId++) {
                    if (s.expectedBuyerTierTotal[i][tierId] > 0) {
                        (,, uint256 releasable) = presale.getBuyerAllocation(buyers[i], tierId);
                        assertGt(releasable, 0, "Should have positive releasable tokens each month");

                        uint256 balBefore = token.balanceOf(buyers[i]);
                        vm.prank(buyers[i]);
                        presale.claimVested(tierId);
                        assertEq(token.balanceOf(buyers[i]) - balBefore, releasable, "Minted amount must match releasable");
                    }
                }
            }
        }
    }

    function _claimAndVerifyTGE(address[20] memory buyers, ShadowState memory s) internal {
        for (uint256 i = 0; i < 20; i++) {
            for (uint256 tierId = 1; tierId <= 3; tierId++) {
                uint256 expectedTotal = s.expectedBuyerTierTotal[i][tierId];
                if (expectedTotal > 0) {
                    (uint256 vTotal,,) = presale.getBuyerAllocation(buyers[i], tierId);
                    assertEq(vTotal, expectedTotal, "Recorded v.total mismatch");

                    vm.prank(buyers[i]);
                    presale.claimInitialAllocation(tierId);

                    uint256 lockupBps = tierId == 1 ? 2500 : (tierId == 2 ? 2000 : 10000);
                    uint256 expectedTge = (expectedTotal * lockupBps) / 10000;
                    (, uint256 tgeClaimed,) = presale.getBuyerAllocation(buyers[i], tierId);
                    assertEq(tgeClaimed, expectedTge, "Initial TGE release mismatch");
                }
            }
        }
    }

    function _verifyFinalVestingCompleteness(
        address[20] memory buyers,
        ShadowState memory s,
        uint256 cliffEnd
    ) internal {
        for (uint256 i = 0; i < 20; i++) {
            uint256 expectedBuyerSum = 0;
            for (uint256 tierId = 1; tierId <= 3; tierId++) {
                uint256 expectedTotal = s.expectedBuyerTierTotal[i][tierId];
                if (expectedTotal > 0) {
                    (uint256 vTotal, uint256 vReleased) = _getVestingTotalAndReleased(buyers[i], tierId);
                    assertEq(vTotal, expectedTotal, "v.total must equal expectedTotal");
                    assertEq(vReleased, vTotal, "Buyer must receive 100.000000% of v.total");
                    expectedBuyerSum += vTotal;

                    (,, uint256 releasableAfter) = presale.getBuyerAllocation(buyers[i], tierId);
                    assertEq(releasableAfter, 0, "Releasable must be 0 after full vesting");

                    // Attempting to claim again reverts
                    vm.warp(cliffEnd + 400 days);
                    vm.prank(buyers[i]);
                    if (tierId == 3) {
                        vm.expectRevert("Presale: no vesting");
                    } else {
                        vm.expectRevert("Presale: nothing to claim");
                    }
                    presale.claimVested(tierId);
                }
            }
            assertEq(token.balanceOf(buyers[i]), expectedBuyerSum, "Buyer token balance must equal exact sum of allocations");
        }
    }

    function _getVestingTotalAndReleased(address buyer, uint256 tierId)
        internal
        view
        returns (uint256 vTotal, uint256 vReleased)
    {
        (vTotal, vReleased,,,,) = presale.vesting(buyer, tierId);
    }

    function test_Permit_TransferFromToExemptDestinationsHasZeroTax() public {
        uint256 amount = 2_000e18;
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(treasury);
        token.mint(ownerAddr, amount * 2);

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(ownerPk, ownerAddr, spenderAddr, amount * 2, token.nonces(ownerAddr), deadline);
        token.permit(ownerAddr, spenderAddr, amount * 2, deadline, v, r, s);

        uint256 supplyBefore = token.totalSupply();

        // TransferFrom to privacyPool is exempt from sell tax
        vm.prank(spenderAddr);
        token.transferFrom(ownerAddr, privacyPool, amount);
        assertEq(token.balanceOf(privacyPool), amount, "PrivacyPool should receive 100% with no tax");

        // TransferFrom to treasury is exempt from sell tax
        uint256 treasuryBefore = token.balanceOf(treasury);
        vm.prank(spenderAddr);
        token.transferFrom(ownerAddr, treasury, amount);
        assertEq(token.balanceOf(treasury) - treasuryBefore, amount, "Treasury should receive 100% with no tax");
        assertEq(token.totalSupply(), supplyBefore, "No tokens burned on tax-exempt transferFrom");
    }

    function test_PresaleStress_DirectReceiveETHAndWhitelistEnforcement() public {
        address unwhitelisted = makeAddr("unwhitelisted");
        vm.deal(unwhitelisted, 10 ether);
        usdt.mint(unwhitelisted, 10_000 * 1e6);

        vm.startPrank(unwhitelisted);
        usdt.approve(address(presale), type(uint256).max);

        // Cannot buy Tier 1 or Tier 2 without KYC whitelist
        vm.expectRevert("Presale: not whitelisted");
        presale.buyWithStablecoin(1, 1_000 * 1e6, address(usdt), address(0));

        vm.expectRevert("Presale: not whitelisted");
        presale.buyWithStablecoin(2, 1_000 * 1e6, address(usdt), address(0));

        // Cannot use buyWithETH on Tier 1 or Tier 2
        vm.expectRevert("Presale: ETH only for Public tier");
        presale.buyWithETH{value: 1 ether}(1);

        vm.expectRevert("Presale: ETH only for Public tier");
        presale.buyWithETH{value: 1 ether}(2);

        // Direct ETH transfer via receive() succeeds for unwhitelisted user and routes to Tier 3 (Public)
        (bool ok,) = address(presale).call{value: 2 ether}("");
        assertTrue(ok, "Direct ETH transfer to receive() should succeed");
        vm.stopPrank();

        uint256 expectedNetEth = 2 ether - (2 ether * 50) / 10000;
        uint256 expectedTokens = (expectedNetEth * presale.ethUsdPrice() * 1e6) / 40000;
        (uint256 total,,) = presale.getBuyerAllocation(unwhitelisted, 3);
        assertEq(total, expectedTokens, "Direct receive() ETH must credit exact Public tier tokens");
    }

    function _execStableBuy(
        address buyer,
        uint256 buyerIdx,
        uint256 tierId,
        uint256 amount,
        address currency,
        address referrer,
        ShadowState memory s
    ) internal {
        uint256 fee = (amount * 50) / 10000;
        uint256 net = amount - fee;
        uint256 price = tierId == 1 ? 20000 : (tierId == 2 ? 30000 : 40000);
        uint256 tokens = (net * 1e18) / price;

        vm.prank(buyer);
        presale.buyWithStablecoin(tierId, amount, currency, referrer);

        if (currency == address(usdt)) {
            s.usdtFees += fee;
            s.raisedUSDT += net;
        } else {
            s.usdcFees += fee;
            s.raisedUSDC += net;
        }

        if (tierId == 1) s.soldTier1 += tokens;
        else if (tierId == 2) s.soldTier2 += tokens;
        else s.soldTier3 += tokens;

        s.expectedBuyerTierTotal[buyerIdx][tierId] += tokens;
    }

    function _execEthBuy(
        address buyer,
        uint256 buyerIdx,
        uint256 ethAmount,
        bool viaReceive,
        uint256 currentEthPrice,
        ShadowState memory s
    ) internal {
        uint256 fee = (ethAmount * 50) / 10000;
        uint256 net = ethAmount - fee;
        uint256 tokens = (net * currentEthPrice * 1e6) / 40000;

        vm.prank(buyer);
        if (viaReceive) {
            (bool ok,) = address(presale).call{value: ethAmount}("");
            require(ok, "Direct ETH receive failed");
        } else {
            presale.buyWithETH{value: ethAmount}(3);
        }

        s.ethFees += fee;
        s.raisedETH += net;
        s.soldTier3 += tokens;
        s.expectedBuyerTierTotal[buyerIdx][3] += tokens;
    }

    function test_PresaleStress_MultiPurchaseAccumulationAndMidSalePriceChanges() public {
        address whale = makeAddr("whale");
        vm.deal(whale, 50 ether);
        usdt.mint(whale, 100_000 * 1e6);
        usdc.mint(whale, 100_000 * 1e6);

        address[] memory wl = new address[](1);
        wl[0] = whale;
        vm.prank(treasury);
        presale.addToWhitelist(wl);

        vm.startPrank(whale);
        usdt.approve(address(presale), type(uint256).max);
        usdc.approve(address(presale), type(uint256).max);
        vm.stopPrank();

        // Buy ETH at $1,800, $2,500, and $3,200
        uint256[3] memory prices = [uint256(1800), uint256(2500), uint256(3200)];
        uint256 expectedTier3Tokens = 0;

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(treasury);
            presale.updateEthUsdPrice(prices[i]);

            uint256 ethIn = (i + 1) * 1 ether;
            uint256 netEth = ethIn - (ethIn * 50) / 10000;
            expectedTier3Tokens += (netEth * prices[i] * 1e6) / 40000;

            vm.prank(whale);
            presale.buyWithETH{value: ethIn}(3);
        }

        (uint256 tier3Total,,) = presale.getBuyerAllocation(whale, 3);
        assertEq(tier3Total, expectedTier3Tokens, "Cumulative Tier 3 tokens across 3 ETH price updates must match");
    }

    function test_PresaleStress_TreasuryWithdrawalsPreserveAccounting() public {
        address buyer = makeAddr("buyerW");
        vm.deal(buyer, 10 ether);
        usdt.mint(buyer, 20_000 * 1e6);
        usdc.mint(buyer, 20_000 * 1e6);

        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);
        usdc.approve(address(presale), type(uint256).max);
        presale.buyWithStablecoin(3, 10_000 * 1e6, address(usdt), address(0));
        presale.buyWithStablecoin(3, 8_000 * 1e6, address(usdc), address(0));
        presale.buyWithETH{value: 4 ether}(3);
        vm.stopPrank();

        uint256 netUsdt = 10_000 * 1e6 - 50 * 1e6;
        uint256 netUsdc = 8_000 * 1e6 - 40 * 1e6;
        uint256 netEth = 4 ether - 0.02 ether;

        uint256 treasuryUsdtBefore = usdt.balanceOf(treasury);
        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        uint256 treasuryEthBefore = treasury.balance;

        vm.startPrank(treasury);
        presale.withdrawStable(netUsdt, address(usdt));
        presale.withdrawStable(netUsdc, address(usdc));
        presale.withdrawETH();
        vm.stopPrank();

        assertEq(usdt.balanceOf(treasury) - treasuryUsdtBefore, netUsdt);
        assertEq(usdc.balanceOf(treasury) - treasuryUsdcBefore, netUsdc);
        assertEq(treasury.balance - treasuryEthBefore, netEth);
        assertEq(presale.totalRaisedETH(), 0, "totalRaisedETH decremented to 0 after full ETH withdrawal");
    }

    function testFuzz_Presale_VestingPrecisionNoDustLeftBehind(uint256 usdtStrategic, uint256 usdcPrivate) public {
        usdtStrategic = bound(usdtStrategic, 100 * 1e6, 50_000 * 1e6);
        usdcPrivate = bound(usdcPrivate, 100 * 1e6, 100_000 * 1e6);

        address buyer = makeAddr("fuzzBuyer");
        usdt.mint(buyer, usdtStrategic);
        usdc.mint(buyer, usdcPrivate);

        address[] memory wl = new address[](1);
        wl[0] = buyer;
        vm.prank(treasury);
        presale.addToWhitelist(wl);

        vm.startPrank(buyer);
        usdt.approve(address(presale), usdtStrategic);
        usdc.approve(address(presale), usdcPrivate);
        presale.buyWithStablecoin(1, usdtStrategic, address(usdt), address(0));
        presale.buyWithStablecoin(2, usdcPrivate, address(usdc), address(0));
        vm.stopPrank();

        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();

        vm.startPrank(buyer);
        presale.claimInitialAllocation(1);
        presale.claimInitialAllocation(2);

        // Claim at arbitrary intermediate points
        vm.warp(tgeTime + 14 days + 73 days);
        presale.claimVested(1);
        presale.claimVested(2);

        vm.warp(tgeTime + 14 days + 219 days);
        presale.claimVested(1);
        presale.claimVested(2);

        // Final claim at exact maturity (14 days cliff + 365 days vesting)
        vm.warp(tgeTime + 14 days + 365 days);
        presale.claimVested(1);
        presale.claimVested(2);
        vm.stopPrank();

        (uint256 total1, uint256 released1,,,,) = presale.vesting(buyer, 1);
        (uint256 total2, uint256 released2,,,,) = presale.vesting(buyer, 2);

        assertEq(released1, total1, "Strategic tier must release 100% with 0 dust");
        assertEq(released2, total2, "Private tier must release 100% with 0 dust");
        assertEq(token.balanceOf(buyer), total1 + total2, "Buyer balance must equal exact total1 + total2");
    }
}

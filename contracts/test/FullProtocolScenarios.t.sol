// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/Presale.sol";
import "../core/PrivacyPool.sol";
import "../core/bridges/CrossEVMBridge.sol";
import "../core/gas/GasRelayer.sol";
import "../modules/messaging/InvoiceRegistry.sol";
import "../modules/ai_payments/UsageVault.sol";
import "../modules/stablecoin/CollateralVault.sol";
import "./MockERC20.sol";

contract MockVerifierScenario is IVerifier {
    bool public shouldPass = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(bytes calldata, uint256[] calldata) external view returns (bool) {
        return shouldPass;
    }
}

/**
 * @title FullProtocolScenariosTest
 * @notice Comprehensive multi-actor scenario suite covering the full Seraph Protocol lifecycle:
 *         1. SeraphPresale multi-tier purchases, referrals, treasury management, TGE & 12-month vesting
 *         2. SeraphToken sell-tax mechanics & PrivacyPool 100-root ring-buffer wrap-around stress tests
 *         3. CrossEVMBridge multi-relayer bonding/slashing, GasRelayer (SER & wXMR), InvoiceRegistry,
 *            UsageVault multi-ticket AI compute settlement, and CollateralVault xUSD lifecycle
 */
contract FullProtocolScenariosTest is Test {
    // Core & Module Contracts
    SeraphToken public ser;
    SeraphPresale public presale;
    PrivacyPool public pool;
    MockVerifierScenario public verifier;
    CrossEVMBridge public bridge;
    GasRelayer public gasRelayer;
    InvoiceRegistry public invoices;
    UsageVault public aiVault;
    CollateralVault public cdpVault;

    // External / Mock Tokens
    MockERC20 public usdt;
    MockERC20 public usdc;
    MockERC20 public wxmr;

    // Protocol Actors
    address public treasury = makeAddr("treasury");
    address public guardian = makeAddr("guardian");
    address public referrer1 = makeAddr("referrer1");
    address public referrer2 = makeAddr("referrer2");

    // 5 Presale Buyers
    address public buyer1 = makeAddr("buyer1"); // Strategic (Tier 1 - USDC)
    address public buyer2 = makeAddr("buyer2"); // Private (Tier 2 - USDT)
    address public buyer3 = makeAddr("buyer3"); // Public (Tier 3 - ETH & receive() fallback)
    address public buyer4 = makeAddr("buyer4"); // Public (Tier 3 - USDC) + Strategic (Tier 1)
    address public buyer5 = makeAddr("buyer5"); // Public (Tier 3 - USDT) + Private (Tier 2)

    // Relayers, Challengers, Recipients & AI Providers
    address public relayerGood = makeAddr("relayerGood");
    address public relayerBad = makeAddr("relayerBad");
    address public challenger = makeAddr("challenger");
    address public freshRecipient1 = makeAddr("freshRecipient1");
    address public freshRecipient2 = makeAddr("freshRecipient2");
    address public aiProvider1 = makeAddr("aiProvider1");
    address public aiProvider2 = makeAddr("aiProvider2");
    address public merchant = makeAddr("merchant");

    // Chain IDs
    bytes32 public constant SERAPH_EVM_ID = keccak256("SERAPH_EVM");
    bytes32 public constant XMR_EVM_ID = keccak256("XMR_EVM");
    bytes32 public constant BASE_LAYER_ID = keccak256("SERAPH_BASE");

    uint256 public tgeTime;

    function setUp() public {
        // 1. Deploy mock currencies
        usdt = new MockERC20("Tether USD", "USDT", 6, 100_000_000);
        usdc = new MockERC20("USD Coin", "USDC", 6, 100_000_000);
        wxmr = new MockERC20("Wrapped Monero", "wXMR", 18, 1_000_000);

        // 2. Deploy core SeraphToken, Verifier, PrivacyPool, and SeraphPresale
        verifier = new MockVerifierScenario();
        ser = new SeraphToken(address(0), treasury, address(0));
        pool = new PrivacyPool(address(ser), treasury, address(verifier), address(verifier));

        tgeTime = block.timestamp + 7 days;
        presale = new SeraphPresale(address(ser), treasury, address(usdt), address(usdc), tgeTime);

        // 3. Deploy CrossEVMBridge, GasRelayer, and First-Party Modules
        bridge = new CrossEVMBridge(address(ser), SERAPH_EVM_ID, guardian);
        gasRelayer = new GasRelayer(address(ser), address(wxmr), 1000e18, 10e18);
        invoices = new InvoiceRegistry();
        aiVault = new UsageVault(address(ser));
        cdpVault = new CollateralVault(address(ser), 2e18); // Initial SER price = $2.00

        // 4. Configure SeraphToken permissions & exemptions via treasury
        vm.startPrank(treasury);
        ser.setPresale(address(presale));
        ser.setPrivacyPool(address(pool));
        ser.setMinter(address(bridge), true);

        // Whitelist all KYC-tier buyers (Strategic Tier 1 & Private Tier 2)
        address[] memory kycBuyers = new address[](4);
        kycBuyers[0] = buyer1;
        kycBuyers[1] = buyer2;
        kycBuyers[2] = buyer4;
        kycBuyers[3] = buyer5;
        presale.addToWhitelist(kycBuyers);
        vm.stopPrank();

        // 5. Fund all 5 buyers and relayers
        address[5] memory buyers = [buyer1, buyer2, buyer3, buyer4, buyer5];
        for (uint256 i = 0; i < buyers.length; i++) {
            vm.deal(buyers[i], 100 ether);
            usdt.mint(buyers[i], 500_000e6);
            usdc.mint(buyers[i], 500_000e6);
            wxmr.mint(buyers[i], 500e18);
        }

        vm.deal(relayerGood, 20 ether);
        vm.deal(relayerBad, 20 ether);
    }

    /* ====================================================================== */
    /* 1. PRESALE FULL MULTI-TIER LIFECYCLE SCENARIOS                         */
    /* ====================================================================== */

    function test_Scenario01_FiveBuyersMultiTierPurchasesAndReferrals() public {
        // Buyer 1: Strategic (Tier 1, $0.02) using 20,000 USDC with referrer1
        vm.startPrank(buyer1);
        usdc.approve(address(presale), 30_000e6);
        presale.buyWithStablecoin(1, 20_000e6, address(usdc), referrer1);
        // Repeat purchase in same tier (10,000 USDC) to verify accumulation
        presale.buyWithStablecoin(1, 10_000e6, address(usdc), referrer1);
        vm.stopPrank();

        // Buyer 2: Private (Tier 2, $0.03) using 30,000 USDT with referrer2
        vm.startPrank(buyer2);
        usdt.approve(address(presale), 45_000e6);
        presale.buyWithStablecoin(2, 30_000e6, address(usdt), referrer2);
        // Repeat purchase in same tier (15,000 USDT)
        presale.buyWithStablecoin(2, 15_000e6, address(usdt), address(0));
        vm.stopPrank();

        // Buyer 3: Public (Tier 3, $0.04) using buyWithETH (2 ETH) + direct ETH transfer via receive() (3 ETH)
        vm.startPrank(buyer3);
        presale.buyWithETH{value: 2 ether}(3);
        (bool ok,) = address(presale).call{value: 3 ether}("");
        assertTrue(ok, "Direct ETH transfer via receive() should succeed");
        vm.stopPrank();

        // Buyer 4: Public (Tier 3, $0.04) with 8,000 USDC + Strategic (Tier 1, $0.02) with 4,000 USDC
        vm.startPrank(buyer4);
        usdc.approve(address(presale), 12_000e6);
        presale.buyWithStablecoin(3, 8_000e6, address(usdc), referrer1);
        presale.buyWithStablecoin(1, 4_000e6, address(usdc), referrer1);
        vm.stopPrank();

        // Buyer 5: Public (Tier 3, $0.04) with 12,000 USDT + Private (Tier 2, $0.03) with 6,000 USDT
        vm.startPrank(buyer5);
        usdt.approve(address(presale), 18_000e6);
        presale.buyWithStablecoin(3, 12_000e6, address(usdt), referrer2);
        presale.buyWithStablecoin(2, 6_000e6, address(usdt), referrer2);
        vm.stopPrank();

        // Verify referrals recorded accurately
        assertEq(presale.referredBy(buyer1), uint256(uint160(referrer1)), "Buyer1 referrer mismatch");
        assertEq(presale.referredBy(buyer2), uint256(uint160(referrer2)), "Buyer2 referrer mismatch");
        assertEq(presale.referredBy(buyer4), uint256(uint160(referrer1)), "Buyer4 referrer mismatch");
        assertEq(presale.referredBy(buyer5), uint256(uint160(referrer2)), "Buyer5 referrer mismatch");

        // Verify accumulated token allocations (net of 0.5% fee):
        // Buyer 1: 30,000 USDC -> 29,850 net / $0.02 = 1,492,500 SER
        (uint256 b1Total,,) = presale.getBuyerAllocation(buyer1, 1);
        assertEq(b1Total, 1_492_500e18, "Buyer1 accumulated Strategic allocation");

        // Buyer 2: 45,000 USDT -> 44,775 net / $0.03 = 1,492,500 SER
        (uint256 b2Total,,) = presale.getBuyerAllocation(buyer2, 2);
        assertEq(b2Total, 1_492_500e18, "Buyer2 accumulated Private allocation");

        // Buyer 3: 5 ETH ($10,000 at $2,000/ETH) -> 4.975 ETH net ($9,950) / $0.04 = 248,750 SER
        (uint256 b3Total,,) = presale.getBuyerAllocation(buyer3, 3);
        assertEq(b3Total, 248_750e18, "Buyer3 accumulated Public ETH allocation");

        // Buyer 4: 8,000 USDC Public -> 7,960 / $0.04 = 199,000 SER; 4,000 USDC Strategic -> 3,980 / $0.02 = 199,000 SER
        (uint256 b4Pub,,) = presale.getBuyerAllocation(buyer4, 3);
        (uint256 b4Strat,,) = presale.getBuyerAllocation(buyer4, 1);
        assertEq(b4Pub, 199_000e18);
        assertEq(b4Strat, 199_000e18);

        // Buyer 5: 12,000 USDT Public -> 11,940 / $0.04 = 298,500 SER; 6,000 USDT Private -> 5,970 / $0.03 = 199,000 SER
        (uint256 b5Pub,,) = presale.getBuyerAllocation(buyer5, 3);
        (uint256 b5Priv,,) = presale.getBuyerAllocation(buyer5, 2);
        assertEq(b5Pub, 298_500e18);
        assertEq(b5Priv, 199_000e18);
    }

    function test_Scenario02_PresaleTreasuryFeeTrackingAndProceedsWithdrawal() public {
        _executeMultiBuyerPurchases();

        // Total gross spent:
        // USDC: 30,000 (buyer1) + 12,000 (buyer4) = 42,000 USDC -> 0.5% fee = 210 USDC, net = 41,790 USDC
        // USDT: 45,000 (buyer2) + 18,000 (buyer5) = 63,000 USDT -> 0.5% fee = 315 USDT, net = 62,685 USDT
        // ETH:  5 ETH (buyer3) -> 0.5% fee = 0.025 ETH, net = 4.975 ETH
        (uint256 usdtFees, uint256 usdcFees, uint256 ethFees,) = presale.getFeesCollected();
        assertEq(usdcFees, 210e6, "USDC 0.5% fee must equal 210 USDC");
        assertEq(usdtFees, 315e6, "USDT 0.5% fee must equal 315 USDT");
        assertEq(ethFees, 0.025 ether, "ETH 0.5% fee must equal 0.025 ETH");

        // Fees were already sent immediately to treasury upon purchase
        assertEq(usdc.balanceOf(treasury), 210e6);
        assertEq(usdt.balanceOf(treasury), 315e6);
        assertEq(treasury.balance, 0.025 ether);

        // Contract holds the net proceeds
        assertEq(usdc.balanceOf(address(presale)), 41_790e6);
        assertEq(usdt.balanceOf(address(presale)), 62_685e6);
        assertEq(address(presale).balance, 4.975 ether);

        // Treasury withdraws all net proceeds
        vm.startPrank(treasury);
        presale.withdrawStable(41_790e6, address(usdc));
        presale.withdrawStable(62_685e6, address(usdt));
        presale.withdrawETH();
        vm.stopPrank();

        assertEq(usdc.balanceOf(treasury), 42_000e6, "Treasury holds 100% of USDC proceeds + fees");
        assertEq(usdt.balanceOf(treasury), 63_000e6, "Treasury holds 100% of USDT proceeds + fees");
        assertEq(treasury.balance, 5 ether, "Treasury holds 100% of ETH proceeds + fees");
        assertEq(presale.totalRaisedETH(), 0, "totalRaisedETH zeroed after withdrawETH");
    }

    function test_Scenario03_TGEExecutionAndInitialAllocationClaimsAllFiveBuyers() public {
        _executeMultiBuyerPurchases();

        // Cannot execute TGE before tgeTimestamp
        vm.prank(treasury);
        vm.expectRevert("Presale: TGE not started");
        presale.executeTGE();

        // Warp to TGE and execute
        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();
        assertTrue(presale.tgeExecuted());

        // Buyer 1 claims Strategic TGE (25% of 1,492,500 = 373,125 SER)
        vm.prank(buyer1);
        presale.claimInitialAllocation(1);
        assertEq(ser.balanceOf(buyer1), 373_125e18, "Strategic buyer1 gets 25% at TGE");

        // Buyer 2 claims Private TGE (20% of 1,492,500 = 298,500 SER)
        vm.prank(buyer2);
        presale.claimInitialAllocation(2);
        assertEq(ser.balanceOf(buyer2), 298_500e18, "Private buyer2 gets 20% at TGE");

        // Buyer 3 claims Public TGE (100% of 248,750 = 248,750 SER)
        vm.prank(buyer3);
        presale.claimInitialAllocation(3);
        assertEq(ser.balanceOf(buyer3), 248_750e18, "Public buyer3 gets 100% at TGE");

        // Buyer 4 claims both Public (100% of 199,000) and Strategic (25% of 199,000 = 49,750)
        vm.startPrank(buyer4);
        presale.claimInitialAllocation(3);
        presale.claimInitialAllocation(1);
        vm.stopPrank();
        assertEq(ser.balanceOf(buyer4), 248_750e18, "Buyer4 receives full Public + 25% Strategic at TGE");

        // Buyer 5 claims both Public (100% of 298,500) and Private (20% of 199,000 = 39,800)
        vm.startPrank(buyer5);
        presale.claimInitialAllocation(3);
        presale.claimInitialAllocation(2);
        vm.stopPrank();
        assertEq(ser.balanceOf(buyer5), 338_300e18, "Buyer5 receives full Public + 20% Private at TGE");

        // Double TGE claim must revert
        vm.prank(buyer1);
        vm.expectRevert("Presale: already claimed");
        presale.claimInitialAllocation(1);
    }

    function test_Scenario04_Full14DayCliffAnd12MonthLinearVestingTo100Percent() public {
        _executeMultiBuyerPurchases();

        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();

        // All 5 buyers claim TGE
        vm.prank(buyer1);
        presale.claimInitialAllocation(1);
        vm.prank(buyer2);
        presale.claimInitialAllocation(2);
        vm.prank(buyer3);
        presale.claimInitialAllocation(3);
        vm.startPrank(buyer4);
        presale.claimInitialAllocation(1);
        presale.claimInitialAllocation(3);
        vm.stopPrank();
        vm.startPrank(buyer5);
        presale.claimInitialAllocation(2);
        presale.claimInitialAllocation(3);
        vm.stopPrank();

        // Warp 10 days into the 14-day cliff: 0 releasable for vested tiers
        vm.warp(tgeTime + 10 days);
        (,, uint256 b1CliffReleasable) = presale.getBuyerAllocation(buyer1, 1);
        (,, uint256 b2CliffReleasable) = presale.getBuyerAllocation(buyer2, 2);
        assertEq(b1CliffReleasable, 0, "Strategic must have 0 releasable during 14-day cliff");
        assertEq(b2CliffReleasable, 0, "Private must have 0 releasable during 14-day cliff");

        // Calling claimVested during cliff is a no-op (0 minted)
        uint256 b1BalBefore = ser.balanceOf(buyer1);
        vm.prank(buyer1);
        presale.claimVested(1);
        assertEq(ser.balanceOf(buyer1), b1BalBefore, "No tokens minted during cliff");

        // Public tier has no vesting: calling claimVested after cliff reverts with "Presale: no vesting"
        vm.warp(tgeTime + 15 days);
        vm.prank(buyer3);
        vm.expectRevert("Presale: no vesting");
        presale.claimVested(3);

        // Claim monthly over 12 months after the 14-day cliff
        uint256 cliffEnd = tgeTime + 14 days;
        for (uint256 month = 1; month <= 12; month++) {
            uint256 targetTime = month < 12 ? cliffEnd + (month * 30 days) : cliffEnd + 365 days;
            vm.warp(targetTime);

            vm.prank(buyer1);
            presale.claimVested(1);

            vm.prank(buyer2);
            presale.claimVested(2);

            vm.prank(buyer4);
            presale.claimVested(1);

            vm.prank(buyer5);
            presale.claimVested(2);
        }

        // Verify exact 100% payout after 12 months
        assertEq(ser.balanceOf(buyer1), 1_492_500e18, "Buyer1 must have exact 100% Strategic allocation");
        assertEq(ser.balanceOf(buyer2), 1_492_500e18, "Buyer2 must have exact 100% Private allocation");
        assertEq(ser.balanceOf(buyer3), 248_750e18, "Buyer3 must have exact 100% Public allocation");
        assertEq(ser.balanceOf(buyer4), 199_000e18 + 199_000e18, "Buyer4 must have exact 100% across Tiers 1 & 3");
        assertEq(ser.balanceOf(buyer5), 298_500e18 + 199_000e18, "Buyer5 must have exact 100% across Tiers 2 & 3");

        // Warp 10 years later — zero over-minting
        vm.warp(cliffEnd + 365 days + 3650 days);
        (,, uint256 b1After10Y) = presale.getBuyerAllocation(buyer1, 1);
        assertEq(b1After10Y, 0, "Zero releasable 10 years after vesting ends");

        vm.prank(buyer1);
        vm.expectRevert("Presale: nothing to claim");
        presale.claimVested(1);

        vm.prank(buyer2);
        vm.expectRevert("Presale: nothing to claim");
        presale.claimVested(2);
    }

    /* ====================================================================== */
    /* 2. SER TOKEN TAX & PRIVACY POOL RING-BUFFER STRESS TEST SCENARIOS      */
    /* ====================================================================== */

    function test_Scenario05_PresaleBuyersShieldTokensTaxFreeViaBothMethods() public {
        _executeMultiBuyerPurchases();
        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();

        vm.prank(buyer1);
        presale.claimInitialAllocation(1); // 373,125 SER
        vm.prank(buyer3);
        presale.claimInitialAllocation(3); // 248,750 SER

        uint256 supplyBefore = ser.totalSupply();
        uint256 poolBefore = ser.balanceOf(address(pool));

        // Buyer 1 shields 100,000 SER via direct approve + pool.shield()
        vm.startPrank(buyer1);
        ser.approve(address(pool), 100_000e18);
        uint32 idx0 = pool.shield(100_000e18, keccak256("buyer1_note_0"), "");
        vm.stopPrank();

        // Buyer 3 shields 50,000 SER via ser.approveAndShield() convenience wrapper
        vm.prank(buyer3);
        ser.approveAndShield(50_000e18, keccak256("buyer3_note_1"));

        assertEq(idx0, 0);
        assertEq(pool.nextLeafIndex(), 2);
        // Verify 0% tax on both shield paths
        assertEq(ser.balanceOf(buyer1), 273_125e18, "0% tax on pool.shield");
        assertEq(ser.balanceOf(buyer3), 198_750e18, "0% tax on ser.approveAndShield");
        assertEq(ser.balanceOf(address(pool)), poolBefore + 150_000e18, "Pool received full 150,000 SER untaxed");
        assertEq(ser.totalSupply(), supplyBefore, "No tokens burned during shielding");
    }

    function test_Scenario06_RegularTransferAppliesSellTaxWhilePoolAndTreasuryAreExempt() public {
        _executeMultiBuyerPurchases();
        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();

        vm.prank(buyer3);
        presale.claimInitialAllocation(3); // 248,750 SER

        uint256 treasuryBefore = ser.balanceOf(treasury);
        uint256 supplyBefore = ser.totalSupply();

        // Regular user-to-user transfer incurs 1% tax (0.5% burn, 0.5% treasury)
        vm.prank(buyer3);
        ser.transfer(freshRecipient1, 10_000e18);

        assertEq(ser.balanceOf(freshRecipient1), 9_900e18, "Recipient receives 99% (100 - 1% sell tax)");
        assertEq(ser.balanceOf(treasury), treasuryBefore + 50e18, "Treasury receives 0.5% tax (50 SER)");
        assertEq(ser.totalSupply(), supplyBefore - 50e18, "Total supply burned by 0.5% (50 SER)");

        // Transfer from user back to treasury is tax-exempt
        vm.prank(freshRecipient1);
        ser.transfer(treasury, 1_000e18);
        assertEq(ser.balanceOf(treasury), treasuryBefore + 50e18 + 1_000e18, "Transfer to treasury is untaxed");
    }

    function test_Scenario07_PrivacyPoolRingBuffer105OperationsWrapAroundStressTest() public {
        _executeMultiBuyerPurchases();
        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();

        vm.prank(buyer1);
        presale.claimInitialAllocation(1); // 373,125 SER
        vm.prank(buyer2);
        presale.claimInitialAllocation(2); // 298,500 SER

        bytes32 initialRoot = pool.getLastRoot();
        assertTrue(pool.isKnownRoot(initialRoot), "Initial root is known at index 0");

        // Record roots after each of 105 consecutive single-commitment operations
        // (70 shields from buyer1 + 35 single-output privateTransfers)
        bytes32[] memory recordedRoots = new bytes32[](105);

        vm.startPrank(buyer1);
        ser.approve(address(pool), type(uint256).max);
        for (uint256 i = 0; i < 70; i++) {
            pool.shield(100e18, keccak256(abi.encodePacked("stress_shield_", i)), "");
            recordedRoots[i] = pool.getLastRoot();
        }
        vm.stopPrank();

        for (uint256 j = 70; j < 105; j++) {
            bytes32[] memory nullifiers = new bytes32[](1);
            nullifiers[0] = keccak256(abi.encodePacked("stress_nullifier_", j));
            bytes32[] memory commitments = new bytes32[](1);
            commitments[0] = keccak256(abi.encodePacked("stress_transfer_commit_", j));

            // Prove against a recent valid root
            bytes32 validRoot = recordedRoots[j - 1];
            pool.privateTransfer(nullifiers, commitments, validRoot, "");
            recordedRoots[j] = pool.getLastRoot();
        }

        assertEq(pool.nextLeafIndex(), 105, "105 leaves inserted into Merkle tree");

        // Ring buffer size is 100:
        // After 105 insertions, initialRoot and recordedRoots[0..4] (the first 5 insertions) were overwritten!
        assertFalse(pool.isKnownRoot(initialRoot), "Initial root must be expired after 105 insertions");
        for (uint256 k = 0; k < 5; k++) {
            assertFalse(pool.isKnownRoot(recordedRoots[k]), "Roots older than 100 insertions must expire");
        }

        // All 100 most recent roots (recordedRoots[5..104]) must still be valid!
        for (uint256 k = 5; k < 105; k++) {
            assertTrue(pool.isKnownRoot(recordedRoots[k]), "Recent 100 roots in ring buffer must remain valid");
        }

        // Attempting privateTransfer or unshield with an expired root must revert
        bytes32[] memory nExp = new bytes32[](1);
        nExp[0] = keccak256("expired_root_nullifier");
        bytes32[] memory cExp = new bytes32[](1);
        cExp[0] = keccak256("expired_root_commitment");

        vm.expectRevert("PrivacyPool: unknown or expired root");
        pool.privateTransfer(nExp, cExp, recordedRoots[0], "");

        vm.expectRevert("PrivacyPool: unknown or expired root");
        pool.unshield(keccak256("expired_unshield_null"), 10e18, freshRecipient1, recordedRoots[4], "");
    }

    function test_Scenario08_PrivacyPoolUnshieldToFreshRecipientsAndDoubleSpendPrevention() public {
        _executeMultiBuyerPurchases();
        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();

        vm.prank(buyer1);
        presale.claimInitialAllocation(1); // 373,125 SER

        // Buyer 1 shields 10,000 SER
        vm.prank(buyer1);
        ser.approveAndShield(10_000e18, keccak256("shield_for_unshield_test"));

        bytes32 rootAfterShield = pool.getLastRoot();

        // Execute a 2-input, 2-output privateTransfer
        bytes32[] memory inNulls = new bytes32[](2);
        inNulls[0] = keccak256("priv_in_null_1");
        inNulls[1] = keccak256("priv_in_null_2");
        bytes32[] memory outCommits = new bytes32[](2);
        outCommits[0] = keccak256("priv_out_commit_1");
        outCommits[1] = keccak256("priv_out_commit_2");

        pool.privateTransfer(inNulls, outCommits, rootAfterShield, "");

        // Re-spending either nullifier in privateTransfer must revert
        bytes32[] memory dupNulls = new bytes32[](1);
        dupNulls[0] = inNulls[0];
        bytes32[] memory nextCommits = new bytes32[](1);
        nextCommits[0] = keccak256("priv_out_commit_3");

        bytes32 latestRoot = pool.getLastRoot();
        vm.expectRevert("PrivacyPool: nullifier already spent");
        pool.privateTransfer(dupNulls, nextCommits, latestRoot, "");

        // Re-spending an already-spent privateTransfer nullifier in unshield must ALSO revert
        vm.expectRevert("PrivacyPool: nullifier already spent");
        pool.unshield(inNulls[1], 1_000e18, freshRecipient1, latestRoot, "");

        // Unshield 4,000 SER directly via pool.unshield to freshRecipient1 (0% tax)
        bytes32 unshieldNull1 = keccak256("unshield_null_fresh_1");
        pool.unshield(unshieldNull1, 4_000e18, freshRecipient1, latestRoot, "");
        assertEq(ser.balanceOf(freshRecipient1), 4_000e18, "freshRecipient1 receives exact 4,000 SER untaxed");

        // Unshield 6,000 SER via ser.unshield wrapper to freshRecipient2 (0% tax)
        bytes32 unshieldNull2 = keccak256("unshield_null_fresh_2");
        vm.prank(buyer1);
        ser.unshield(unshieldNull2, 6_000e18, freshRecipient2, latestRoot, "");
        assertEq(ser.balanceOf(freshRecipient2), 6_000e18, "freshRecipient2 receives exact 6,000 SER untaxed");

        // Double-unshielding unshieldNull1 must revert
        vm.expectRevert("PrivacyPool: nullifier already spent");
        pool.unshield(unshieldNull1, 4_000e18, freshRecipient1, latestRoot, "");
    }

    /* ====================================================================== */
    /* 3. CROSS-EVM BRIDGE, GAS ABSTRACTION & FIRST-PARTY MODULES             */
    /* ====================================================================== */

    function test_Scenario09_CrossEVMBridgeMultiRelayerMerkleTreeBatchAndChallengeWindow() public {
        // RelayerGood bonds 2 ETH, RelayerBad bonds 1.5 ETH
        vm.prank(relayerGood);
        bridge.bondRelayer{value: 2 ether}();
        vm.prank(relayerBad);
        bridge.bondRelayer{value: 1.5 ether}();

        assertEq(bridge.relayerBonds(relayerGood), 2 ether);
        assertEq(bridge.relayerBonds(relayerBad), 1.5 ether);

        // Construct a 2-leaf Merkle tree for two cross-chain claims (buyer1 and buyer2)
        bytes32 null1 = keccak256("xmr_to_seraph_null_1");
        bytes32 null2 = keccak256("xmr_to_seraph_null_2");
        uint256 amt1 = 1_250e18;
        uint256 amt2 = 2_750e18;

        bytes32 leaf1 = keccak256(abi.encodePacked(null1, buyer1, amt1, SERAPH_EVM_ID));
        bytes32 leaf2 = keccak256(abi.encodePacked(null2, buyer2, amt2, SERAPH_EVM_ID));
        bytes32 merkleRoot = _hashSortedPair(leaf1, leaf2);

        vm.prank(relayerGood);
        uint256 batchId = bridge.submitStateBatch(XMR_EVM_ID, merkleRoot);

        bytes32[] memory proofFor1 = new bytes32[](1);
        proofFor1[0] = leaf2;
        bytes32[] memory proofFor2 = new bytes32[](1);
        proofFor2[0] = leaf1;

        // Claiming before 1-hour challenge window reverts
        vm.expectRevert(CrossEVMBridge.ChallengeWindowActive.selector);
        bridge.claimBridged(batchId, null1, buyer1, amt1, proofFor1);

        // Warp past 1-hour challenge window
        vm.warp(block.timestamp + 1 hours + 1);

        // Wrong Merkle proof or wrong amount reverts
        vm.expectRevert(CrossEVMBridge.InvalidMerkleProof.selector);
        bridge.claimBridged(batchId, null1, buyer1, amt1 + 1, proofFor1);

        // Both valid claims succeed
        bridge.claimBridged(batchId, null1, buyer1, amt1, proofFor1);
        bridge.claimBridged(batchId, null2, buyer2, amt2, proofFor2);

        assertEq(ser.balanceOf(buyer1), amt1);
        assertEq(ser.balanceOf(buyer2), amt2);

        // Replay of null1 must revert
        vm.expectRevert(CrossEVMBridge.NullifierAlreadyUsed.selector);
        bridge.claimBridged(batchId, null1, buyer1, amt1, proofFor1);
    }

    function test_Scenario10_CrossEVMBridgeFraudChallengeSlashesBadRelayerAndLocksOutbound() public {
        vm.prank(relayerBad);
        bridge.bondRelayer{value: 3 ether}();

        // RelayerBad submits a fraudulent state root
        vm.prank(relayerBad);
        uint256 fraudulentBatchId = bridge.submitStateBatch(BASE_LAYER_ID, keccak256("forged_state_root"));

        // Non-guardian cannot challenge
        vm.prank(challenger);
        vm.expectRevert(CrossEVMBridge.Unauthorized.selector);
        bridge.challengeBatch(fraudulentBatchId, challenger);

        // Guardian challenges fraudulent batch and rewards challenger with the 3 ETH bond
        uint256 challengerBalBefore = challenger.balance;
        vm.prank(guardian);
        bridge.challengeBatch(fraudulentBatchId, challenger);

        assertEq(challenger.balance - challengerBalBefore, 3 ether, "Challenger receives full 3 ETH slashed bond");
        assertEq(bridge.relayerBonds(relayerBad), 0, "Bad relayer bond slashed to 0");

        // Slashed relayer can no longer submit batches without re-bonding
        vm.prank(relayerBad);
        vm.expectRevert(CrossEVMBridge.InsufficientBond.selector);
        bridge.submitStateBatch(BASE_LAYER_ID, keccak256("another_root"));

        // Even after 1 hour, claiming against a challenged batch reverts
        vm.warp(block.timestamp + 2 hours);
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(CrossEVMBridge.InvalidBatch.selector);
        bridge.claimBridged(fraudulentBatchId, keccak256("n"), buyer1, 100e18, emptyProof);

        // Test outbound bridging (bridgeOut) locking SER
        vm.startPrank(treasury);
        ser.setSellTaxEnabled(false);
        ser.mint(buyer1, 500e18);
        vm.stopPrank();

        vm.startPrank(buyer1);
        ser.approve(address(bridge), 500e18);
        uint256 nonce = bridge.bridgeOut(buyer2, 500e18, XMR_EVM_ID);
        vm.stopPrank();

        assertEq(nonce, 0);
        assertEq(ser.balanceOf(address(bridge)), 500e18);
    }

    function test_Scenario11_GasRelayerDualTokenAbstractionInSERAndWXMR() public {
        vm.startPrank(treasury);
        ser.setSellTaxEnabled(false);
        ser.mint(buyer1, 5_000e18);
        vm.stopPrank();

        // 1. Fund GasRelayer with SER voucher from buyer1
        bytes32 serVoucherCommit = keccak256("ser_voucher_commit_1");
        bytes32 serVoucherNull = keccak256("ser_voucher_null_1");
        vm.startPrank(buyer1);
        ser.approve(address(gasRelayer), 100e18);
        gasRelayer.fundGasVoucher(address(ser), 100e18, serVoucherCommit);
        vm.stopPrank();

        // 2. Fund GasRelayer with wXMR voucher from buyer2
        bytes32 xmrVoucherCommit = keccak256("xmr_voucher_commit_1");
        bytes32 xmrVoucherNull = keccak256("xmr_voucher_null_1");
        vm.startPrank(buyer2);
        wxmr.approve(address(gasRelayer), 10e18);
        gasRelayer.fundGasVoucher(address(wxmr), 10e18, xmrVoucherCommit);
        vm.stopPrank();

        // 3. RelayerGood executes an encrypted message broadcast paid in SER
        bytes memory msgCall = abi.encodeWithSelector(
            InvoiceRegistry.sendEncryptedMessage.selector,
            keccak256("recipient_view_pub"),
            keccak256("ephemeral_pub"),
            bytes("stealth_ciphertext_payload")
        );

        vm.prank(relayerGood);
        gasRelayer.executeWithGasAbstraction(serVoucherNull, address(ser), 25e18, address(invoices), msgCall);
        assertEq(ser.balanceOf(relayerGood), 25e18, "Relayer compensated in SER");

        // 4. RelayerGood executes a stealth invoice creation on InvoiceRegistry paid in wXMR
        bytes32 relayedInvId = keccak256("relayed_invoice_001");
        bytes memory createInvCall = abi.encodeWithSelector(
            InvoiceRegistry.createInvoice.selector,
            relayedInvId,
            keccak256("stealth_merchant"),
            merchant,
            address(wxmr),
            50e18,
            bytes("encrypted_invoice_memo")
        );

        vm.prank(relayerGood);
        gasRelayer.executeWithGasAbstraction(xmrVoucherNull, address(wxmr), 1.5e18, address(invoices), createInvCall);
        assertEq(wxmr.balanceOf(relayerGood), 1.5e18, "Relayer compensated in wXMR");

        // Verify invoice was created on-chain via gas-abstracted call
        (, address claimAddr, address invToken, uint256 invAmt, bool settled,) = invoices.invoices(relayedInvId);
        assertEq(claimAddr, merchant);
        assertEq(invToken, address(wxmr));
        assertEq(invAmt, 50e18);
        assertFalse(settled);

        // 5. Reusing a spent gas voucher nullifier must revert
        vm.prank(relayerGood);
        vm.expectRevert(GasRelayer.VoucherAlreadyUsed.selector);
        gasRelayer.executeWithGasAbstraction(serVoucherNull, address(ser), 10e18, address(invoices), msgCall);
    }

    function test_Scenario12_InvoiceRegistryEndToEndStealthInvoicingInSERAndWXMR() public {
        vm.startPrank(treasury);
        ser.setSellTaxEnabled(false);
        ser.mint(buyer1, 10_000e18);
        vm.stopPrank();

        bytes32 serInvId = keccak256("invoice_ser_101");
        bytes32 xmrInvId = keccak256("invoice_xmr_102");

        // Merchant creates two stealth invoices: one denominated in SER, one in wXMR
        vm.startPrank(merchant);
        invoices.createInvoice(serInvId, keccak256("stealth_addr_1"), merchant, address(ser), 1_500e18, hex"cafe01");
        invoices.createInvoice(xmrInvId, keccak256("stealth_addr_2"), merchant, address(wxmr), 12e18, hex"cafe02");

        // Duplicate invoice ID must revert
        vm.expectRevert(InvoiceRegistry.InvoiceExists.selector);
        invoices.createInvoice(serInvId, keccak256("stealth_addr_1"), merchant, address(ser), 1_500e18, hex"cafe01");
        vm.stopPrank();

        // Buyer1 settles SER invoice
        vm.startPrank(buyer1);
        ser.approve(address(invoices), 1_500e18);
        invoices.settleInvoice(serInvId, keccak256("ser_payment_nullifier"));
        vm.stopPrank();

        // Buyer2 settles wXMR invoice
        vm.startPrank(buyer2);
        wxmr.approve(address(invoices), 12e18);
        invoices.settleInvoice(xmrInvId, keccak256("xmr_payment_nullifier"));
        vm.stopPrank();

        assertEq(ser.balanceOf(merchant), 1_500e18, "Merchant received 1,500 SER");
        assertEq(wxmr.balanceOf(merchant), 12e18, "Merchant received 12 wXMR");

        // Settling an already settled invoice must revert
        vm.prank(buyer1);
        vm.expectRevert(InvoiceRegistry.AlreadySettled.selector);
        invoices.settleInvoice(serInvId, keccak256("ser_payment_nullifier_2"));
    }

    function test_Scenario13_UsageVaultMultiTicketAIComputeRedemptionsAcrossProviders() public {
        vm.startPrank(treasury);
        ser.setSellTaxEnabled(false);
        ser.mint(buyer1, 10_000e18);
        vm.stopPrank();

        bytes32 agentSecret = keccak256("ai_agent_master_secret");
        bytes32 commitment = keccak256(abi.encodePacked(agentSecret));

        // Buyer1 deposits 5,000 SER compute credits under blinded commitment
        vm.startPrank(buyer1);
        ser.approve(address(aiVault), 5_000e18);
        aiVault.depositCredits(commitment, 5_000e18);
        vm.stopPrank();

        // AI Provider 1 redeems 3 sequential micro-tickets (400, 600, 1000 SER = 2,000 SER)
        vm.startPrank(aiProvider1);
        aiVault.redeemUsageTicket(commitment, keccak256("ticket_p1_1"), 400e18, agentSecret);
        aiVault.redeemUsageTicket(commitment, keccak256("ticket_p1_2"), 600e18, agentSecret);
        aiVault.redeemUsageTicket(commitment, keccak256("ticket_p1_3"), 1_000e18, agentSecret);
        vm.stopPrank();

        // AI Provider 2 redeems 2 sequential tickets (1,200, 1,800 SER = 3,000 SER)
        vm.startPrank(aiProvider2);
        aiVault.redeemUsageTicket(commitment, keccak256("ticket_p2_1"), 1_200e18, agentSecret);
        aiVault.redeemUsageTicket(commitment, keccak256("ticket_p2_2"), 1_800e18, agentSecret);
        vm.stopPrank();

        assertEq(aiVault.creditCommitments(commitment), 0, "All 5,000 SER commitment credits consumed");

        // Replaying a ticket or exceeding remaining balance reverts
        vm.prank(aiProvider1);
        vm.expectRevert(UsageVault.TicketAlreadyRedeemed.selector);
        aiVault.redeemUsageTicket(commitment, keccak256("ticket_p1_1"), 100e18, agentSecret);

        vm.prank(aiProvider1);
        vm.expectRevert(UsageVault.InsufficientCommitmentBalance.selector);
        aiVault.redeemUsageTicket(commitment, keccak256("ticket_p1_4"), 1e18, agentSecret);

        // Both AI providers claim their accumulated earnings
        vm.prank(aiProvider1);
        uint256 p1Claimed = aiVault.claimEarnings();
        vm.prank(aiProvider2);
        uint256 p2Claimed = aiVault.claimEarnings();

        assertEq(p1Claimed, 2_000e18);
        assertEq(p2Claimed, 3_000e18);
        assertEq(ser.balanceOf(aiProvider1), 2_000e18);
        assertEq(ser.balanceOf(aiProvider2), 3_000e18);

        // Second claim with 0 pending earnings reverts
        vm.prank(aiProvider1);
        vm.expectRevert(UsageVault.NothingToClaim.selector);
        aiVault.claimEarnings();
    }

    function test_Scenario14_CollateralVaultMintPriceDropHealthCheckAndFullRepayment() public {
        vm.startPrank(treasury);
        ser.setSellTaxEnabled(false);
        ser.mint(buyer1, 10_000e18);
        vm.stopPrank();

        // At $2.00/SER: Buyer1 deposits 3,000 SER ($6,000 value) and mints 3,500 xUSD (CR = 171.4% >= 150%)
        vm.startPrank(buyer1);
        ser.approve(address(cdpVault), 10_000e18);
        cdpVault.depositAndMint(3_000e18, 3_500e18);
        vm.stopPrank();

        assertEq(cdpVault.xUSD().balanceOf(buyer1), 3_500e18);

        // Oracle updates SER price down from $2.00 to $1.50
        // Collateral value is now 3,000 * $1.50 = $4,500; required for 3,500 xUSD at 150% CR is $5,250
        cdpVault.setCollateralPrice(1.5e18);

        // Buyer1 cannot mint even 1 wei of xUSD or withdraw 1 wei of SER while under-collateralized
        vm.startPrank(buyer1);
        vm.expectRevert(CollateralVault.InsufficientCollateralRatio.selector);
        cdpVault.depositAndMint(0, 1);

        vm.expectRevert(CollateralVault.InsufficientCollateralRatio.selector);
        cdpVault.burnAndWithdraw(0, 1);

        // Buyer1 repays 1,000 xUSD (debt becomes 2,500 xUSD -> min required collateral value = $3,750)
        // With $4,500 collateral value ($1.50 * 3,000), buyer1 can now withdraw 500 SER ($750), leaving 2,500 SER ($3,750 = exact 150% CR)
        cdpVault.burnAndWithdraw(1_000e18, 500e18);
        assertEq(cdpVault.xUSD().balanceOf(buyer1), 2_500e18);

        // Repay remaining 2,500 xUSD and withdraw remaining 2,500 SER
        cdpVault.burnAndWithdraw(2_500e18, 2_500e18);
        vm.stopPrank();

        assertEq(cdpVault.xUSD().balanceOf(buyer1), 0, "All xUSD debt burned");
        assertEq(ser.balanceOf(buyer1), 10_000e18, "All 3,000 SER collateral returned to buyer1");
    }

    function test_Scenario15_EndToEndFullProtocolLifecycleFromPresaleToPrivateDeFiAndAI() public {
        // Step 1: Presale purchase & TGE claim
        _executeMultiBuyerPurchases();
        vm.warp(tgeTime);
        vm.prank(treasury);
        presale.executeTGE();

        vm.prank(buyer1);
        presale.claimInitialAllocation(1); // 373,125 SER

        // Step 2: Buyer1 shields 50,000 SER into PrivacyPool (0% tax)
        vm.prank(buyer1);
        ser.approveAndShield(50_000e18, keccak256("e2e_shield_commit"));

        // Step 3: Buyer1 performs a privateTransfer inside PrivacyPool
        bytes32[] memory nulls = new bytes32[](1);
        nulls[0] = keccak256("e2e_priv_null");
        bytes32[] memory commits = new bytes32[](1);
        commits[0] = keccak256("e2e_priv_commit_out");
        pool.privateTransfer(nulls, commits, pool.getLastRoot(), "");

        // Step 4: Unshield 50,000 SER to freshRecipient1 (unlinkable wallet, 0% tax)
        pool.unshield(keccak256("e2e_unshield_null"), 50_000e18, freshRecipient1, pool.getLastRoot(), "");
        assertEq(ser.balanceOf(freshRecipient1), 50_000e18);

        // Governance disables sell tax post-TGE so DeFi / AI modules operate at 1:1 nominal amounts
        vm.prank(treasury);
        ser.setSellTaxEnabled(false);

        // Step 5: freshRecipient1 uses unshielded SER to:
        //   (a) Lock 10,000 SER in CollateralVault to mint 12,000 xUSD
        //   (b) Deposit 5,000 SER in UsageVault for AI agent compute
        //   (c) Fund a 500 SER gas voucher in GasRelayer
        bytes32 aiSecret = keccak256("e2e_ai_secret");
        bytes32 aiCommit = keccak256(abi.encodePacked(aiSecret));

        vm.startPrank(freshRecipient1);
        ser.approve(address(cdpVault), 10_000e18);
        cdpVault.depositAndMint(10_000e18, 12_000e18);

        ser.approve(address(aiVault), 5_000e18);
        aiVault.depositCredits(aiCommit, 5_000e18);

        ser.approve(address(gasRelayer), 500e18);
        gasRelayer.fundGasVoucher(address(ser), 500e18, keccak256("e2e_gas_voucher"));
        vm.stopPrank();

        // Step 6: Relayer executes AI ticket redemption via GasRelayer!
        bytes memory redeemCall = abi.encodeWithSelector(
            UsageVault.redeemUsageTicket.selector, aiCommit, keccak256("e2e_ai_ticket_1"), 2_500e18, aiSecret
        );
        vm.prank(relayerGood);
        gasRelayer.executeWithGasAbstraction(
            keccak256("e2e_gas_nullifier"), address(ser), 50e18, address(aiVault), redeemCall
        );

        assertEq(ser.balanceOf(relayerGood), 50e18, "Relayer earned 50 SER fee");
        assertEq(aiVault.providerEarnings(address(gasRelayer)), 2_500e18, "Target recorded earnings for caller");
        assertEq(cdpVault.xUSD().balanceOf(freshRecipient1), 12_000e18, "freshRecipient1 holds 12,000 xUSD");
    }

    function test_Scenario16_PresaleDynamicETHPriceAndTierCapBoundaries() public {
        // Treasury updates ETH price from $2,000 to $4,000
        vm.prank(treasury);
        presale.updateEthUsdPrice(4000);

        // Buyer3 buys with 1 ETH in Public tier ($0.04):
        // Net ETH = 0.995 ETH -> $3,980 USD / $0.04 = 99,500 SER
        vm.prank(buyer3);
        presale.buyWithETH{value: 1 ether}(3);

        (uint256 total,,) = presale.getBuyerAllocation(buyer3, 3);
        assertEq(total, 99_500e18, "ETH purchase reflects updated $4,000 ETH/USD price");

        // Treasury tightens Tier 3 hardCap right to current sold amount
        vm.prank(treasury);
        presale.setTierHardCap(3, total);

        // Any further purchase in Tier 3 exceeds hardCap and reverts
        vm.prank(buyer3);
        vm.expectRevert("Presale: tier cap exceeded");
        presale.buyWithETH{value: 0.01 ether}(3);
    }

    /* ====================================================================== */
    /* INTERNAL HELPERS                                                       */
    /* ====================================================================== */

    function _executeMultiBuyerPurchases() internal {
        vm.startPrank(buyer1);
        usdc.approve(address(presale), 30_000e6);
        presale.buyWithStablecoin(1, 20_000e6, address(usdc), referrer1);
        presale.buyWithStablecoin(1, 10_000e6, address(usdc), referrer1);
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdt.approve(address(presale), 45_000e6);
        presale.buyWithStablecoin(2, 30_000e6, address(usdt), referrer2);
        presale.buyWithStablecoin(2, 15_000e6, address(usdt), address(0));
        vm.stopPrank();

        vm.startPrank(buyer3);
        presale.buyWithETH{value: 2 ether}(3);
        (bool ok,) = address(presale).call{value: 3 ether}("");
        require(ok, "receive failed");
        vm.stopPrank();

        vm.startPrank(buyer4);
        usdc.approve(address(presale), 12_000e6);
        presale.buyWithStablecoin(3, 8_000e6, address(usdc), referrer1);
        presale.buyWithStablecoin(1, 4_000e6, address(usdc), referrer1);
        vm.stopPrank();

        vm.startPrank(buyer5);
        usdt.approve(address(presale), 18_000e6);
        presale.buyWithStablecoin(3, 12_000e6, address(usdt), referrer2);
        presale.buyWithStablecoin(2, 6_000e6, address(usdt), referrer2);
        vm.stopPrank();
    }

    function _hashSortedPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}

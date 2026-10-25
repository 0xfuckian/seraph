// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../core/SERAPH.sol";
import "../core/PrivacyPool.sol";
import "../core/gas/GasRelayer.sol";
import "../modules/messaging/InvoiceRegistry.sol";
import "../modules/ai_payments/UsageVault.sol";
import "../modules/stablecoin/CollateralVault.sol";
import "./MockERC20.sol";

/**
 * @title MockInvariantVerifier
 * @notice Deterministic verifier used by PrivacyPool during stateful invariant fuzzing.
 */
contract MockInvariantVerifier is IVerifier {
    function verifyProof(bytes calldata, uint256[] calldata) external pure returns (bool) {
        return true;
    }
}

/**
 * @title ProtocolModulesHandler
 * @notice Stateful handler driving random sequences of actions across:
 *         - PrivacyPool (shield, privateTransfer, unshield)
 *         - UsageVault (depositCredits, redeemUsageTicket, claimEarnings)
 *         - CollateralVault (depositAndMint, burnAndWithdraw across 5 actors)
 *         - GasRelayer (fundGasVoucher, executeWithGasAbstraction in SER and wXMR)
 */
contract ProtocolModulesHandler is Test {
    SeraphToken public ser;
    MockERC20 public wxmr;
    PrivacyPool public pool;
    UsageVault public aiVault;
    CollateralVault public cdpVault;
    GasRelayer public gasRelayer;
    InvoiceRegistry public invoices;

    address public treasury;
    address[] public actors;
    address[] public providers;

    uint256 public nonce;

    // ─── PrivacyPool Ghost State ───────────────────────────────────────
    uint256 public totalShielded;
    uint256 public totalUnshielded;
    uint256 public totalLeavesInserted;
    bytes32[] public spentNullifiers;
    bytes32[] public insertedCommitments;

    // ─── UsageVault Ghost State ────────────────────────────────────────
    bytes32[] public aiCommitments;
    bytes32[] public aiSecrets;
    bytes32[] public redeemedTicketNullifiers;

    // ─── GasRelayer Ghost State ────────────────────────────────────────
    bytes32[] public usedGasVouchers;

    constructor(
        SeraphToken _ser,
        MockERC20 _wxmr,
        PrivacyPool _pool,
        UsageVault _aiVault,
        CollateralVault _cdpVault,
        GasRelayer _gasRelayer,
        InvoiceRegistry _invoices,
        address _treasury,
        address[] memory _actors,
        address[] memory _providers
    ) {
        ser = _ser;
        wxmr = _wxmr;
        pool = _pool;
        aiVault = _aiVault;
        cdpVault = _cdpVault;
        gasRelayer = _gasRelayer;
        invoices = _invoices;
        treasury = _treasury;
        actors = _actors;
        providers = _providers;
    }

    // ─── Helpers ───────────────────────────────────────────────────────

    function _ensureSerBalance(address actor, uint256 needed) internal returns (bool) {
        uint256 bal = ser.balanceOf(actor);
        if (bal >= needed) return true;
        uint256 deficit = needed - bal;
        if (ser.totalSupply() + deficit <= ser.MAX_SUPPLY()) {
            vm.prank(treasury);
            ser.mint(actor, deficit);
            return true;
        }
        return false;
    }

    function _ensureWxmrBalance(address actor, uint256 needed) internal {
        uint256 bal = wxmr.balanceOf(actor);
        if (bal < needed) {
            wxmr.mint(actor, needed - bal);
        }
    }

    // ─── 1. PrivacyPool Actions ────────────────────────────────────────

    function handler_shield(uint256 actorSeed, uint256 amount, uint256 secretSeed) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e18, 10_000e18);
        if (!_ensureSerBalance(actor, amount)) return;

        bytes32 commitment = keccak256(abi.encodePacked("pool_commit", ++nonce, secretSeed));

        vm.startPrank(actor);
        ser.approve(address(pool), amount);
        pool.shield(amount, commitment, "");
        vm.stopPrank();

        totalShielded += amount;
        totalLeavesInserted += 1;
        insertedCommitments.push(commitment);
    }

    function handler_privateTransfer(uint256 nullifierCount, uint256 commitmentCount, uint256 seed) external {
        if (totalLeavesInserted == 0) return;

        nullifierCount = bound(nullifierCount, 1, 3);
        commitmentCount = bound(commitmentCount, 1, 3);

        bytes32[] memory nullifiers = new bytes32[](nullifierCount);
        for (uint256 i = 0; i < nullifierCount; i++) {
            bytes32 n = keccak256(abi.encodePacked("pool_transfer_null", ++nonce, seed, i));
            nullifiers[i] = n;
            spentNullifiers.push(n);
        }

        bytes32[] memory commitments = new bytes32[](commitmentCount);
        for (uint256 j = 0; j < commitmentCount; j++) {
            bytes32 c = keccak256(abi.encodePacked("pool_transfer_commit", ++nonce, seed, j));
            commitments[j] = c;
            insertedCommitments.push(c);
        }

        bytes32 root = pool.getLastRoot();
        pool.privateTransfer(nullifiers, commitments, root, "");

        totalLeavesInserted += commitmentCount;
    }

    function handler_unshield(uint256 actorSeed, uint256 unshieldBps, uint256 seed) external {
        uint256 netShielded = totalShielded - totalUnshielded;
        if (netShielded == 0) return;

        unshieldBps = bound(unshieldBps, 100, 10_000);
        uint256 amount = (netShielded * unshieldBps) / 10_000;
        if (amount == 0) amount = netShielded;

        address recipient = actors[actorSeed % actors.length];
        bytes32 nullifier = keccak256(abi.encodePacked("pool_unshield_null", ++nonce, seed));
        bytes32 root = pool.getLastRoot();

        pool.unshield(nullifier, amount, recipient, root, "");

        totalUnshielded += amount;
        spentNullifiers.push(nullifier);
    }

    // ─── 2. UsageVault Actions ─────────────────────────────────────────

    function handler_depositCredits(uint256 actorSeed, uint256 amount, uint256 secretSeed) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e18, 5_000e18);
        if (!_ensureSerBalance(actor, amount)) return;

        bytes32 secret = keccak256(abi.encodePacked("ai_secret", ++nonce, secretSeed));
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        if (aiVault.creditCommitments(commitment) != 0) return;

        vm.startPrank(actor);
        ser.approve(address(aiVault), amount);
        aiVault.depositCredits(commitment, amount);
        vm.stopPrank();

        aiSecrets.push(secret);
        aiCommitments.push(commitment);
    }

    function handler_redeemUsageTicket(uint256 commitmentSeed, uint256 providerSeed, uint256 redeemBps, uint256 seed)
        external
    {
        if (aiCommitments.length == 0) return;

        uint256 idx = commitmentSeed % aiCommitments.length;
        bytes32 commitment = aiCommitments[idx];
        bytes32 secret = aiSecrets[idx];

        uint256 avail = aiVault.creditCommitments(commitment);
        if (avail == 0) return;

        redeemBps = bound(redeemBps, 100, 10_000);
        uint256 amount = (avail * redeemBps) / 10_000;
        if (amount == 0) amount = avail;

        address provider = providers[providerSeed % providers.length];
        bytes32 ticketNullifier = keccak256(abi.encodePacked("ai_ticket_null", ++nonce, seed));

        vm.prank(provider);
        aiVault.redeemUsageTicket(commitment, ticketNullifier, amount, secret);

        redeemedTicketNullifiers.push(ticketNullifier);
    }

    function handler_claimEarnings(uint256 providerSeed) external {
        address provider = providers[providerSeed % providers.length];
        uint256 earnings = aiVault.providerEarnings(provider);
        if (earnings == 0) return;

        vm.prank(provider);
        aiVault.claimEarnings();
    }

    // ─── 3. CollateralVault Actions ────────────────────────────────────

    function handler_depositAndMint(uint256 actorSeed, uint256 collateralAmount, uint256 mintBps) external {
        address actor = actors[actorSeed % actors.length];
        collateralAmount = bound(collateralAmount, 10e18, 5_000e18);
        if (!_ensureSerBalance(actor, collateralAmount)) return;

        (uint256 curColl, uint256 curDebt) = cdpVault.positions(actor);
        uint256 newColl = curColl + collateralAmount;

        uint256 price = cdpVault.collateralPriceUsd();
        uint256 collateralValueUsd = (newColl * price) / cdpVault.PRICE_PRECISION();
        uint256 maxDebt = (collateralValueUsd * cdpVault.BPS()) / cdpVault.MIN_COLLATERAL_RATIO_BPS();

        mintBps = bound(mintBps, 0, 10_000);
        uint256 headroom = maxDebt > curDebt ? maxDebt - curDebt : 0;
        uint256 mintAmount = (headroom * mintBps) / 10_000;

        vm.startPrank(actor);
        ser.approve(address(cdpVault), collateralAmount);
        cdpVault.depositAndMint(collateralAmount, mintAmount);
        vm.stopPrank();
    }

    function handler_burnAndWithdraw(uint256 actorSeed, uint256 burnBps, uint256 withdrawBps) external {
        address actor = actors[actorSeed % actors.length];
        (uint256 curColl, uint256 curDebt) = cdpVault.positions(actor);
        if (curColl == 0 && curDebt == 0) return;

        burnBps = bound(burnBps, 0, 10_000);
        withdrawBps = bound(withdrawBps, 0, 10_000);

        uint256 xusdBal = cdpVault.xUSD().balanceOf(actor);
        uint256 maxBurn = curDebt < xusdBal ? curDebt : xusdBal;
        uint256 burnAmount = (maxBurn * burnBps) / 10_000;
        uint256 remDebt = curDebt - burnAmount;

        uint256 price = cdpVault.collateralPriceUsd();
        uint256 minColl = 0;
        if (remDebt > 0) {
            uint256 minValUsd = (remDebt * cdpVault.MIN_COLLATERAL_RATIO_BPS() + cdpVault.BPS() - 1) / cdpVault.BPS();
            minColl = (minValUsd * cdpVault.PRICE_PRECISION() + price - 1) / price + 1;
        }

        uint256 maxWithdraw = curColl > minColl ? curColl - minColl : 0;
        uint256 withdrawCollateral = (maxWithdraw * withdrawBps) / 10_000;

        // Verify post-withdrawal health before executing
        uint256 finalColl = curColl - withdrawCollateral;
        if (remDebt > 0) {
            uint256 finalValUsd = (finalColl * price) / cdpVault.PRICE_PRECISION();
            if ((finalValUsd * cdpVault.BPS()) < (remDebt * cdpVault.MIN_COLLATERAL_RATIO_BPS())) {
                withdrawCollateral = 0;
            }
        }

        if (burnAmount == 0 && withdrawCollateral == 0) return;

        vm.prank(actor);
        cdpVault.burnAndWithdraw(burnAmount, withdrawCollateral);
    }

    // ─── 4. GasRelayer Actions ─────────────────────────────────────────

    function handler_fundGasVoucher(uint256 actorSeed, bool useWxmr, uint256 amount, uint256 seed) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e18, 2_000e18);

        address feeToken = useWxmr ? address(wxmr) : address(ser);
        if (useWxmr) {
            _ensureWxmrBalance(actor, amount);
        } else {
            if (!_ensureSerBalance(actor, amount)) return;
        }

        bytes32 voucherCommitment = keccak256(abi.encodePacked("gas_commit", ++nonce, seed));
        if (gasRelayer.voucherCommitments(voucherCommitment)) return;

        vm.startPrank(actor);
        IERC20(feeToken).approve(address(gasRelayer), amount);
        gasRelayer.fundGasVoucher(feeToken, amount, voucherCommitment);
        vm.stopPrank();
    }

    function handler_executeWithGasAbstraction(uint256 relayerSeed, bool useWxmr, uint256 feeBps, uint256 seed)
        external
    {
        address feeToken = useWxmr ? address(wxmr) : address(ser);
        uint256 poolBal = gasRelayer.voucherPoolBalance(feeToken);

        feeBps = bound(feeBps, 0, 10_000);
        uint256 feeAmount = (poolBal * feeBps) / 10_000;

        address relayer = providers[relayerSeed % providers.length];
        bytes32 voucherNullifier = keccak256(abi.encodePacked("gas_nullifier", ++nonce, seed));
        if (gasRelayer.usedVouchers(voucherNullifier)) return;

        bytes memory callData = abi.encodeWithSelector(
            InvoiceRegistry.sendEncryptedMessage.selector,
            bytes32(uint256(++nonce)),
            bytes32(uint256(seed | 1)),
            bytes("relayed_encrypted_memo")
        );

        vm.prank(relayer);
        gasRelayer.executeWithGasAbstraction(voucherNullifier, feeToken, feeAmount, address(invoices), callData);

        usedGasVouchers.push(voucherNullifier);
    }

    // ─── View Getters for Invariants ───────────────────────────────────

    function getActorsLength() external view returns (uint256) {
        return actors.length;
    }

    function getProvidersLength() external view returns (uint256) {
        return providers.length;
    }

    function getAiCommitmentsLength() external view returns (uint256) {
        return aiCommitments.length;
    }

    function getSpentNullifiersLength() external view returns (uint256) {
        return spentNullifiers.length;
    }
}

/**
 * @title StatefulModulesAndPoolInvariantsTest
 * @notice Foundry stateful invariant suite (`StdInvariant`) verifying solvency, accounting,
 *         collateralization, and nullifier/commitment integrity across `PrivacyPool`,
 *         `UsageVault`, `CollateralVault`, and `GasRelayer`.
 */
contract StatefulModulesAndPoolInvariantsTest is StdInvariant, Test {
    SeraphToken public ser;
    MockERC20 public wxmr;
    MockInvariantVerifier public verifier;
    PrivacyPool public pool;
    UsageVault public aiVault;
    CollateralVault public cdpVault;
    GasRelayer public gasRelayer;
    InvoiceRegistry public invoices;
    ProtocolModulesHandler public handler;

    address public treasury = makeAddr("inv_treasury");
    address[] public actors;
    address[] public providers;

    function setUp() public {
        verifier = new MockInvariantVerifier();
        ser = new SeraphToken(address(0), treasury, address(0));

        vm.startPrank(treasury);
        ser.setSellTaxEnabled(false);
        pool = new PrivacyPool(address(ser), treasury, address(verifier), address(0));
        ser.setPrivacyPool(address(pool));
        vm.stopPrank();

        wxmr = new MockERC20("Wrapped XMR", "wXMR", 18, 0);
        aiVault = new UsageVault(address(ser));
        cdpVault = new CollateralVault(address(ser), 2e18); // $2.00 per SER
        gasRelayer = new GasRelayer(address(ser), address(wxmr), 1000e18, 10e18);
        invoices = new InvoiceRegistry();

        // Initialize 5 protocol actors
        for (uint256 i = 0; i < 5; i++) {
            address a = makeAddr(string(abi.encodePacked("mod_actor_", vm.toString(i))));
            vm.prank(treasury);
            ser.mint(a, 5_000_000e18);
            wxmr.mint(a, 5_000_000e18);
            actors.push(a);
        }

        // Initialize 3 AI / Relayer providers
        for (uint256 j = 0; j < 3; j++) {
            address p = makeAddr(string(abi.encodePacked("mod_provider_", vm.toString(j))));
            providers.push(p);
        }

        handler = new ProtocolModulesHandler(
            ser, wxmr, pool, aiVault, cdpVault, gasRelayer, invoices, treasury, actors, providers
        );

        targetContract(address(handler));
    }

    /**
     * @notice INVARIANT 1: PrivacyPool SER balance must always equal totalShielded minus totalUnshielded,
     *         nextLeafIndex must match total commitments inserted, and latest root must be known.
     */
    function invariant_PrivacyPoolBalanceEqualsNetShielded() public view {
        uint256 expectedPoolBalance = handler.totalShielded() - handler.totalUnshielded();
        assertEq(
            ser.balanceOf(address(pool)), expectedPoolBalance, "PrivacyPool balance does not equal net shielded SER"
        );
        assertEq(
            uint256(pool.nextLeafIndex()),
            handler.totalLeavesInserted(),
            "PrivacyPool nextLeafIndex mismatch with total leaves inserted"
        );
        assertTrue(pool.isKnownRoot(pool.getLastRoot()), "PrivacyPool latest root must always be known");
    }

    /**
     * @notice INVARIANT 2: UsageVault SER balance must always equal the sum of all unredeemed
     *         creditCommitments plus the sum of all unclaimed providerEarnings.
     */
    function invariant_UsageVaultSolvency() public view {
        uint256 sumCommitments = 0;
        uint256 commLen = handler.getAiCommitmentsLength();
        for (uint256 i = 0; i < commLen; i++) {
            bytes32 comm = handler.aiCommitments(i);
            sumCommitments += aiVault.creditCommitments(comm);
        }

        uint256 sumEarnings = 0;
        uint256 provLen = handler.getProvidersLength();
        for (uint256 j = 0; j < provLen; j++) {
            address prov = handler.providers(j);
            sumEarnings += aiVault.providerEarnings(prov);
        }

        assertEq(
            ser.balanceOf(address(aiVault)),
            sumCommitments + sumEarnings,
            "UsageVault SER balance mismatch with commitments + provider earnings"
        );
    }

    /**
     * @notice INVARIANT 3: CollateralVault SER balance must equal sum(pos.collateral),
     *         xUSD totalSupply must equal sum(pos.debt), and every actor position must
     *         satisfy the >= 150% collateralization ratio.
     */
    function invariant_CollateralVaultAndXUSDSolvency() public view {
        uint256 sumCollateral = 0;
        uint256 sumDebt = 0;
        uint256 price = cdpVault.collateralPriceUsd();
        uint256 minCrBps = cdpVault.MIN_COLLATERAL_RATIO_BPS();
        uint256 bps = cdpVault.BPS();
        uint256 precision = cdpVault.PRICE_PRECISION();

        uint256 actLen = handler.getActorsLength();
        for (uint256 i = 0; i < actLen; i++) {
            (uint256 coll, uint256 debt) = cdpVault.positions(handler.actors(i));
            sumCollateral += coll;
            sumDebt += debt;

            if (debt > 0) {
                uint256 collValUsd = (coll * price) / precision;
                assertGe(
                    collValUsd * bps, debt * minCrBps, "CollateralVault position violated 150% minimum collateral ratio"
                );
            }
        }

        assertEq(
            ser.balanceOf(address(cdpVault)),
            sumCollateral,
            "CollateralVault SER balance mismatch with sum of position collateral"
        );
        assertEq(cdpVault.xUSD().totalSupply(), sumDebt, "xUSD totalSupply mismatch with sum of position debt");
    }

    /**
     * @notice INVARIANT 4: GasRelayer token balances must always equal voucherPoolBalance
     *         for both SER and wXMR.
     */
    function invariant_GasRelayerPoolSolvency() public view {
        assertEq(
            ser.balanceOf(address(gasRelayer)),
            gasRelayer.voucherPoolBalance(address(ser)),
            "GasRelayer SER balance mismatch with voucherPoolBalance"
        );
        assertEq(
            wxmr.balanceOf(address(gasRelayer)),
            gasRelayer.voucherPoolBalance(address(wxmr)),
            "GasRelayer wXMR balance mismatch with voucherPoolBalance"
        );
    }
}

// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "./FundTestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title FundTokenHarness - Exposes internal _assetToShares and _sharesToAsset for fuzz testing.
/// @dev Deployed via proxy, initialized identically to the regular Nav4626.
contract FundTokenHarness is CoboFundToken {
    function exposed_assetToShares(uint256 assetAmount, uint256 nav) external view returns (uint256) {
        return _assetToShares(assetAmount, nav);
    }

    function exposed_sharesToAsset(uint256 shareAmount, uint256 nav) external view returns (uint256) {
        return _sharesToAsset(shareAmount, nav);
    }
}

/// @title FundFuzzTest - Fuzz and invariant tests for the XAUE gold fund tokenization system.
/// @dev Covers FZ-1..FZ-7 (fuzz tests) and INV-1..INV-9 (scenario-based invariant tests).
contract FundFuzzTest is FundTestBase {
    // ─── Harness ─────────────────────────────────────────────────────────
    FundTokenHarness public harness;

    function setUp() public override {
        super.setUp();

        // Deploy harness implementation
        FundTokenHarness harnessImpl = new FundTokenHarness();

        // Deploy harness proxy with identical initialization to fundToken
        bytes memory harnessInit = abi.encodeCall(
            CoboFundToken.initialize,
            (
                "XAUE Harness",
                "XAUE-H",
                XAUE_DECIMALS,
                address(xaut),
                address(oracle),
                address(vault),
                admin,
                MIN_DEPOSIT_AMOUNT,
                MIN_REDEEM_SHARES
            )
        );
        harness = FundTokenHarness(address(new ERC1967Proxy(address(harnessImpl), harnessInit)));
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6.1 Fuzz Tests
    // ═════════════════════════════════════════════════════════════════════

    // ─── FZ-1: Round-trip asset → shares → asset (no overpay) ────────────

    /// @dev _sharesToAsset(_assetToShares(x, nav), nav) <= x
    function testFuzz_FZ_1_roundTripAssetToShares(uint256 assetAmount, uint256 nav) public view {
        assetAmount = bound(assetAmount, 1, 1e30);
        nav = bound(nav, 1, 1e30);

        uint256 shares = harness.exposed_assetToShares(assetAmount, nav);
        uint256 recoveredAsset = harness.exposed_sharesToAsset(shares, nav);

        // Rounding always favors the protocol: recovered <= original
        assertLe(recoveredAsset, assetAmount, "FZ-1: round-trip overpays user");
    }

    // ─── FZ-2: Round-trip shares → asset → shares (no overpay) ──────────

    /// @dev _assetToShares(_sharesToAsset(s, nav), nav) <= s
    function testFuzz_FZ_2_roundTripSharesToAsset(uint256 shareAmount, uint256 nav) public view {
        shareAmount = bound(shareAmount, 1, 1e30);
        nav = bound(nav, 1, 1e30);

        uint256 asset = harness.exposed_sharesToAsset(shareAmount, nav);
        uint256 recoveredShares = harness.exposed_assetToShares(asset, nav);

        // Rounding always favors the protocol: recovered <= original
        assertLe(recoveredShares, shareAmount, "FZ-2: round-trip overpays user");
    }

    // ─── FZ-3: getLatestPrice never below current period baseNetValue ────

    /// @dev With APR >= 0, NAV(t) >= baseNetValue always holds.
    function testFuzz_FZ_3_getLatestPriceNeverBelowBase(uint256 elapsed, uint256 apr, uint256 baseNV) public {
        elapsed = bound(elapsed, 0, 10 * 365 days);
        apr = bound(apr, 0, MAX_APR);
        baseNV = bound(baseNV, 1, 1e30);

        // Set up oracle with the fuzzed parameters
        // Deploy a fresh oracle for this test to avoid interference
        CoboFundOracle fuzzOracle = CoboFundOracle(
            address(
                new ERC1967Proxy(
                    address(oracleImpl),
                    abi.encodeCall(
                        CoboFundOracle.initialize, (admin, baseNV, apr, MAX_APR, MAX_APR_DELTA, MIN_UPDATE_INTERVAL)
                    )
                )
            )
        );

        // Warp forward by elapsed time
        vm.warp(block.timestamp + elapsed);

        uint256 price = fuzzOracle.getLatestPrice();
        assertGe(price, baseNV, "FZ-3: getLatestPrice below baseNetValue");
    }

    // ─── FZ-4: mint produces valid shares and transfers XAUT ─────────────

    /// @dev For any valid xautAmount within range, shares > 0, XAUT transferred, totalSupply increases.
    function testFuzz_FZ_4_mintAmount(uint256 xautAmount) public {
        uint256 userBalance = xaut.balanceOf(user1);
        xautAmount = bound(xautAmount, MIN_DEPOSIT_AMOUNT, userBalance);

        uint256 totalSupplyBefore = fundToken.totalSupply();
        uint256 vaultBalBefore = xaut.balanceOf(address(vault));
        uint256 userXautBefore = xaut.balanceOf(user1);

        vm.prank(user1);
        uint256 shares = fundToken.mint(xautAmount);

        // Shares must be positive
        assertGt(shares, 0, "FZ-4: zero shares minted");

        // XAUT correctly transferred from user to vault
        assertEq(xaut.balanceOf(user1), userXautBefore - xautAmount, "FZ-4: user XAUT balance wrong");
        assertEq(xaut.balanceOf(address(vault)), vaultBalBefore + xautAmount, "FZ-4: vault XAUT balance wrong");

        // totalSupply increased by shares
        assertEq(fundToken.totalSupply(), totalSupplyBefore + shares, "FZ-4: totalSupply mismatch");

        // User balance increased by shares
        assertEq(fundToken.balanceOf(user1), shares, "FZ-4: user share balance mismatch");
    }

    // ─── FZ-5: requestRedemption burns correct shares ────────────────────

    /// @dev For any xaueAmount within balance, xautAmount > 0, shares correctly burned.
    function testFuzz_FZ_5_requestRedemptionAmount(uint256 xaueAmount) public {
        // First deposit to have shares
        uint256 shares = _deposit(user1, 100e6);

        xaueAmount = bound(xaueAmount, MIN_REDEEM_SHARES, shares);

        uint256 totalSupplyBefore = fundToken.totalSupply();
        uint256 userSharesBefore = fundToken.balanceOf(user1);

        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(xaueAmount);

        // Shares were burned
        assertEq(fundToken.balanceOf(user1), userSharesBefore - xaueAmount, "FZ-5: user shares not burned correctly");
        assertEq(fundToken.totalSupply(), totalSupplyBefore - xaueAmount, "FZ-5: totalSupply not reduced correctly");

        // xautAmount in the request must be > 0
        (,, uint256 xautAmt,,,) = fundToken.redemptions(reqId);
        assertGt(xautAmt, 0, "FZ-5: zero xautAmount in redemption request");
    }

    // ─── FZ-6: withdraw from vault ──────────────────────────────────────

    /// @dev Random amount within vault balance correctly decreases vault balance.
    function testFuzz_FZ_6_withdrawAmount(uint256 amount) public {
        // First deposit to fund the vault
        _deposit(user1, 500e6);
        uint256 vaultBalance = xaut.balanceOf(address(vault));

        // Bound to valid range (> 0 and <= vault balance)
        amount = bound(amount, 1, vaultBalance);

        uint256 user1XautBefore = xaut.balanceOf(user1);

        vm.prank(settlementOperator);
        vault.withdraw(user1, amount);

        // Vault balance decreased
        assertEq(xaut.balanceOf(address(vault)), vaultBalance - amount, "FZ-6: vault balance not decreased correctly");
        // User received the amount
        assertEq(xaut.balanceOf(user1), user1XautBefore + amount, "FZ-6: user balance not increased correctly");
    }

    // ─── FZ-7: updateRate APR value within valid range ──────────────────

    /// @dev Random newAPR within (currentAPR +/- maxDelta) intersect [0, maxAPR] solidifies baseNetValue.
    function testFuzz_FZ_7_updateRateAPR(uint256 newAPR) public {
        // Must wait minUpdateInterval before updateRate
        vm.warp(block.timestamp + MIN_UPDATE_INTERVAL);

        uint256 currentAPR_ = oracle.currentAPR();

        // Compute valid range: intersection of [currentAPR - maxDelta, currentAPR + maxDelta] and [0, maxAPR]
        uint256 lowerBound = currentAPR_ > MAX_APR_DELTA ? currentAPR_ - MAX_APR_DELTA : 0;
        uint256 upperBound = currentAPR_ + MAX_APR_DELTA;
        if (upperBound > MAX_APR) upperBound = MAX_APR;

        newAPR = bound(newAPR, lowerBound, upperBound);

        // Record baseNetValue before update (should be solidified to current getLatestPrice)
        uint256 expectedNewBase = oracle.getLatestPrice();

        vm.prank(navUpdater);
        oracle.updateRate(newAPR, "fuzz");

        // baseNetValue solidified to what getLatestPrice was before the update
        assertEq(oracle.baseNetValue(), expectedNewBase, "FZ-7: baseNetValue not solidified correctly");
        assertEq(oracle.currentAPR(), newAPR, "FZ-7: APR not updated correctly");
        assertEq(oracle.lastUpdateTimestamp(), block.timestamp, "FZ-7: timestamp not updated");
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6.2 Invariant Tests (Scenario-based)
    // ═════════════════════════════════════════════════════════════════════

    // ─── INV-1: totalSupply == sum of balanceOf[all users] ──────────────

    /// @dev After a series of mint/burn/transfer operations, totalSupply matches sum of all known balances.
    function test_INV_1_totalSupplyConsistency() public {
        // Step 1: Mint for user1 and user2
        _deposit(user1, 100e6);
        _deposit(user2, 200e6);
        _assertTotalSupplyConsistency();

        // Step 2: Transfer from user1 to user2
        vm.prank(user1);
        fundToken.transfer(user2, 50e18);
        _assertTotalSupplyConsistency();

        // Step 3: Burn via requestRedemption
        _requestRedemption(user2, 100e18);
        _assertTotalSupplyConsistency();

        // Step 4: Mint for user3
        _deposit(user3, 50e6);
        _assertTotalSupplyConsistency();

        // Step 5: forceRedeem
        // Cache balance before vm.prank — balanceOf is an external call via proxy
        // and would consume the prank if placed inside the argument.
        uint256 user3Shares = fundToken.balanceOf(user3);
        vm.prank(admin);
        fundToken.forceRedeem(user3, user3Shares);
        _assertTotalSupplyConsistency();
    }

    function _assertTotalSupplyConsistency() internal view {
        uint256 sumBalances = fundToken.balanceOf(user1) + fundToken.balanceOf(user2) + fundToken.balanceOf(user3);
        assertEq(fundToken.totalSupply(), sumBalances, "INV-1: totalSupply != sum of balances");
    }

    // ─── INV-2: getLatestPrice() >= current period baseNetValue ─────────

    /// @dev NAV only increases within a period (APR >= 0 guaranteed by uint256).
    function test_INV_2_navNeverDecreasesWithinPeriod() public {
        uint256 base = oracle.baseNetValue();

        // Check at multiple time offsets within the same period
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 30 days);
            uint256 price = oracle.getLatestPrice();
            assertGe(price, base, "INV-2: price below baseNetValue within period");
        }

        // After updateRate, new baseNetValue = old getLatestPrice, still >= old base
        vm.warp(block.timestamp + MIN_UPDATE_INTERVAL);
        uint256 priceBeforeUpdate = oracle.getLatestPrice();
        vm.prank(navUpdater);
        oracle.updateRate(DEFAULT_APR, "test");

        uint256 newBase = oracle.baseNetValue();
        assertEq(newBase, priceBeforeUpdate, "INV-2: newBase != priceBeforeUpdate");
        assertGe(newBase, base, "INV-2: new baseNetValue below old baseNetValue");
    }

    // ─── INV-3: Executed/Rejected requests cannot be re-operated ────────

    /// @dev After approve or reject, attempting them again must revert.
    function test_INV_3_terminalStatesIrreversible() public {
        // Setup: deposit and create two redemption requests
        _deposit(user1, 100e6);
        uint256 reqId1 = _requestRedemption(user1, 50e18);
        uint256 reqId2 = _requestRedemption(user1, 50e18);

        (,, uint256 xautAmt1, uint256 xaueAmt1,,) = fundToken.redemptions(reqId1);
        (,, uint256 xautAmt2, uint256 xaueAmt2,,) = fundToken.redemptions(reqId2);

        // Approve reqId1
        // Fund vault with enough XAUT for payout
        xaut.mint(address(vault), xautAmt1);
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId1, user1, xautAmt1, xaueAmt1);

        // Try to approve again — must revert
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId1));
        fundToken.approveRedemption(reqId1, user1, xautAmt1, xaueAmt1);

        // Try to reject an already approved request — must revert
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId1));
        fundToken.rejectRedemption(reqId1, user1, xautAmt1, xaueAmt1);

        // Reject reqId2
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId2, user1, xautAmt2, xaueAmt2);

        // Try to reject again — must revert
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId2));
        fundToken.rejectRedemption(reqId2, user1, xautAmt2, xaueAmt2);

        // Try to approve an already rejected request — must revert
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId2));
        fundToken.approveRedemption(reqId2, user1, xautAmt2, xaueAmt2);
    }

    // ─── INV-4: redemptionCount strictly increasing ────────────────────

    /// @dev Every requestRedemption increments redemptionCount by exactly 1.
    function test_INV_4_redemptionCountStrictlyIncreasing() public {
        _deposit(user1, 100e6);

        uint256 prevCount = fundToken.redemptionCount();
        assertEq(prevCount, 0, "INV-4: initial redemptionCount != 0");

        // Create multiple requests and verify monotonic increase
        for (uint256 i = 0; i < 5; i++) {
            // Need enough shares: deposit more
            if (fundToken.balanceOf(user1) < MIN_REDEEM_SHARES) {
                _deposit(user1, MIN_DEPOSIT_AMOUNT);
            }

            uint256 balance = fundToken.balanceOf(user1);
            uint256 redeemAmount = balance < MIN_REDEEM_SHARES ? balance : MIN_REDEEM_SHARES;
            if (redeemAmount < MIN_REDEEM_SHARES) continue;

            uint256 reqId = _requestRedemption(user1, redeemAmount);
            assertEq(reqId, prevCount, "INV-4: reqId not equal to previous count");
            assertEq(fundToken.redemptionCount(), prevCount + 1, "INV-4: redemptionCount not incremented by 1");
            prevCount = fundToken.redemptionCount();
        }
    }

    // ─── INV-5: Vault XAUT accounting consistency ───────────────────────

    /// @dev Vault.XAUT change = mint deposits - approve payouts - withdrawals
    function test_INV_5_vaultAccountingAccuracy() public {
        uint256 vaultBalStart = xaut.balanceOf(address(vault));
        assertEq(vaultBalStart, 0, "INV-5: vault should start empty");

        // 1. Deposit 100 XAUT → vault gains 100 XAUT
        _deposit(user1, 100e6);
        assertEq(xaut.balanceOf(address(vault)), 100e6, "INV-5: after deposit");

        // 2. Deposit 200 XAUT → vault gains 200 more
        _deposit(user2, 200e6);
        assertEq(xaut.balanceOf(address(vault)), 300e6, "INV-5: after second deposit");

        // 3. Request redemption (burns shares, does NOT move XAUT yet)
        uint256 reqId = _requestRedemption(user1, 50e18);
        assertEq(xaut.balanceOf(address(vault)), 300e6, "INV-5: after request (no XAUT change)");

        // 4. Approve redemption → vault pays xautAmount to user
        (,, uint256 xautAmt, uint256 xaueAmt,,) = fundToken.redemptions(reqId);
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, xautAmt, xaueAmt);
        assertEq(xaut.balanceOf(address(vault)), 300e6 - xautAmt, "INV-5: after approve");

        // 5. Withdraw 10 XAUT from vault
        vm.prank(settlementOperator);
        vault.withdraw(user1, 10e6);
        assertEq(xaut.balanceOf(address(vault)), 300e6 - xautAmt - 10e6, "INV-5: after withdraw");

        // Final: vault balance = total deposits - approve payouts - withdrawals
        uint256 expectedVaultBal = 300e6 - xautAmt - 10e6;
        assertEq(xaut.balanceOf(address(vault)), expectedVaultBal, "INV-5: final accounting mismatch");
    }

    // ─── INV-6: forceRedeem works in any state (only owner constraint) ──

    /// @dev forceRedeem works regardless of whitelist, freeze, pause status.
    function test_INV_6_forceRedeemWorksInAnyState() public {
        _deposit(user1, 100e6);
        uint256 shares = fundToken.balanceOf(user1);

        // Scenario A: user removed from whitelist — forceRedeem still works
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(admin);
        fundToken.forceRedeem(user1, shares / 4);
        assertEq(fundToken.balanceOf(user1), shares - shares / 4, "INV-6: forceRedeem after whitelist removal");

        // Restore whitelist for next deposit
        vm.prank(manager);
        fundToken.addToWhitelist(user1);

        // Scenario B: user frozen — forceRedeem still works
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(admin);
        fundToken.forceRedeem(user1, shares / 4);
        assertEq(fundToken.balanceOf(user1), shares - 2 * (shares / 4), "INV-6: forceRedeem after freeze");

        // Scenario C: system paused — forceRedeem still works
        vm.prank(admin);
        fundToken.pause();

        uint256 remaining = fundToken.balanceOf(user1);
        vm.prank(admin);
        fundToken.forceRedeem(user1, remaining);
        assertEq(fundToken.balanceOf(user1), 0, "INV-6: forceRedeem after pause");
    }

    // ─── INV-7: _burnBypass unaffected by pause/whitelist/freeze ────────

    /// @dev forceRedeem (which uses _burnBypass) works under all restrictive conditions.
    function test_INV_7_burnBypassUnrestricted() public {
        // Deposit first
        _deposit(user1, 100e6);
        uint256 initialShares = fundToken.balanceOf(user1);

        // Apply ALL restrictions: remove whitelist + freeze + pause

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(admin);
        fundToken.pause();

        // forceRedeem (using _burnBypass) should STILL work
        vm.prank(admin);
        fundToken.forceRedeem(user1, initialShares);
        assertEq(fundToken.balanceOf(user1), 0, "INV-7: _burnBypass should ignore all restrictions");
    }

    // ─── INV-8: _mintBypass unaffected by whitelist/freeze, respects pause ──

    /// @dev rejectRedemption (which uses _mintBypass) works when user is de-whitelisted/frozen,
    ///      but reverts when the system is paused.
    function test_INV_8_mintBypassRespectsOnlyPause() public {
        // Deposit and request redemption
        _deposit(user1, 100e6);
        uint256 reqId = _requestRedemption(user1, 50e18);
        (,, uint256 xautAmt, uint256 xaueAmt,,) = fundToken.redemptions(reqId);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // rejectRedemption should still work (mintBypass ignores whitelist/freeze)
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, xautAmt, xaueAmt);
        assertEq(fundToken.balanceOf(user1), 100e18, "INV-8: _mintBypass should bypass whitelist/freeze");

        // Now test pause: create a new redemption request
        // Re-whitelist and unfreeze user1 so they can request redemption
        vm.prank(manager);
        fundToken.addToWhitelist(user1);

        uint256 reqId2 = _requestRedemption(user1, 50e18);
        (,, uint256 xautAmt2, uint256 xaueAmt2,,) = fundToken.redemptions(reqId2);

        // Pause the system
        vm.prank(admin);
        fundToken.pause();

        // rejectRedemption should revert because _mintBypass has whenNotPaused
        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId2, user1, xautAmt2, xaueAmt2);
    }

    // ─── INV-9: After pause, only forceRedeem + admin functions work ────

    /// @dev After pause: mint reverts, requestRedemption reverts, transfer reverts,
    ///      approveRedemption reverts, rejectRedemption reverts,
    ///      but forceRedeem succeeds.
    function test_INV_9_pauseSafety() public {
        // Setup: deposit, create a pending redemption
        _deposit(user1, 100e6);
        _deposit(user2, 100e6);
        uint256 reqId = _requestRedemption(user1, 50e18);
        (,, uint256 xautAmt, uint256 xaueAmt,,) = fundToken.redemptions(reqId);

        // Pause the system
        vm.prank(admin);
        fundToken.pause();

        // 1. mint should revert (whenNotPaused on mint)
        vm.prank(user1);
        vm.expectRevert();
        fundToken.mint(10e6);

        // 2. requestRedemption should revert (whenNotPaused on requestRedemption)
        vm.prank(user2);
        vm.expectRevert();
        fundToken.requestRedemption(10e18);

        // 3. transfer should revert (whenNotPaused on _update)
        vm.prank(user2);
        vm.expectRevert();
        fundToken.transfer(user1, 10e18);

        // 4. ERC20 approve() does NOT go through _update, so it still works when paused.
        //    This is correct — approve only sets allowance, no token movement.
        vm.prank(user2);
        fundToken.approve(user1, 10e18);
        assertEq(fundToken.allowance(user2, user1), 10e18, "INV-9: approve should still work when paused");

        // However, transferFrom (which uses the allowance) should still revert
        vm.prank(user1);
        vm.expectRevert();
        fundToken.transferFrom(user2, user1, 10e18);

        // 5. approveRedemption should revert (whenNotPaused)
        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.approveRedemption(reqId, user1, xautAmt, xaueAmt);

        // 6. rejectRedemption should revert (_mintBypass has whenNotPaused)
        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, xautAmt, xaueAmt);

        // 7. Vault withdraw should revert (checks fundToken.paused())
        vm.prank(settlementOperator);
        vm.expectRevert(LibFundErrors.SystemPaused.selector);
        vault.withdraw(user1, 1e6);

        // 8. forceRedeem SHOULD succeed (uses _burnBypass, no pause check)
        uint256 user2Shares = fundToken.balanceOf(user2);
        vm.prank(admin);
        fundToken.forceRedeem(user2, user2Shares);
        assertEq(fundToken.balanceOf(user2), 0, "INV-9: forceRedeem must work when paused");

        // 9. Admin functions should still work: unpause
        vm.prank(admin);
        fundToken.unpause();
        assertFalse(fundToken.paused(), "INV-9: admin should be able to unpause");
    }
}

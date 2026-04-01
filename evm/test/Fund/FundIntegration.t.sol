// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "./FundTestBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract FundIntegrationTest is FundTestBase {
    // ═══════════════════════════════════════════════════════════════════
    // 4.1 Full Deposit → Redeem → Approve cycle
    // ═══════════════════════════════════════════════════════════════════

    function test_fullCycle_depositRedeemApprove() public {
        // 1. User deposits 100 ASSET at NAV=1.0
        uint256 shares = _deposit(user1, 100e6);
        assertEq(shares, 100e18); // 100 SHARE
        assertEq(asset.balanceOf(address(vault)), 100e6);

        // 2. Time passes, NAV increases
        vm.warp(block.timestamp + 365 days); // NAV → 1.05e18

        // 3. User requests redemption of all shares
        uint256 reqId = _requestRedemption(user1, 100e18);
        assertEq(fundToken.balanceOf(user1), 0);

        // 4. Check stored assetAmount (should be based on 1.05 NAV)
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);
        // assetAmount = 100e18 * 1.05e18 / (1e12 * 1e18) = 105e6
        assertEq(assetAmt, 105e6);
        assertEq(shareAmt, 100e18);

        // 5. But vault only has 100 ASSET! Need more. Fund vault.
        asset.mint(address(vault), 5e6); // mint additional for the yield

        // 6. Approver approves
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // 7. User received 105 ASSET (original 900 + 105)
        assertEq(asset.balanceOf(user1), 900e6 + 105e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.2 Full Deposit → Redeem → Reject cycle
    // ═══════════════════════════════════════════════════════════════════

    function test_fullCycle_depositRedeemReject() public {
        _deposit(user1, 100e6);

        uint256 reqId = _requestRedemption(user1, 50e18);
        assertEq(fundToken.balanceOf(user1), 50e18); // 50 burned

        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Reject
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        // Shares restored
        assertEq(fundToken.balanceOf(user1), 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.3 Multiple users deposit and redeem
    // ═══════════════════════════════════════════════════════════════════

    function test_multiUser_depositAndRedeem() public {
        // Both users deposit
        _deposit(user1, 100e6);
        _deposit(user2, 200e6);

        assertEq(fundToken.totalSupply(), 300e18);
        assertEq(asset.balanceOf(address(vault)), 300e6);

        // User1 redeems half
        uint256 req1 = _requestRedemption(user1, 50e18);
        // User2 redeems all
        uint256 req2 = _requestRedemption(user2, 200e18);

        assertEq(fundToken.totalSupply(), 50e18); // user1 has 50 left

        // Approve both
        (, , uint256 x1, uint256 s1, , ) = fundToken.redemptions(req1);
        (, , uint256 x2, uint256 s2, , ) = fundToken.redemptions(req2);

        vm.startPrank(redemptionApprover);
        fundToken.approveRedemption(req1, user1, x1, s1);
        fundToken.approveRedemption(req2, user2, x2, s2);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.4 Coordinated pause blocks both Nav4626 and Vault
    // ═══════════════════════════════════════════════════════════════════

    function test_coordinatedPause() public {
        _deposit(user1, 100e6);
        asset.mint(address(vault), 100e6);

        // Pause from guardian
        vm.prank(emergencyGuardian);
        fundToken.pause();

        // Nav4626 operations blocked
        vm.prank(user1);
        vm.expectRevert(); // paused
        fundToken.mint(10e6);

        vm.prank(user1);
        vm.expectRevert(); // paused
        fundToken.requestRedemption(10e18);

        // Vault withdraw also blocked (reads fundToken.paused())
        vm.prank(settlementOperator);
        vm.expectRevert(LibFundErrors.SystemPaused.selector);
        vault.withdraw(user1, 10e6);

        // Unpause
        vm.prank(admin);
        fundToken.unpause();

        // Now everything works again
        vm.prank(user1);
        fundToken.transfer(user2, 5e18);

        vm.prank(settlementOperator);
        vault.withdraw(user1, 10e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.5 NAV accumulation across multiple periods
    // ═══════════════════════════════════════════════════════════════════

    function test_navAccumulation_multiplePeriods() public {
        // Period 1: 5% APR for 365 days → NAV = 1.05e18
        uint256 startTs = block.timestamp;
        uint256 period1End = startTs + 365 days;
        vm.warp(period1End);

        uint256 navAfterPeriod1 = oracle.getLatestPrice();
        assertEq(navAfterPeriod1, 1.05e18);

        // Update to 3% APR (solidify base)
        vm.prank(navUpdater);
        oracle.updateRate(3e16, "test");
        assertEq(oracle.baseNetValue(), 1.05e18);
        assertEq(oracle.currentAPR(), 3e16);
        assertEq(oracle.lastUpdateTimestamp(), period1End);

        // Period 2: 3% APR for another 365 days
        uint256 period2End = period1End + 365 days;
        vm.warp(period2End);

        uint256 nav2 = oracle.getLatestPrice();
        // 1.05e18 + 1.05e18 * 3e16 * 365d / (365d * 1e18)
        // = 1.05e18 + 1.05e18 * 3e16 / 1e18 = 1.0815e18
        assertTrue(nav2 > navAfterPeriod1, "NAV should increase in period 2");
        assertGt(nav2, 1.08e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.6 Deposit → NAV increases → Shares worth more
    // ═══════════════════════════════════════════════════════════════════

    function test_navAppreciation_sharesWorthMore() public {
        // User1 deposits 100 ASSET at NAV=1.0 → gets 100 SHARE
        _deposit(user1, 100e6);

        // NAV goes up to 1.05
        vm.warp(block.timestamp + 365 days);

        // User1 redeems 100 SHARE → should get 105 ASSET
        uint256 reqId = _requestRedemption(user1, 100e18);
        (, , uint256 assetAmt, , , ) = fundToken.redemptions(reqId);
        assertEq(assetAmt, 105e6); // shares appreciated
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.7 Decimal conversion precision
    // ═══════════════════════════════════════════════════════════════════

    function test_decimalConversion_precision() public {
        // At NAV=1.0: 1 ASSET (1e6) → 1 SHARE (1e18)
        uint256 shares = _deposit(user1, 1e6);
        assertEq(shares, 1e18);

        // At NAV=1.0: 1 SHARE (1e18) → 1 ASSET (1e6)
        uint256 reqId = _requestRedemption(user1, 1e18);
        (, , uint256 assetAmt, , , ) = fundToken.redemptions(reqId);
        assertEq(assetAmt, 1e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.8 Vault-Nav4626 approval for redemption payout
    // ═══════════════════════════════════════════════════════════════════

    function test_vaultApproval_redemptionPayout() public {
        // Deposit puts ASSET in vault
        _deposit(user1, 100e6);

        // Vault has pre-approved fundToken
        uint256 allowance = asset.allowance(address(vault), address(fundToken));
        assertEq(allowance, type(uint256).max);

        // Redeem and approve should work without additional approval
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // User got paid
        assertGt(asset.balanceOf(user1), 900e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.9 forceRedeem bypasses all checks
    // ═══════════════════════════════════════════════════════════════════

    function test_forceRedeem_bypasses_everything() public {
        _deposit(user1, 100e6);

        // Pause + freeze user
        vm.prank(admin);
        fundToken.pause();
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // Remove from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // forceRedeem still works
        vm.prank(admin);
        fundToken.forceRedeem(user1, 100e18);
        assertEq(fundToken.balanceOf(user1), 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.10 Settlement operator can withdraw to whitelisted target
    // ═══════════════════════════════════════════════════════════════════

    function test_settlement_withdraw() public {
        _deposit(user1, 100e6);

        address custodyAddr = makeAddr("custody");
        vm.prank(admin);
        vault.setWhitelist(custodyAddr, true);

        vm.prank(settlementOperator);
        vault.withdraw(custodyAddr, 50e6);
        assertEq(asset.balanceOf(custodyAddr), 50e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.1 INT-3: Deposit → partial redeem → approve → redeem remaining → approve
    // ═══════════════════════════════════════════════════════════════════

    function test_INT3_partialRedeem_thenRedeemRemaining() public {
        // 1. User deposits 100 ASSET at NAV=1.0 → 100 SHARE
        uint256 shares = _deposit(user1, 100e6);
        assertEq(shares, 100e18);
        assertEq(fundToken.balanceOf(user1), 100e18);
        assertEq(asset.balanceOf(address(vault)), 100e6);

        // 2. Redeem 50 SHARE (partial)
        uint256 reqId1 = _requestRedemption(user1, 50e18);
        assertEq(fundToken.balanceOf(user1), 50e18);
        (, , uint256 x1, uint256 s1, , ) = fundToken.redemptions(reqId1);
        assertEq(x1, 50e6);
        assertEq(s1, 50e18);

        // 3. Approve first redemption
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId1, user1, x1, s1);
        assertEq(asset.balanceOf(user1), 900e6 + 50e6); // started with 1000-100=900, got back 50

        // 4. Redeem remaining 50 SHARE
        uint256 reqId2 = _requestRedemption(user1, 50e18);
        assertEq(fundToken.balanceOf(user1), 0);
        (, , uint256 x2, uint256 s2, , ) = fundToken.redemptions(reqId2);
        assertEq(x2, 50e6);
        assertEq(s2, 50e18);

        // 5. Approve second redemption
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId2, user1, x2, s2);
        assertEq(asset.balanceOf(user1), 1000e6); // all ASSET recovered
        assertEq(fundToken.balanceOf(user1), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.2 INT-5: NAV doubles → new user deposits get half shares
    // ═══════════════════════════════════════════════════════════════════

    function test_INT5_navDoubles_newUserGetsHalfShares() public {
        // NAV starts at 1e18. We need to get NAV to 2e18.
        // With 5% APR it takes 20 years, so let's do multiple update cycles.
        // Simpler: set APR=5%, advance 1 year, update to 5%, repeat.
        // After each year NAV grows by ~5% compounding.
        // Alternatively: just advance time enough.

        // NAV = 1e18 + 1e18 * 5e16 * elapsed / (365d * 1e18)
        // For NAV = 2e18: 1e18 = 1e18 * 5e16 * elapsed / (365d * 1e18)
        //   elapsed = 365d * 1e18 / 5e16 = 365d * 20 = 7300 days
        // But this is simple interpolation (no compounding within a single period).
        vm.warp(block.timestamp + 7300 days);
        uint256 nav = oracle.getLatestPrice();
        assertEq(nav, 2e18);

        // New user deposits 100 ASSET → should get 50 SHARE
        uint256 shares = _deposit(user2, 100e6);
        // shares = 100e6 * 1e12 * 1e18 / 2e18 = 50e18
        assertEq(shares, 50e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.2 INT-6: APR=0, deposit→redeem→approve, amounts match exactly
    // ═══════════════════════════════════════════════════════════════════

    function test_INT6_zeroAPR_depositsAndRedeemsMatch() public {
        // Set APR to 0 (need to wait minUpdateInterval first)
        _advanceTimeAndUpdateRate(1 days, 0);
        uint256 navBefore = oracle.getLatestPrice();

        // Wait arbitrary time — NAV should not change
        vm.warp(block.timestamp + 365 days);
        uint256 navAfter = oracle.getLatestPrice();
        assertEq(navBefore, navAfter, "NAV should not change with APR=0");

        // NAV after first updateRate is slightly above 1e18 due to the 1-day accrual.
        // With APR=0 from that point, NAV stays constant.
        // Rounding: protocol rounds in its favor (assetToShares rounds down, sharesToAsset rounds down).
        // So deposit→redeem may lose up to 1 wei in asset due to round-trip rounding.

        // Deposit 100 ASSET
        uint256 shares = _deposit(user1, 100e6);

        // Redeem all shares
        uint256 reqId = _requestRedemption(user1, shares);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Approve
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // User should get back ~100 ASSET (rounding favors protocol, so <= 1 wei loss is acceptable)
        uint256 userAsset = asset.balanceOf(user1);
        assertApproxEqAbs(userAsset, 1000e6, 1, "User ASSET should approximately match original balance");
        assertLe(userAsset, 1000e6, "Rounding should favor protocol (user gets <= deposited)");
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.2 INT-7: Multiple updateRate, NAV grows, deposit then redeem at higher NAV
    // ═══════════════════════════════════════════════════════════════════

    function test_INT7_multipleUpdates_navGrows_redeemAtHigherNav() public {
        uint256 startTs = block.timestamp;

        // Period 1: 5% APR for 365 days → solidify base
        // NAV = 1e18 + 1e18 * 5e16 * 365d / (365d * 1e18) = 1.05e18
        _advanceTimeAndUpdateRate(365 days, 5e16);
        assertEq(oracle.baseNetValue(), 1.05e18);

        // Period 2: 5% APR for another 365 days → solidify base
        // NAV = 1.05e18 + 1.05e18 * 5e16 / 1e18 = 1.1025e18, then set APR=3%
        _advanceTimeAndUpdateRate(365 days, 3e16);
        assertEq(oracle.baseNetValue(), 1.1025e18);

        // Period 3: 3% APR for 365 days → solidify base
        // NAV = 1.1025e18 + 1.1025e18 * 3e16 / 1e18 = 1.135575e18, then set APR=5%
        _advanceTimeAndUpdateRate(365 days, 5e16);
        uint256 navAtDeposit = oracle.baseNetValue();
        assertEq(navAtDeposit, 1135575000000000000);

        // Deposit 100 ASSET at current NAV (~1.1356)
        uint256 shares = _deposit(user1, 100e6);
        assertGt(shares, 0);

        // Wait for NAV to rise further (5% APR for another year)
        // Use absolute timestamp to avoid any issues
        vm.warp(startTs + 4 * 365 days);
        uint256 navAtRedeem = oracle.getLatestPrice();
        assertGt(navAtRedeem, navAtDeposit, "NAV should have increased");

        // Redeem all shares
        uint256 reqId = _requestRedemption(user1, shares);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // User should get back MORE than 100 ASSET (because NAV rose between deposit and redeem)
        assertGt(assetAmt, 100e6, "Redeemed amount should exceed deposit due to NAV growth");

        // Fund vault for the extra yield and approve
        uint256 vaultBal = asset.balanceOf(address(vault));
        if (assetAmt > vaultBal) {
            asset.mint(address(vault), assetAmt - vaultBal);
        }
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
        assertEq(fundToken.balanceOf(user1), 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.2 INT-8: High NAV (1000:1) full flow
    // ═══════════════════════════════════════════════════════════════════

    function test_INT8_highNav_fullFlow() public {
        // We need NAV = 1000e18. With 5% APR:
        // NAV = 1e18 + 1e18 * 5e16 * elapsed / (365d * 1e18) = 1000e18
        // elapsed = 999 * 365d / 0.05 = 7,292,700 days
        vm.warp(block.timestamp + 7_292_700 days);
        uint256 nav = oracle.getLatestPrice();
        assertEq(nav, 1000e18);

        // At NAV=1000, depositing 100 ASSET gives 0.1 SHARE (1e17) which is < minRedeemShares (1e18).
        // Lower minRedeemShares for this high-NAV scenario.
        vm.prank(admin);
        fundToken.setMinRedeemShares(1e16); // 0.01 SHARE min

        // Deposit 100 ASSET at NAV=1000
        uint256 shares = _deposit(user1, 100e6);
        // shares = 100e6 * 1e12 * 1e18 / 1000e18 = 1e17
        assertEq(shares, 1e17, "Should get 0.1 SHARE for 100 ASSET at NAV=1000");

        // Redeem
        uint256 reqId = _requestRedemption(user1, shares);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);
        assertEq(assetAmt, 100e6, "Should redeem back 100 ASSET");

        // Approve
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
        assertEq(asset.balanceOf(user1), 1000e6, "User fully recovered");
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.3 INT-10: Partial approve partial reject among 3 users
    // ═══════════════════════════════════════════════════════════════════

    function test_INT10_partialApprove_partialReject_threeUsers() public {
        // All three users deposit
        _deposit(user1, 100e6);
        _deposit(user2, 100e6);
        // user3 is whitelisted in Nav4626 but NOT in vault whitelist
        _deposit(user3, 100e6);

        assertEq(asset.balanceOf(address(vault)), 300e6);

        // All three request redemption
        uint256 req1 = _requestRedemption(user1, 100e18);
        uint256 req2 = _requestRedemption(user2, 100e18);
        uint256 req3 = _requestRedemption(user3, 100e18);

        (, , uint256 x1, uint256 s1, , ) = fundToken.redemptions(req1);
        (, , uint256 x2, uint256 s2, , ) = fundToken.redemptions(req2);
        (, , uint256 x3, uint256 s3, , ) = fundToken.redemptions(req3);

        vm.startPrank(redemptionApprover);

        // A approved
        fundToken.approveRedemption(req1, user1, x1, s1);
        // B rejected
        fundToken.rejectRedemption(req2, user2, x2, s2);
        // C approved
        fundToken.approveRedemption(req3, user3, x3, s3);

        vm.stopPrank();

        // A got ASSET back
        assertEq(asset.balanceOf(user1), 900e6 + 100e6);
        // B got shares back
        assertEq(fundToken.balanceOf(user2), 100e18);
        assertEq(asset.balanceOf(user2), 900e6); // no ASSET change
        // C got ASSET back
        assertEq(asset.balanceOf(user3), 900e6 + 100e6);
        // Vault has 100 ASSET (300 - 100 for A - 100 for C)
        assertEq(asset.balanceOf(address(vault)), 100e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.3 INT-11: Vault balance insufficient for later approvals
    // ═══════════════════════════════════════════════════════════════════

    function test_INT11_vaultBalanceInsufficient_laterApprovalReverts() public {
        // User1 deposits 100, user2 deposits 100 → vault has 200
        _deposit(user1, 100e6);
        _deposit(user2, 100e6);

        // Settlement operator withdraws 150, leaving vault with 50
        address custodyAddr = makeAddr("custody");
        vm.prank(admin);
        vault.setWhitelist(custodyAddr, true);
        vm.prank(settlementOperator);
        vault.withdraw(custodyAddr, 150e6);
        assertEq(asset.balanceOf(address(vault)), 50e6);

        // Both users request full redemption (100 ASSET each)
        uint256 req1 = _requestRedemption(user1, 100e18);
        _requestRedemption(user2, 100e18);

        (, , uint256 x1, uint256 s1, , ) = fundToken.redemptions(req1);

        vm.startPrank(redemptionApprover);

        // First approval succeeds (50 ASSET available... but we need 100!)
        // Actually vault only has 50, so even the first 100 ASSET approval should fail
        vm.expectRevert();
        fundToken.approveRedemption(req1, user1, x1, s1);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.3 INT-12: Different NAV at different deposit times
    // ═══════════════════════════════════════════════════════════════════

    function test_INT12_differentNavAtDifferentDepositTimes() public {
        // User1 deposits at NAV=1.0
        uint256 sharesA = _deposit(user1, 100e6);
        assertEq(sharesA, 100e18); // 100 SHARE

        // NAV rises to 1.1 (5% APR for 2 years, but let's use updateRate for precision)
        // Advance 2 years: NAV = 1.0 + 1.0 * 0.05 * 2 = 1.1
        vm.warp(block.timestamp + 730 days);
        uint256 navMid = oracle.getLatestPrice();
        assertEq(navMid, 1.1e18);

        // User2 deposits at NAV=1.1
        uint256 sharesB = _deposit(user2, 100e6);
        // shares = 100e6 * 1e12 * 1e18 / 1.1e18 = 100e18 / 1.1 ≈ 90.909090909090909090e18
        uint256 expectedShares = (uint256(100e6) * 1e12 * 1e18) / navMid;
        assertEq(sharesB, expectedShares);
        assertLt(sharesB, sharesA, "B should get fewer shares than A");

        // Both redeem at current NAV=1.1
        uint256 req1 = _requestRedemption(user1, sharesA);
        uint256 req2 = _requestRedemption(user2, sharesB);

        (, , uint256 x1, , , ) = fundToken.redemptions(req1);
        (, , uint256 x2, , , ) = fundToken.redemptions(req2);

        // User1: 100 SHARE at NAV=1.1 → 110 ASSET (profit!)
        assertEq(x1, 110e6);
        // User2: ~90.909... SHARE at NAV=1.1 → ~100 ASSET (no profit — just deposited)
        // Due to double rounding (assetToShares rounds down, then sharesToAsset rounds down),
        // user2 may lose up to 1 wei.
        assertApproxEqAbs(x2, 100e6, 1, "User2 should get back ~100 ASSET");
        assertLe(x2, 100e6, "Rounding favors protocol");
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.4 INT-14: Pending request during pause → approve blocked
    // ═══════════════════════════════════════════════════════════════════

    function test_INT14_pendingRequestDuringPause_approveBlocked() public {
        _deposit(user1, 100e6);

        // User requests redemption
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Pause
        vm.prank(admin);
        fundToken.pause();

        // Approve should revert (whenNotPaused)
        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.4 INT-17: Pending request during pause → reject blocked
    // ═══════════════════════════════════════════════════════════════════

    function test_INT17_pendingRequestDuringPause_rejectBlocked() public {
        _deposit(user1, 100e6);

        // User requests redemption
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Pause
        vm.prank(admin);
        fundToken.pause();

        // Reject should revert (_mintBypass has whenNotPaused)
        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.4 INT-17b: Pending request survives pause→unpause cycle
    // ═══════════════════════════════════════════════════════════════════

    function test_INT17b_pendingRequestSurvivesPauseUnpause() public {
        _deposit(user1, 100e6);

        // Request redemption (shares are burned)
        uint256 reqId = _requestRedemption(user1, 50e18);
        assertEq(fundToken.balanceOf(user1), 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Pause
        vm.prank(admin);
        fundToken.pause();

        // Wait during pause
        vm.warp(block.timestamp + 7 days);

        // Unpause
        vm.prank(admin);
        fundToken.unpause();

        // Approve should work after unpause
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // User gets ASSET
        assertEq(asset.balanceOf(user1), 900e6 + 50e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.5 INT-18: Freeze → verify blocked → forceRedeem
    // ═══════════════════════════════════════════════════════════════════

    function test_INT18_removedUser_blockedOps_thenForceRedeem() public {
        _deposit(user1, 100e6);

        // Remove from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // User can still transfer (whitelist not enforced on transfers)
        vm.prank(user1);
        fundToken.transfer(user2, 10e18);
        assertEq(fundToken.balanceOf(user2), 10e18);

        // User cannot request redemption
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.requestRedemption(10e18);

        // Owner forceRedeem works (90 remaining after transfer)
        vm.prank(admin);
        fundToken.forceRedeem(user1, 90e18);
        assertEq(fundToken.balanceOf(user1), 0, "All shares burned via forceRedeem");
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.5 INT-19: Removed from whitelist user pending request → approve succeeds
    // ═══════════════════════════════════════════════════════════════════

    function test_INT19_removedUser_pendingRequest_approveReverts() public {
        _deposit(user1, 100e6);

        // Request redemption
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Remove from whitelist AFTER request
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // approveRedemption checks whitelist — should revert
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // 4.5 INT-20: Removed from whitelist user pending request → reject succeeds
    // ═══════════════════════════════════════════════════════════════════

    function test_INT20_removedUser_pendingRequest_rejectSucceeds() public {
        _deposit(user1, 100e6);

        // Request redemption
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Remove from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // rejectRedemption uses _mintBypass which bypasses pause check
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        // Shares restored to removed user
        assertEq(fundToken.balanceOf(user1), 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.5 INT-21: Removed-whitelist user pending request → approve reverts
    // ═══════════════════════════════════════════════════════════════════

    function test_INT21_removedWhitelist_pendingRequest_approveReverts() public {
        _deposit(user1, 100e6);

        // Request redemption
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Remove user from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // approveRedemption checks whitelist — should revert
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.5 INT-22: Removed-whitelist user pending request → reject succeeds
    // ═══════════════════════════════════════════════════════════════════

    function test_INT22_removedWhitelist_pendingRequest_rejectSucceeds() public {
        _deposit(user1, 100e6);

        // Request redemption
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Remove from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // rejectRedemption uses _mintBypass which bypasses pause check
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        // Shares restored
        assertEq(fundToken.balanceOf(user1), 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.5 INT-23: Removed from whitelist → forceRedeem succeeds
    // ═══════════════════════════════════════════════════════════════════

    function test_INT23_removedWhitelist_forceRedeem() public {
        _deposit(user1, 100e6);

        // Remove from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // forceRedeem uses _burnBypass — bypasses pause check
        vm.prank(admin);
        fundToken.forceRedeem(user1, 100e18);
        assertEq(fundToken.balanceOf(user1), 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.5 INT-24: Removed from whitelist + pending + forceRedeem remaining + approve pending
    // ═══════════════════════════════════════════════════════════════════

    function test_INT24_removedWL_pendingAndForceRedeem() public {
        // User has 100 SHARE
        _deposit(user1, 100e6);

        // Redeem 50 SHARE (Pending), leaving 50 in balance
        uint256 reqId = _requestRedemption(user1, 50e18);
        assertEq(fundToken.balanceOf(user1), 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Remove from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // forceRedeem the remaining 50 SHARE
        vm.prank(admin);
        fundToken.forceRedeem(user1, 50e18);
        assertEq(fundToken.balanceOf(user1), 0);

        // Approve the pending request — should revert (user not whitelisted)
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // Only option: reject to return shares
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
        assertEq(fundToken.balanceOf(user1), 50e18); // shares returned via _mintBypass
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.6 INT-25: New approver can handle old pending requests
    // ═══════════════════════════════════════════════════════════════════

    function test_INT25_newApprover_handlesOldPendingRequests() public {
        _deposit(user1, 100e6);

        // Request redemption with old approver in place
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Admin grants REDEMPTION_APPROVER_ROLE to a new approver
        address newApprover = makeAddr("newApprover");
        vm.prank(admin);
        fundToken.grantRole(REDEMPTION_APPROVER_ROLE, newApprover);

        // New approver can approve old request (request not bound to specific approver)
        vm.prank(newApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
        assertEq(asset.balanceOf(user1), 900e6 + 50e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.6 INT-26: Old approver loses access after role revocation
    // ═══════════════════════════════════════════════════════════════════

    function test_INT26_oldApprover_losesAccessAfterRevocation() public {
        _deposit(user1, 100e6);

        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Revoke old approver
        vm.prank(admin);
        fundToken.revokeRole(REDEMPTION_APPROVER_ROLE, redemptionApprover);

        // Old approver attempts approval — should revert
        vm.prank(redemptionApprover);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                redemptionApprover,
                REDEMPTION_APPROVER_ROLE
            )
        );
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.6 INT-27: setOracle → subsequent mint uses new oracle
    // ═══════════════════════════════════════════════════════════════════

    function test_INT27_setOracle_subsequentMintUsesNewOracle() public {
        // Deploy a new oracle with different initial NAV (2e18 = 2:1)
        bytes memory newOracleInit = abi.encodeCall(
            CoboFundOracle.initialize,
            (admin, 2e18, DEFAULT_APR, MAX_APR, MAX_APR_DELTA, MIN_UPDATE_INTERVAL)
        );
        CoboFundOracle newOracle = CoboFundOracle(address(new ERC1967Proxy(address(oracleImpl), newOracleInit)));
        // Grant updater role on new oracle
        vm.prank(admin);
        newOracle.grantRole(NAV_UPDATER_ROLE, navUpdater);

        // Admin switches oracle
        vm.prank(admin);
        fundToken.setOracle(address(newOracle));

        // Now mint should use new oracle's NAV=2e18
        uint256 shares = _deposit(user1, 100e6);
        // shares = 100e6 * 1e12 * 1e18 / 2e18 = 50e18
        assertEq(shares, 50e18, "Should use new oracle NAV of 2.0");
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.6 INT-28: setVault → redemption approval from new vault
    // ═══════════════════════════════════════════════════════════════════

    function test_INT28_setVault_redemptionFromNewVault() public {
        // User deposits into current vault
        _deposit(user1, 100e6);
        uint256 reqId = _requestRedemption(user1, 50e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);

        // Deploy a new vault
        bytes memory newVaultInit = abi.encodeCall(
            CoboFundVault.initialize,
            (address(asset), address(fundToken), admin)
        );
        CoboFundVault newVault = CoboFundVault(address(new ERC1967Proxy(address(vaultImpl), newVaultInit)));

        // Fund the new vault with ASSET
        asset.mint(address(newVault), 200e6);

        // Admin switches fundToken to use new vault
        vm.prank(admin);
        fundToken.setVault(address(newVault));

        // The new vault already approved fundToken via initialize (max approval).
        // Approve redemption — should pull ASSET from newVault
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        assertEq(asset.balanceOf(user1), 900e6 + 50e6);
        // ASSET came from the new vault, not the old one
        assertEq(asset.balanceOf(address(newVault)), 200e6 - 50e6);
        // Old vault balance unchanged
        assertEq(asset.balanceOf(address(vault)), 100e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.6 INT-29: Old blocklist admin loses access after role revocation
    // ═══════════════════════════════════════════════════════════════════

    function test_INT29_oldBlocklistAdmin_losesAccess() public {
        // Revoke old blocklist admin
        vm.prank(admin);
        fundToken.revokeRole(MANAGER_ROLE, blocklistAdmin);

        // Old admin tries to freeze a user
        vm.prank(blocklistAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                blocklistAdmin,
                MANAGER_ROLE
            )
        );
        fundToken.removeFromWhitelist(user1);

        // Grant to new admin and verify it works
        address newBlocklistAdmin = makeAddr("newBlocklistAdmin");
        vm.prank(admin);
        fundToken.grantRole(MANAGER_ROLE, newBlocklistAdmin);

        vm.prank(newBlocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        assertFalse(fundToken.whitelist(user1));
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.6 INT-30: Settlement operator change
    // ═══════════════════════════════════════════════════════════════════

    function test_INT30_settlementOperator_change() public {
        _deposit(user1, 100e6);

        address custodyAddr = makeAddr("custody");
        vm.prank(admin);
        vault.setWhitelist(custodyAddr, true);

        address newSettlementOp = makeAddr("newSettlementOp");

        // Grant new operator and revoke old
        vm.startPrank(admin);
        vault.grantRole(SETTLEMENT_OPERATOR_ROLE, newSettlementOp);
        vault.revokeRole(SETTLEMENT_OPERATOR_ROLE, settlementOperator);
        vm.stopPrank();

        // New operator can withdraw
        vm.prank(newSettlementOp);
        vault.withdraw(custodyAddr, 30e6);
        assertEq(asset.balanceOf(custodyAddr), 30e6);

        // Old operator cannot withdraw
        vm.prank(settlementOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                settlementOperator,
                SETTLEMENT_OPERATOR_ROLE
            )
        );
        vault.withdraw(custodyAddr, 10e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.7 INT-31: Vault withdraw depletes balance → approve fails
    // ═══════════════════════════════════════════════════════════════════

    function test_INT31_vaultWithdrawDepletes_approveFails() public {
        // Users deposit 200 ASSET total
        _deposit(user1, 100e6);
        _deposit(user2, 100e6);
        assertEq(asset.balanceOf(address(vault)), 200e6);

        // Settlement withdraws 150
        address custodyAddr = makeAddr("custody");
        vm.prank(admin);
        vault.setWhitelist(custodyAddr, true);
        vm.prank(settlementOperator);
        vault.withdraw(custodyAddr, 150e6);
        assertEq(asset.balanceOf(address(vault)), 50e6);

        // User requests redemption of 100 ASSET
        uint256 reqId = _requestRedemption(user1, 100e18);
        (, , uint256 assetAmt, uint256 shareAmt, , ) = fundToken.redemptions(reqId);
        assertEq(assetAmt, 100e6);

        // Approve fails because vault only has 50 ASSET
        vm.prank(redemptionApprover);
        vm.expectRevert(); // SafeERC20 transfer will fail
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4.7 INT-32: Interleaved withdraws and approvals
    // ═══════════════════════════════════════════════════════════════════

    function test_INT32_interleavedWithdrawsAndApprovals() public {
        // User1 deposits 200, user2 deposits 100 → vault has 300
        _deposit(user1, 200e6);
        _deposit(user2, 100e6);
        assertEq(asset.balanceOf(address(vault)), 300e6);

        address custodyAddr = makeAddr("custody");
        vm.prank(admin);
        vault.setWhitelist(custodyAddr, true);

        // User1 requests redemption of 100 SHARE → 100 ASSET
        uint256 req1 = _requestRedemption(user1, 100e18);
        (, , uint256 x1, uint256 s1, , ) = fundToken.redemptions(req1);

        // Withdraw 100 → vault: 200
        vm.prank(settlementOperator);
        vault.withdraw(custodyAddr, 100e6);
        assertEq(asset.balanceOf(address(vault)), 200e6);

        // Approve req1 (100 ASSET) → vault: 100
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(req1, user1, x1, s1);
        assertEq(asset.balanceOf(address(vault)), 100e6);

        // User2 requests redemption of 50 SHARE → 50 ASSET
        uint256 req2 = _requestRedemption(user2, 50e18);
        (, , uint256 x2, uint256 s2, , ) = fundToken.redemptions(req2);

        // Withdraw 30 → vault: 70
        vm.prank(settlementOperator);
        vault.withdraw(custodyAddr, 30e6);
        assertEq(asset.balanceOf(address(vault)), 70e6);

        // Approve req2 (50 ASSET) → vault: 20
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(req2, user2, x2, s2);
        assertEq(asset.balanceOf(address(vault)), 20e6);

        // Final balance checks
        assertEq(asset.balanceOf(user1), 800e6 + 100e6); // 1000-200+100
        assertEq(asset.balanceOf(user2), 900e6 + 50e6); // 1000-100+50
        assertEq(asset.balanceOf(custodyAddr), 130e6); // 100+30
    }
}

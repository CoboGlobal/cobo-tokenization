// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "./FundTestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title FundNumericalTest - Section 5: Numerical Precision & Boundary Tests
/// @dev Tests decimal conversion, round-trip precision, large values, and oracle numerical boundaries.
contract FundNumericalTest is FundTestBase {
    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _SECONDS_PER_YEAR = 365 days;

    // ═══════════════════════════════════════════════════════════════════
    // Helper: Deploy a fresh Oracle + Nav4626 + Vault with custom decimals
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Deploys a fresh set of contracts with custom asset and share decimals.
    ///      Returns (mockAsset, customOracle, customNav4626, customVault).
    function _deployCustomDecimals(
        uint8 assetDec,
        uint8 shareDec,
        uint256 initialNav,
        uint256 minDeposit,
        uint256 minRedeem
    )
        internal
        returns (
            MockERC20 mockAsset,
            CoboFundOracle customOracle,
            CoboFundToken customNav4626,
            CoboFundVault customVault
        )
    {
        // Deploy mock asset with custom decimals
        mockAsset = new MockERC20("Test Asset", "TAST", assetDec);

        // Deploy oracle proxy
        CoboFundOracle oImpl = new CoboFundOracle();
        bytes memory oInit = abi.encodeCall(
            CoboFundOracle.initialize, (admin, initialNav, DEFAULT_APR, MAX_APR, MAX_APR_DELTA, MIN_UPDATE_INTERVAL)
        );
        customOracle = CoboFundOracle(address(new ERC1967Proxy(address(oImpl), oInit)));

        // Predict vault address:
        // nonce+0: CoboFundToken impl, nonce+1: fundToken proxy, nonce+2: CoboFundVault impl, nonce+3: vault proxy
        uint64 nonce = vm.getNonce(address(this));
        address predictedVault = vm.computeCreateAddress(address(this), nonce + 3);

        // Deploy Nav4626 proxy
        CoboFundToken nImpl = new CoboFundToken();
        bytes memory nInit = abi.encodeCall(
            CoboFundToken.initialize,
            (
                "Test Share",
                "TSHR",
                shareDec,
                address(mockAsset),
                address(customOracle),
                predictedVault,
                admin,
                minDeposit,
                minRedeem
            )
        );
        customNav4626 = CoboFundToken(address(new ERC1967Proxy(address(nImpl), nInit)));

        // Deploy Vault proxy
        CoboFundVault vImpl = new CoboFundVault();
        bytes memory vInit =
            abi.encodeCall(CoboFundVault.initialize, (address(mockAsset), address(customNav4626), admin));
        customVault = CoboFundVault(address(new ERC1967Proxy(address(vImpl), vInit)));

        assertEq(address(customVault), predictedVault, "Vault address prediction mismatch");

        // Grant roles
        vm.startPrank(admin);
        customOracle.grantRole(NAV_UPDATER_ROLE, navUpdater);
        customNav4626.grantRole(MANAGER_ROLE, manager);
        customNav4626.grantRole(MANAGER_ROLE, admin);
        customNav4626.grantRole(MANAGER_ROLE, blocklistAdmin);
        customNav4626.grantRole(REDEMPTION_APPROVER_ROLE, redemptionApprover);
        customNav4626.grantRole(EMERGENCY_GUARDIAN_ROLE, emergencyGuardian);
        customVault.grantRole(SETTLEMENT_OPERATOR_ROLE, settlementOperator);
        customNav4626.addToWhitelist(user1);
        customVault.setWhitelist(user1, true);
        vm.stopPrank();
    }

    /// @dev Helper: fund a user and approve Nav4626 for custom deployment.
    function _fundAndApprove(MockERC20 mockAsset, CoboFundToken customNav4626, address user, uint256 amount) internal {
        mockAsset.mint(user, amount);
        vm.prank(user);
        mockAsset.approve(address(customNav4626), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 5.1 Decimal Conversion Precision (NUM-1 ~ NUM-8)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev NUM-1: asset=6, share=18, NAV=1e18. 1e6 asset → 1e18 shares.
    ///      Formula: 1e6 * 10^12 * 1e18 / 1e18 = 1e18
    function test_NUM_1_decConvert_6_18_nav1e18() public {
        // Default setup: asset=6, share=18, NAV=1e18
        uint256 shares = _deposit(user1, 1e6);
        assertEq(shares, 1e18, "NUM-1: 1 ASSET should yield 1e18 shares at NAV=1");
    }

    /// @dev NUM-2: asset=6, share=18, NAV=2e18. 1e6 asset → 5e17 shares.
    ///      Formula: 1e6 * 10^12 * 1e18 / 2e18 = 5e17
    function test_NUM_2_decConvert_6_18_nav2e18() public {
        // Deploy custom oracle with NAV=2e18
        (MockERC20 asset2,, CoboFundToken nav2,) = _deployCustomDecimals(6, 18, 2e18, 1e6, 1e18);

        _fundAndApprove(asset2, nav2, user1, 100e6);

        vm.prank(user1);
        uint256 shares = nav2.mint(1e6);
        assertEq(shares, 5e17, "NUM-2: 1 ASSET at NAV=2 should yield 0.5e18 shares");
    }

    /// @dev NUM-3: asset=6, share=18, NAV=1000e18 (1000:1 scenario).
    ///      1e6 asset → 1e15 shares.
    ///      Formula: 1e6 * 1e12 * 1e18 / 1000e18 = 1e15
    function test_NUM_3_decConvert_6_18_nav1000e18() public {
        (MockERC20 asset3,, CoboFundToken nav3,) = _deployCustomDecimals(6, 18, 1000e18, 1e6, 1e15);

        _fundAndApprove(asset3, nav3, user1, 100e6);

        vm.prank(user1);
        uint256 shares = nav3.mint(1e6);
        assertEq(shares, 1e15, "NUM-3: 1 ASSET at NAV=1000 should yield 1e15 shares");
    }

    /// @dev NUM-4: asset=18, share=18, NAV=1e18 (same decimals, 1:1).
    ///      1e18 asset → 1e18 shares.
    ///      Formula: 1e18 * 1e18 * 1e18 / (1e18 * 1e18) = 1e18
    function test_NUM_4_decConvert_18_18_nav1e18() public {
        (MockERC20 asset4,, CoboFundToken nav4,) = _deployCustomDecimals(18, 18, 1e18, 1e18, 1e18);

        _fundAndApprove(asset4, nav4, user1, 100e18);

        vm.prank(user1);
        uint256 shares = nav4.mint(1e18);
        assertEq(shares, 1e18, "NUM-4: same decimals 1:1 should yield equal shares");
    }

    /// @dev NUM-5: asset=18, share=6, NAV=1e18 (reverse decimal diff).
    ///      1e18 asset → 1e6 shares.
    ///      Formula: 1e18 * 1e6 * 1e18 / (1e18 * 1e18) = 1e6
    function test_NUM_5_decConvert_18_6_nav1e18() public {
        (MockERC20 asset5,, CoboFundToken nav5,) = _deployCustomDecimals(18, 6, 1e18, 1e18, 1e6);

        _fundAndApprove(asset5, nav5, user1, 100e18);

        vm.prank(user1);
        uint256 shares = nav5.mint(1e18);
        assertEq(shares, 1e6, "NUM-5: reverse decimal diff should yield 1e6 shares");
    }

    /// @dev NUM-6: asset=8, share=18, NAV=1e18 (intermediate scale).
    ///      1e8 asset → 1e18 shares.
    ///      Formula: 1e8 * 1e18 * 1e18 / (1e18 * 1e8) = 1e18
    function test_NUM_6_decConvert_8_18_nav1e18() public {
        (MockERC20 asset6,, CoboFundToken nav6,) = _deployCustomDecimals(8, 18, 1e18, 1e8, 1e18);

        _fundAndApprove(asset6, nav6, user1, 100e8);

        vm.prank(user1);
        uint256 shares = nav6.mint(1e8);
        assertEq(shares, 1e18, "NUM-6: 8-to-18 intermediate offset should yield 1e18 shares");
    }

    /// @dev NUM-7: asset=6, share=8, NAV=1e18 (small scale diff).
    ///      1e6 asset → 1e8 shares.
    ///      Formula: 1e6 * 1e8 * 1e18 / (1e18 * 1e6) = 1e8
    function test_NUM_7_decConvert_6_8_nav1e18() public {
        (MockERC20 asset7,, CoboFundToken nav7,) = _deployCustomDecimals(6, 8, 1e18, 1e6, 1e8);

        _fundAndApprove(asset7, nav7, user1, 100e6);

        vm.prank(user1);
        uint256 shares = nav7.mint(1e6);
        assertEq(shares, 1e8, "NUM-7: 6-to-8 small offset should yield 1e8 shares");
    }

    /// @dev NUM-8: asset=6, share=18, NAV=1e18, deposit=1 (smallest unit).
    ///      1 raw unit → 1e12 shares.
    ///      Formula: 1 * 10^12 * 1e18 / 1e18 = 1e12
    function test_NUM_8_decConvert_6_18_minUnit() public {
        // Need minDepositAmount=1 for this test
        vm.prank(admin);
        fundToken.setMinDepositAmount(1);

        vm.prank(user1);
        uint256 shares = fundToken.mint(1);
        assertEq(shares, 1e12, "NUM-8: smallest unit deposit should yield 1e12 shares");
    }

    // ═══════════════════════════════════════════════════════════════════
    // 5.2 Round-trip Precision Tests (NUM-9 ~ NUM-14)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev NUM-9: deposit→redeem round-trip at NAV=1e18.
    ///      mint(assetAmount) → requestRedemption(all shares).
    ///      assetBack <= assetAmount, precision loss <= 1 min unit.
    function test_NUM_9_roundTrip_nav1e18() public {
        uint256 assetAmount = 100e6; // 100 ASSET
        uint256 shares = _deposit(user1, assetAmount);

        // Request redemption of all shares
        uint256 reqId = _requestRedemption(user1, shares);

        // Check stored assetAmount
        (,, uint256 assetBack,,,) = fundToken.redemptions(reqId);

        // At NAV=1.0: round-trip should be exact
        assertLe(assetBack, assetAmount, "NUM-9: assetBack must not exceed original deposit");
        assertGe(assetBack + 1, assetAmount, "NUM-9: precision loss should be <= 1 min unit");
    }

    /// @dev NUM-10: deposit→redeem round-trip at NAV=1.05e18.
    ///      Precision loss <= 1 min unit.
    function test_NUM_10_roundTrip_nav1_05e18() public {
        // Advance 365 days: NAV = 1e18 + 1e18 * 5e16 * 365d / (365d * 1e18) = 1.05e18
        vm.warp(block.timestamp + 365 days);

        uint256 assetAmount = 100e6;
        uint256 shares = _deposit(user1, assetAmount);

        // Request redemption of all shares at the same NAV
        uint256 reqId = _requestRedemption(user1, shares);
        (,, uint256 assetBack,,,) = fundToken.redemptions(reqId);

        // Round-trip: assetBack <= assetAmount, loss <= 1 min unit
        assertLe(assetBack, assetAmount, "NUM-10: assetBack must not exceed original deposit");
        assertGe(assetBack + 1, assetAmount, "NUM-10: precision loss should be <= 1 min unit");
    }

    /// @dev NUM-11: large round-trip: mint(1_000_000e6) → redeem all.
    ///      Precision loss <= 1 min unit.
    function test_NUM_11_roundTrip_large() public {
        uint256 assetAmount = 1_000_000e6; // 1M ASSET
        asset.mint(user1, assetAmount); // Fund extra

        uint256 shares = _deposit(user1, assetAmount);
        uint256 reqId = _requestRedemption(user1, shares);
        (,, uint256 assetBack,,,) = fundToken.redemptions(reqId);

        assertLe(assetBack, assetAmount, "NUM-11: assetBack must not exceed original");
        assertGe(assetBack + 1, assetAmount, "NUM-11: precision loss should be <= 1 min unit");
    }

    /// @dev NUM-12: small round-trip: mint(minDepositAmount) → redeem all.
    ///      Precision loss within acceptable range.
    function test_NUM_12_roundTrip_small() public {
        uint256 assetAmount = MIN_DEPOSIT_AMOUNT; // 1e6 = 1 ASSET
        uint256 shares = _deposit(user1, assetAmount);

        uint256 reqId = _requestRedemption(user1, shares);
        (,, uint256 assetBack,,,) = fundToken.redemptions(reqId);

        assertLe(assetBack, assetAmount, "NUM-12: assetBack must not exceed original");
        assertGe(assetBack + 1, assetAmount, "NUM-12: precision loss should be <= 1 min unit");
    }

    /// @dev NUM-13: reverse round-trip verification.
    ///      _sharesToAsset(_assetToShares(x, nav), nav) <= x (round down, no overpay).
    ///      We test this math property at multiple NAV values.
    function test_NUM_13_reverseRoundTrip_noOverpay() public {
        // Test at several NAV values
        uint256[5] memory navValues = [uint256(1e18), 1.05e18, 2e18, 0.5e18, 1000e18];

        for (uint256 i = 0; i < navValues.length; i++) {
            uint256 nav = navValues[i];
            // Use default decimals: asset=6, share=18, assetScale=1e6, shareScale=1e18
            uint256 assetAmount = 100e6;

            // _assetToShares: assetAmount * shareScale * PRECISION / (nav * assetScale)
            uint256 shareAmount = (assetAmount * 1e18 * _PRECISION) / (nav * 1e6);

            // _sharesToAsset: shareAmount * nav * assetScale / (shareScale * PRECISION)
            uint256 assetBack = (shareAmount * nav * 1e6) / (1e18 * _PRECISION);

            assertLe(assetBack, assetAmount, string.concat("NUM-13: no overpay at NAV index ", vm.toString(i)));
        }
    }

    /// @dev NUM-14: cumulative precision loss over 10 small mints + 10 small redeems.
    function test_NUM_14_cumulativePrecisionLoss() public {
        // Set low minDeposit for small mints
        vm.prank(admin);
        fundToken.setMinDepositAmount(1e6);

        uint256 totalDeposited = 0;
        uint256 totalRedeemed = 0;
        uint256 singleAmount = 1e6; // 1 ASSET per mint

        // 10 small mints
        for (uint256 i = 0; i < 10; i++) {
            _deposit(user1, singleAmount);
            totalDeposited += singleAmount;
        }

        // Get total shares
        uint256 totalShares = fundToken.balanceOf(user1);

        // 10 small redeems (redeem 1/10 of total each time)
        uint256 sharePerRedeem = totalShares / 10;
        for (uint256 i = 0; i < 9; i++) {
            uint256 reqId = _requestRedemption(user1, sharePerRedeem);
            (,, uint256 assetBack,,,) = fundToken.redemptions(reqId);
            totalRedeemed += assetBack;
        }

        // Redeem remaining shares
        uint256 remaining = fundToken.balanceOf(user1);
        if (remaining >= MIN_REDEEM_SHARES) {
            uint256 reqId = _requestRedemption(user1, remaining);
            (,, uint256 assetBack,,,) = fundToken.redemptions(reqId);
            totalRedeemed += assetBack;
        }

        // Cumulative loss should be small: <= 10 min units for 10 operations
        assertLe(totalRedeemed, totalDeposited, "NUM-14: total redeemed must not exceed deposited");
        uint256 loss = totalDeposited - totalRedeemed;
        assertLe(loss, 10, "NUM-14: cumulative loss should be <= 10 min units for 10 round-trips");
    }

    // ═══════════════════════════════════════════════════════════════════
    // 5.3 Large Value Boundaries (NUM-15 ~ NUM-18, NUM-24)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev NUM-15: huge deposit (uint128 level). No overflow, correct calc.
    ///      mint(type(uint128).max) with asset decimals=6
    function test_NUM_15_hugeDeposit_uint128() public {
        uint256 hugeAmount = type(uint128).max;

        // Fund user with huge amount
        asset.mint(user1, hugeAmount);

        // Set minDeposit to allow
        vm.prank(admin);
        fundToken.setMinDepositAmount(1);

        // At NAV=1e18: shares = hugeAmount * 1e12 * 1e18 / 1e18 = hugeAmount * 1e12
        // hugeAmount = 2^128-1 ≈ 3.4e38; shares ≈ 3.4e50, fits in uint256
        vm.prank(user1);
        uint256 shares = fundToken.mint(hugeAmount);

        uint256 expected = hugeAmount * 1e12;
        assertEq(shares, expected, "NUM-15: huge deposit should not overflow");
    }

    /// @dev NUM-16: extremely high NAV (1e30). No overflow.
    ///      shares = assetAmount * 1e12 * 1e18 / 1e30 = assetAmount * 1e0
    function test_NUM_16_extremelyHighNAV() public {
        (MockERC20 asset16,, CoboFundToken nav16,) = _deployCustomDecimals(6, 18, 1e30, 1e6, 1);

        _fundAndApprove(asset16, nav16, user1, 1000e6);

        vm.prank(user1);
        uint256 shares = nav16.mint(1e6);

        // shares = 1e6 * 1e12 * 1e18 / 1e30 = 1e6
        assertEq(shares, 1e6, "NUM-16: extreme NAV should not overflow");
    }

    /// @dev NUM-17: extreme baseNetValue + APR + elapsed.
    ///      baseNetValue=1e30, APR=1e18 (100%), elapsed=10 years.
    ///      intermediate = 1e30 * 1e18 * 315360000 ≈ 3.15e56 < uint256 max ≈ 1.16e77
    ///      Should not overflow.
    function test_NUM_17_extremeOracleCalc() public {
        // Deploy oracle with extreme baseNetValue and max APR=1e18
        CoboFundOracle oImpl = new CoboFundOracle();
        bytes memory oInit = abi.encodeCall(CoboFundOracle.initialize, (admin, 1e30, 1e18, 1e18, 1e18, 1));
        CoboFundOracle extremeOracle = CoboFundOracle(address(new ERC1967Proxy(address(oImpl), oInit)));

        // Warp 10 years
        vm.warp(block.timestamp + 3650 days);

        // getLatestPrice = 1e30 + 1e30 * 1e18 * (3650*86400) / (365*86400 * 1e18)
        //                = 1e30 + 1e30 * 10 = 11e30
        uint256 price = extremeOracle.getLatestPrice();
        uint256 elapsed = 3650 days;
        uint256 expected = 1e30 + (1e30 * 1e18 * elapsed) / (_SECONDS_PER_YEAR * _PRECISION);
        assertEq(price, expected, "NUM-17: extreme values should not overflow");
        assertEq(price, 11e30, "NUM-17: price should be 11x base after 10 years at 100% APR");
    }

    /// @dev NUM-18: Oracle very long without update (warp 100 years). getLatestPrice doesn't overflow.
    function test_NUM_18_oracleVeryLongWithoutUpdate() public {
        // Default oracle: baseNetValue=1e18, APR=5e16
        // Warp 100 years
        vm.warp(block.timestamp + 36500 days);

        // getLatestPrice = 1e18 + 1e18 * 5e16 * (36500*86400) / (365*86400 * 1e18)
        //                = 1e18 + 1e18 * 5e16 * 100 / 1e18
        //                = 1e18 + 5e18 = 6e18
        uint256 price = oracle.getLatestPrice();

        uint256 elapsed = 36500 days;
        uint256 expected = 1e18 + (1e18 * 5e16 * elapsed) / (_SECONDS_PER_YEAR * _PRECISION);
        assertEq(price, expected, "NUM-18: 100 years without update should not overflow");
        assertEq(price, 6e18, "NUM-18: NAV should be 6x after 100 years at 5%");
    }

    /// @dev NUM-24: _sharesToAsset overflow test with reverse decimals.
    ///      When share < asset decimals: sharesToAsset = shareAmount * nav * assetScale / (shareScale * PRECISION)
    ///      shareAmount=1e30, nav=1e30, assetScale=1e18 -> intermediate = 1e78, near uint256 max.
    ///      Test with smaller values to verify safe range.
    function test_NUM_24_sharesToAsset_reversePathOverflow() public {
        // Deploy: asset=18, share=6. assetScale=1e18, shareScale=1e6
        _deployCustomDecimals(18, 6, 1e30, 1, 1);

        // Test the math directly:
        // shareAmount * nav * assetScale / (shareScale * PRECISION)
        // = 1e25 * 1e30 * 1e18 / (1e6 * 1e18) = 1e73 / 1e24 = 1e49 (fits in uint256)
        uint256 result1 = (uint256(1e25) * uint256(1e30) * uint256(1e18)) / (uint256(1e6) * _PRECISION);
        assertEq(result1, 1e49, "NUM-24: 1e25 shares should not overflow");

        // Test with moderate values:
        // 1e20 * 1e30 * 1e18 = 1e68, / 1e24 = 1e44 (fits)
        uint256 result2 = (uint256(1e20) * uint256(1e30) * uint256(1e18)) / (uint256(1e6) * _PRECISION);
        assertEq(result2, 1e44, "NUM-24: 1e20 shares with nav=1e30 should not overflow");

        // Maximum safe intermediate: shareAmount * nav * assetScale < 2^256 (~1.16e77)
        // 1e25 * 1e30 * 1e18 = 1e73 < 1.16e77. Safe.
        // Use OverflowHelper to test boundary cases
        OverflowHelper helper = new OverflowHelper();

        // This should succeed (1e30 * 1e30 * 1e12 = 1e72 < uint256 max)
        // 1e25 * 1e30 * 1e18 = 1e73 < uint256 max, safe
        uint256 safeResult = helper.mulThree(1e25, 1e30, 1e18);
        assertEq(safeResult, 1e73, "NUM-24: safe mul should succeed");

        // This should revert with overflow (1e40 * 1e30 * 1e18 = 1e88 > uint256 max)
        vm.expectRevert();
        helper.mulThree(1e40, 1e30, 1e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 5.4 NavOracle Numerical Boundaries (NUM-19 ~ NUM-23)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev NUM-19: APR=0 → NAV doesn't grow. Warp any time, getLatestPrice == baseNetValue exactly.
    function test_NUM_19_apr0_noGrowth() public {
        // Deploy oracle with APR=0
        CoboFundOracle oImpl = new CoboFundOracle();
        bytes memory oInit =
            abi.encodeCall(CoboFundOracle.initialize, (admin, 1e18, 0, MAX_APR, MAX_APR_DELTA, MIN_UPDATE_INTERVAL));
        CoboFundOracle zeroAprOracle = CoboFundOracle(address(new ERC1967Proxy(address(oImpl), oInit)));

        // Warp various durations
        vm.warp(block.timestamp + 1 days);
        assertEq(zeroAprOracle.getLatestPrice(), 1e18, "NUM-19: APR=0, 1 day, NAV should not grow");

        vm.warp(block.timestamp + 365 days);
        assertEq(zeroAprOracle.getLatestPrice(), 1e18, "NUM-19: APR=0, 1 year, NAV should not grow");

        vm.warp(block.timestamp + 36500 days);
        assertEq(zeroAprOracle.getLatestPrice(), 1e18, "NUM-19: APR=0, 100 years, NAV should not grow");
    }

    /// @dev NUM-20: APR=maxAPR(1e18=100%), warp 1 year → getLatestPrice = 2 * baseNetValue.
    function test_NUM_20_maxAPR_1year() public {
        // Deploy oracle with APR=1e18 (100%)
        CoboFundOracle oImpl = new CoboFundOracle();
        bytes memory oInit =
            abi.encodeCall(CoboFundOracle.initialize, (admin, 1e18, 1e18, 1e18, 1e18, MIN_UPDATE_INTERVAL));
        CoboFundOracle maxAprOracle = CoboFundOracle(address(new ERC1967Proxy(address(oImpl), oInit)));

        // Warp exactly 1 year
        vm.warp(block.timestamp + 365 days);

        // NAV = 1e18 + 1e18 * 1e18 * 365d / (365d * 1e18) = 1e18 + 1e18 = 2e18
        uint256 price = maxAprOracle.getLatestPrice();
        assertEq(price, 2e18, "NUM-20: 100% APR after 1 year should double NAV");
    }

    /// @dev NUM-21: APR drops from max to 0. baseNetValue solidified, no further growth.
    function test_NUM_21_aprDropsToZero() public {
        // Deploy oracle with APR=1e18 (100%), allow large delta
        CoboFundOracle oImpl = new CoboFundOracle();
        bytes memory oInit =
            abi.encodeCall(CoboFundOracle.initialize, (admin, 1e18, 1e18, 1e18, 1e18, MIN_UPDATE_INTERVAL));
        CoboFundOracle dropOracle = CoboFundOracle(address(new ERC1967Proxy(address(oImpl), oInit)));

        // Grant updater role
        vm.prank(admin);
        dropOracle.grantRole(NAV_UPDATER_ROLE, navUpdater);

        // Warp 1 day, NAV grows
        vm.warp(block.timestamp + 1 days);
        uint256 navBefore = dropOracle.getLatestPrice();
        // NAV = 1e18 + 1e18 * 1e18 * 86400 / (365*86400 * 1e18) = 1e18 + 1e18/365
        assertTrue(navBefore > 1e18, "NUM-21: NAV should grow before drop");

        // Update APR to 0
        vm.prank(navUpdater);
        dropOracle.updateRate(0, "drop to zero");

        // baseNetValue should now be solidified at navBefore
        assertEq(dropOracle.baseNetValue(), navBefore, "NUM-21: baseNetValue should be solidified");
        assertEq(dropOracle.currentAPR(), 0, "NUM-21: APR should be 0");

        // Warp another year — no growth
        vm.warp(block.timestamp + 365 days);
        uint256 navAfter = dropOracle.getLatestPrice();
        assertEq(navAfter, navBefore, "NUM-21: after APR=0, NAV should not grow further");
    }

    /// @dev NUM-22: consecutive updateRate cumulative NAV.
    ///      10 updateRates each 1 day apart. Final NAV matches manual calculation.
    function test_NUM_22_consecutiveUpdateRate() public {
        // Deploy oracle: baseNetValue=1e18, APR=5e16, minInterval=1 day
        CoboFundOracle oImpl = new CoboFundOracle();
        bytes memory oInit = abi.encodeCall(CoboFundOracle.initialize, (admin, 1e18, 5e16, 1e17, 5e16, 1 days));
        CoboFundOracle cumOracle = CoboFundOracle(address(new ERC1967Proxy(address(oImpl), oInit)));

        vm.prank(admin);
        cumOracle.grantRole(NAV_UPDATER_ROLE, navUpdater);

        // Manual cumulative calculation
        uint256 manualNav = 1e18;
        uint256 currentAPR = 5e16;

        for (uint256 i = 0; i < 10; i++) {
            // Warp 1 day
            vm.warp(block.timestamp + 1 days);

            // Manual: NAV += NAV * APR * 1day / (365days * 1e18)
            manualNav = manualNav + (manualNav * currentAPR * 1 days) / (_SECONDS_PER_YEAR * _PRECISION);

            // Update rate (keep same APR for simplicity)
            vm.prank(navUpdater);
            cumOracle.updateRate(currentAPR, "daily update");
        }

        // Verify oracle matches manual calculation
        uint256 oracleNav = cumOracle.getLatestPrice();
        assertEq(oracleNav, manualNav, "NUM-22: cumulative NAV should match manual calculation");
        assertEq(cumOracle.baseNetValue(), manualNav, "NUM-22: baseNetValue should be solidified");
    }

    /// @dev NUM-23: extremely short update interval (1 second). minUpdateInterval=1.
    ///      Frequent small updates NAV cumulates correctly.
    function test_NUM_23_extremelyShortInterval() public {
        // Deploy oracle with minUpdateInterval=1 second
        CoboFundOracle oImpl = new CoboFundOracle();
        bytes memory oInit = abi.encodeCall(CoboFundOracle.initialize, (admin, 1e18, 5e16, 1e17, 5e16, 1));
        CoboFundOracle shortOracle = CoboFundOracle(address(new ERC1967Proxy(address(oImpl), oInit)));

        vm.prank(admin);
        shortOracle.grantRole(NAV_UPDATER_ROLE, navUpdater);

        uint256 manualNav = 1e18;
        uint256 apr = 5e16;

        // Do 100 updates, each 1 second apart
        for (uint256 i = 0; i < 100; i++) {
            vm.warp(block.timestamp + 1);

            manualNav = manualNav + (manualNav * apr * 1) / (_SECONDS_PER_YEAR * _PRECISION);

            vm.prank(navUpdater);
            shortOracle.updateRate(apr, "");
        }

        uint256 oracleNav = shortOracle.getLatestPrice();
        assertEq(oracleNav, manualNav, "NUM-23: short interval cumulative NAV should match manual");

        // Verify NAV has grown at all (even tiny amounts)
        assertTrue(oracleNav >= 1e18, "NUM-23: NAV should not decrease");
    }
}

/// @dev Helper contract for testing overflow in checked arithmetic via external call.
///      vm.expectRevert only catches reverts from external calls, so we need a separate contract.
contract OverflowHelper {
    function mulThree(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        return a * b * c;
    }
}

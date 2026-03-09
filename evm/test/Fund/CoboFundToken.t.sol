// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "./FundTestBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoboFundTokenTest is FundTestBase {
    // ═══════════════════════════════════════════════════════════════════
    // 2.1 initialize
    // ═══════════════════════════════════════════════════════════════════

    function test_fundToken_initialize_normal() public view {
        assertEq(fundToken.name(), "SHARE Gold Fund");
        assertEq(fundToken.symbol(), "SHARE");
        assertEq(fundToken.decimals(), SHARE_DECIMALS);
        assertEq(address(fundToken.asset()), address(asset));
        assertEq(address(fundToken.oracle()), address(oracle));
        assertEq(fundToken.vault(), address(vault));
        assertEq(fundToken.minDepositAmount(), MIN_DEPOSIT_AMOUNT);
        assertEq(fundToken.minRedeemShares(), MIN_REDEEM_SHARES);
        assertEq(fundToken.assetDecimals(), ASSET_DECIMALS);
        assertTrue(fundToken.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    function test_fundToken_initialize_revert_double() public {
        vm.expectRevert();
        fundToken.initialize("X", "X", 18, address(asset), address(oracle), address(vault), admin, 1, 1);
    }

    function test_fundToken_initialize_revert_zeroXaut() public {
        CoboFundToken impl = new CoboFundToken();
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                CoboFundToken.initialize, ("X", "X", 18, address(0), address(oracle), address(vault), admin, 1, 1)
            )
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.2 Deposit (mint)
    // ═══════════════════════════════════════════════════════════════════

    // F-MINT-1: Normal deposit
    function test_mint_normal() public {
        // At NAV=1e18, 10 ASSET → 10 SHARE
        uint256 shares = _deposit(user1, 10e6);
        assertEq(shares, 10e18);
        assertEq(fundToken.balanceOf(user1), 10e18);
        assertEq(fundToken.totalSupply(), 10e18);
        // ASSET went to vault
        assertEq(asset.balanceOf(address(vault)), 10e6);
        assertEq(asset.balanceOf(user1), 990e6);
    }

    // F-MINT-2: Deposit at higher NAV
    function test_mint_higherNAV() public {
        // Advance 365 days at 5% → NAV = 1.05e18
        vm.warp(block.timestamp + 365 days);

        // 10 ASSET → shares = 10e6 * 1e12 * 1e18 / 1.05e18 = 10e18 / 1.05 ≈ 9.523809e18
        uint256 shares = _deposit(user1, 10e6);
        uint256 expected = (uint256(10e6) * uint256(1e12) * uint256(1e18)) / uint256(1.05e18);
        assertEq(shares, expected);
    }

    // F-MINT-3: Non-whitelisted user reverts
    function test_mint_revert_notWhitelisted() public {
        asset.mint(attacker, 100e6);
        vm.prank(attacker);
        asset.approve(address(fundToken), type(uint256).max);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, attacker));
        fundToken.mint(10e6);
    }

    // F-MINT-4: Frozen user reverts
    function test_mint_revert_frozen() public {
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.mint(10e6);
    }

    // F-MINT-5: Below minimum deposit reverts
    function test_mint_revert_belowMinDeposit() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.BelowMinDeposit.selector, 100, MIN_DEPOSIT_AMOUNT));
        fundToken.mint(100); // 0.0001 ASSET < 1 ASSET minimum
    }

    // F-MINT-6: Paused reverts
    function test_mint_revert_paused() public {
        vm.prank(admin);
        fundToken.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundToken.mint(10e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.3 Request Redemption
    // ═══════════════════════════════════════════════════════════════════

    // F-REDEEM-1: Normal redemption request
    function test_requestRedemption_normal() public {
        _deposit(user1, 10e6); // get 10 SHARE

        uint256 reqId = _requestRedemption(user1, 5e18); // redeem 5 SHARE
        assertEq(reqId, 0);
        assertEq(fundToken.balanceOf(user1), 5e18); // burned 5
        assertEq(fundToken.redemptionCount(), 1);

        // Check stored request
        (
            uint256 id,
            address ruser,
            uint256 assetAmt,
            uint256 shareAmt,
            uint256 ts,
            CoboFundToken.RedemptionStatus status
        ) = fundToken.redemptions(0);
        assertEq(id, 0);
        assertEq(ruser, user1);
        assertEq(shareAmt, 5e18);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Pending));
        assertTrue(assetAmt > 0);
    }

    // F-REDEEM-2: Below min redeem reverts
    function test_requestRedemption_revert_belowMin() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.BelowMinRedeem.selector, 1e17, MIN_REDEEM_SHARES));
        fundToken.requestRedemption(1e17); // 0.1 SHARE < 1 SHARE min
    }

    // F-REDEEM-3: Non-whitelisted user reverts
    function test_requestRedemption_revert_notWhitelisted() public {
        _deposit(user1, 10e6);

        // Remove user1 from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.requestRedemption(5e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.4 Approve Redemption
    // ═══════════════════════════════════════════════════════════════════

    // F-APPROVE-1: Normal approve
    function test_approveRedemption_normal() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);

        // Get stored values
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        // Fund vault (deposit already sent ASSET there)
        uint256 vaultBal = asset.balanceOf(address(vault));
        assertTrue(vaultBal >= assetAmt, "Vault should have enough ASSET");

        uint256 user1BalBefore = asset.balanceOf(user1);

        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // Check status
        (,,,,, CoboFundToken.RedemptionStatus status) = fundToken.redemptions(reqId);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Executed));

        // User received ASSET
        assertEq(asset.balanceOf(user1), user1BalBefore + assetAmt);
    }

    // F-APPROVE-2: Non-approver reverts
    function test_approveRedemption_revert_notApprover() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(attacker);
        vm.expectRevert();
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // F-APPROVE-3: Non-existent reqId reverts (default value attack)
    function test_approveRedemption_revert_invalidRequest() public {
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.InvalidRedemptionRequest.selector, 999));
        fundToken.approveRedemption(999, address(0), 0, 0);
    }

    // F-APPROVE-4: Already executed reverts
    function test_approveRedemption_revert_alreadyExecuted() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // Try again
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId));
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // F-APPROVE-5: Param mismatch reverts
    function test_approveRedemption_revert_paramMismatch() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionParamMismatch.selector, reqId));
        fundToken.approveRedemption(reqId, user2, assetAmt, shareAmt); // wrong user
    }

    // F-APPROVE-6: Paused reverts
    function test_approveRedemption_revert_paused() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(admin);
        fundToken.pause();

        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.5 Reject Redemption
    // ═══════════════════════════════════════════════════════════════════

    // F-REJECT-1: Normal reject — shares returned
    function test_rejectRedemption_normal() public {
        _deposit(user1, 10e6);
        uint256 balBefore = fundToken.balanceOf(user1);

        uint256 reqId = _requestRedemption(user1, 5e18);
        assertEq(fundToken.balanceOf(user1), balBefore - 5e18);

        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        // Shares returned
        assertEq(fundToken.balanceOf(user1), balBefore);

        // Status = Rejected
        (,,,,, CoboFundToken.RedemptionStatus status) = fundToken.redemptions(reqId);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Rejected));
    }

    // F-REJECT-2: Reject after user removed from whitelist (bypass test)
    function test_rejectRedemption_bypassWhitelist() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        // Remove user from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // Reject should still work (bypass)
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
        assertEq(fundToken.balanceOf(user1), 10e18); // all shares returned
    }

    // F-REJECT-3: Reject reverts when paused (mintBypass respects pause)
    function test_rejectRedemption_revert_paused() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(admin);
        fundToken.pause();

        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.6 Force Redeem
    // ═══════════════════════════════════════════════════════════════════

    // F-FORCE-1: Normal force redeem
    function test_forceRedeem_normal() public {
        _deposit(user1, 10e6);

        uint256 balBefore = fundToken.balanceOf(user1);

        vm.prank(admin);
        fundToken.forceRedeem(user1, 5e18);

        assertEq(fundToken.balanceOf(user1), balBefore - 5e18);
    }

    // F-FORCE-2: Force redeem works when paused (bypass)
    function test_forceRedeem_whilePaused() public {
        _deposit(user1, 10e6);

        vm.prank(admin);
        fundToken.pause();

        vm.prank(admin);
        fundToken.forceRedeem(user1, 5e18);
        assertEq(fundToken.balanceOf(user1), 5e18);
    }

    // F-FORCE-3: Force redeem works when user is frozen (bypass)
    function test_forceRedeem_frozenUser() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(admin);
        fundToken.forceRedeem(user1, 5e18);
        assertEq(fundToken.balanceOf(user1), 5e18);
    }

    // F-FORCE-4: Non-admin reverts
    function test_forceRedeem_revert_notAdmin() public {
        _deposit(user1, 10e6);
        vm.prank(attacker);
        vm.expectRevert();
        fundToken.forceRedeem(user1, 5e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.7 Pause / Unpause
    // ═══════════════════════════════════════════════════════════════════

    // F-PAUSE-1: Guardian can pause
    function test_pause_byGuardian() public {
        vm.prank(emergencyGuardian);
        fundToken.pause();
        assertTrue(fundToken.paused());
    }

    // F-PAUSE-2: Admin can pause
    function test_pause_byAdmin() public {
        vm.prank(admin);
        fundToken.pause();
        assertTrue(fundToken.paused());
    }

    // F-PAUSE-3: Random user cannot pause
    function test_pause_revert_unauthorized() public {
        vm.prank(attacker);
        vm.expectRevert();
        fundToken.pause();
    }

    // F-PAUSE-4: Guardian cannot unpause (asymmetric)
    function test_unpause_revert_guardian() public {
        vm.prank(admin);
        fundToken.pause();

        vm.prank(emergencyGuardian);
        vm.expectRevert();
        fundToken.unpause();
    }

    // F-PAUSE-5: Admin can unpause
    function test_unpause_byAdmin() public {
        vm.prank(admin);
        fundToken.pause();

        vm.prank(admin);
        fundToken.unpause();
        assertFalse(fundToken.paused());
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.8 ERC20 transfer with whitelist/freeze
    // ═══════════════════════════════════════════════════════════════════

    // F-TRANSFER-1: Transfer between whitelisted users
    function test_transfer_normal() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        fundToken.transfer(user2, 3e18);
        assertEq(fundToken.balanceOf(user1), 7e18);
        assertEq(fundToken.balanceOf(user2), 3e18);
    }

    // F-TRANSFER-2: Transfer to non-whitelisted reverts
    function test_transfer_revert_receiverNotWhitelisted() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, attacker));
        fundToken.transfer(attacker, 3e18);
    }

    // F-TRANSFER-3: Transfer from frozen sender reverts
    function test_transfer_revert_senderFrozen() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.transfer(user2, 3e18);
    }

    // F-TRANSFER-4: Transfer when paused reverts
    function test_transfer_revert_paused() public {
        _deposit(user1, 10e6);

        vm.prank(admin);
        fundToken.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundToken.transfer(user2, 3e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.9 Configuration
    // ═══════════════════════════════════════════════════════════════════

    function test_setOracle() public {
        address newOracle = makeAddr("newOracle");
        vm.prank(admin);
        fundToken.setOracle(newOracle);
        assertEq(address(fundToken.oracle()), newOracle);
    }

    function test_setOracle_revert_zeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        fundToken.setOracle(address(0));
    }

    function test_setVault() public {
        address newVault = makeAddr("newVault");
        vm.prank(admin);
        fundToken.setVault(newVault);
        assertEq(fundToken.vault(), newVault);
    }

    function test_setMinDepositAmount() public {
        vm.prank(admin);
        fundToken.setMinDepositAmount(5e6);
        assertEq(fundToken.minDepositAmount(), 5e6);
    }

    function test_setMinRedeemShares() public {
        vm.prank(admin);
        fundToken.setMinRedeemShares(5e18);
        assertEq(fundToken.minRedeemShares(), 5e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.10 Whitelist & Freeze management
    // ═══════════════════════════════════════════════════════════════════

    function test_setWhitelist_managerOnly() public {
        address newUser = makeAddr("newUser");
        vm.prank(manager);
        fundToken.addToWhitelist(newUser);
        assertTrue(fundToken.whitelist(newUser));

        // Non-manager reverts
        vm.prank(attacker);
        vm.expectRevert();
        fundToken.removeFromWhitelist(newUser);
    }

    function test_removeFromWhitelist_blocklistAdminOnly() public {
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        assertFalse(fundToken.whitelist(user1));

        vm.prank(manager);
        fundToken.addToWhitelist(user1);
        assertTrue(fundToken.whitelist(user1));

        // Non-blocklist admin reverts
        vm.prank(attacker);
        vm.expectRevert();
        fundToken.removeFromWhitelist(user1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.11 Admin self-protection
    // ═══════════════════════════════════════════════════════════════════

    function test_fundToken_lastAdmin_protected() public {
        vm.prank(admin);
        vm.expectRevert(LibFundErrors.LastAdminCannotBeRevoked.selector);
        fundToken.revokeRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.12 Rescue ERC20
    // ═══════════════════════════════════════════════════════════════════

    function test_fundToken_rescueERC20_normal() public {
        MockERC20 randomToken = new MockERC20("R", "R", 18);
        randomToken.mint(address(fundToken), 100e18);

        vm.prank(admin);
        fundToken.rescueERC20(address(randomToken), admin, 100e18);
        assertEq(randomToken.balanceOf(admin), 100e18);
    }

    function test_fundToken_rescueERC20_xaut() public {
        // FundToken should not hold ASSET, but if it does, admin can rescue it
        asset.mint(address(fundToken), 100e6);
        vm.prank(admin);
        fundToken.rescueERC20(address(asset), admin, 100e6);
        assertEq(asset.balanceOf(admin), 100e6);
    }

    function test_fundToken_rescueERC20_xaue() public {
        // FundToken should not hold SHARE, but if it does, admin can rescue it
        uint256 shares = _deposit(user1, 10e6);

        // Whitelist fundToken and admin so transfer paths succeed
        vm.startPrank(admin);
        fundToken.addToWhitelist(address(fundToken));
        fundToken.addToWhitelist(admin);
        vm.stopPrank();

        vm.prank(user1);
        fundToken.transfer(address(fundToken), shares);

        uint256 adminBefore = fundToken.balanceOf(admin);
        vm.prank(admin);
        fundToken.rescueERC20(address(fundToken), admin, shares);
        assertEq(fundToken.balanceOf(admin), adminBefore + shares);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.13 Version
    // ═══════════════════════════════════════════════════════════════════

    function test_fundToken_version() public view {
        assertEq(fundToken.version(), 1);
    }

    // ╔═══════════════════════════════════════════════════════════════════╗
    // ║                ADDITIONAL TESTS (appended)                       ║
    // ╚═══════════════════════════════════════════════════════════════════╝

    // ═══════════════════════════════════════════════════════════════════
    // 2.1 initialize — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-INIT-3: admin=address(0) reverts
    function test_N_INIT_3_zeroAdmin() public {
        CoboFundToken impl = new CoboFundToken();
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                CoboFundToken.initialize,
                ("X", "X", 18, address(asset), address(oracle), address(vault), address(0), 1, 1)
            )
        );
    }

    /// @dev N-INIT-4: scale factors share=18, asset=6 → shareScale=1e18, assetScale=1e6
    function test_N_INIT_4_scaleFactor_18_6() public view {
        assertEq(fundToken.decimals(), 18);
        assertEq(fundToken.assetDecimals(), 6);
    }

    /// @dev N-INIT-5: scale factors share=6, asset=18 → shareScale=1e6, assetScale=1e18
    function test_N_INIT_5_scaleFactor_6_18() public {
        MockERC20 asset18 = new MockERC20("Asset18", "A18", 18);
        CoboFundToken impl = new CoboFundToken();
        CoboFundToken nav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 6, address(asset18), address(oracle), address(vault), admin, 1, 1)
                    )
                )
            )
        );
        assertEq(nav.decimals(), 6);
        assertEq(nav.assetDecimals(), 18);
    }

    /// @dev N-INIT-6: scale factors share=18, asset=18 → both 1e18
    function test_N_INIT_6_scaleFactor_18_18() public {
        MockERC20 asset18 = new MockERC20("Asset18", "A18", 18);
        CoboFundToken impl = new CoboFundToken();
        CoboFundToken nav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 18, address(asset18), address(oracle), address(vault), admin, 1, 1)
                    )
                )
            )
        );
        assertEq(nav.decimals(), 18);
        assertEq(nav.assetDecimals(), 18);
    }

    /// @dev N-INIT-7: scale factors share=8, asset=6 → shareScale=1e8, assetScale=1e6
    function test_N_INIT_7_scaleFactor_8_6() public {
        CoboFundToken impl = new CoboFundToken();
        CoboFundToken nav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 8, address(asset), address(oracle), address(vault), admin, 1, 1)
                    )
                )
            )
        );
        assertEq(nav.decimals(), 8);
        assertEq(nav.assetDecimals(), 6);
    }

    /// @dev N-INIT-8: minDepositAmount=0 succeeds
    function test_N_INIT_8_minDeposit_zero() public {
        CoboFundToken impl = new CoboFundToken();
        CoboFundToken nav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 18, address(asset), address(oracle), address(vault), admin, 0, 1e18)
                    )
                )
            )
        );
        assertEq(nav.minDepositAmount(), 0);
    }

    /// @dev N-INIT-9: minRedeemShares=0 succeeds
    function test_N_INIT_9_minRedeem_zero() public {
        CoboFundToken impl = new CoboFundToken();
        CoboFundToken nav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 18, address(asset), address(oracle), address(vault), admin, 1e6, 0)
                    )
                )
            )
        );
        assertEq(nav.minRedeemShares(), 0);
    }

    /// @dev N-INIT-11: oracle=address(0) reverts
    function test_N_INIT_11_zeroOracle() public {
        CoboFundToken impl = new CoboFundToken();
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                CoboFundToken.initialize, ("X", "X", 18, address(asset), address(0), address(vault), admin, 1, 1)
            )
        );
    }

    /// @dev N-INIT-12: vault=address(0) reverts
    function test_N_INIT_12_zeroVault() public {
        CoboFundToken impl = new CoboFundToken();
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                CoboFundToken.initialize, ("X", "X", 18, address(asset), address(oracle), address(0), admin, 1, 1)
            )
        );
    }

    /// @dev N-INIT-13: share decimals=0, asset=6 → offset=10^6, gte=false
    function test_N_INIT_13_shareDecimals_zero() public {
        CoboFundToken impl = new CoboFundToken();
        CoboFundToken nav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 0, address(asset), address(oracle), address(vault), admin, 1, 1)
                    )
                )
            )
        );
        assertEq(nav.decimals(), 0);
        assertEq(nav.assetDecimals(), 6);
    }

    /// @dev N-INIT-14: share=0, asset=0 → offset=1
    function test_N_INIT_14_bothDecimals_zero() public {
        MockERC20 asset0 = new MockERC20("Asset0", "A0", 0);
        CoboFundToken impl = new CoboFundToken();
        CoboFundToken nav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 0, address(asset0), address(oracle), address(vault), admin, 1, 1)
                    )
                )
            )
        );
        assertEq(nav.decimals(), 0);
        assertEq(nav.assetDecimals(), 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.2 mint — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-MNT-4: Transfer event emitted from address(0) to user (mint)
    function test_N_MNT_4_transferEvent() public {
        // At NAV=1e18, 10 ASSET → 10 SHARE
        uint256 expectedShares = 10e18;

        vm.expectEmit(true, true, true, true, address(fundToken));
        emit IERC20.Transfer(address(0), user1, expectedShares);

        _deposit(user1, 10e6);
    }

    /// @dev N-MNT-8: not whitelisted + frozen → revert "not whitelisted" (checked first)
    function test_N_MNT_8_notWhitelisted_and_frozen() public {
        asset.mint(attacker, 100e6);
        vm.prank(attacker);
        asset.approve(address(fundToken), type(uint256).max);

        // attacker is not whitelisted. Also freeze them.
        vm.prank(manager);
        fundToken.addToWhitelist(attacker);
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(attacker);
        // Now remove from whitelist
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(attacker);

        // mint should revert with "not whitelisted" first
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, attacker));
        fundToken.mint(10e6);
    }

    /// @dev N-MNT-11: exactly min deposit boundary succeeds
    function test_N_MNT_11_exactlyMinDeposit() public {
        // minDepositAmount = 1e6 (1 ASSET)
        uint256 shares = _deposit(user1, 1e6);
        assertGt(shares, 0);
        assertEq(fundToken.balanceOf(user1), shares);
    }

    /// @dev N-MNT-12: NAV=0 reverts with ZeroNetValue
    function test_N_MNT_12_zeroNAV() public {
        // Deploy a mock oracle that returns 0
        MockZeroOracle zeroOracle = new MockZeroOracle();
        vm.prank(admin);
        fundToken.setOracle(address(zeroOracle));

        vm.prank(user1);
        vm.expectRevert(LibFundErrors.ZeroNetValue.selector);
        fundToken.mint(10e6);
    }

    /// @dev N-MNT-13: zero shares revert (tiny amount with huge NAV)
    function test_N_MNT_13_zeroSharesRevert() public {
        // Set minDeposit to 0 to allow tiny amounts through
        vm.prank(admin);
        fundToken.setMinDepositAmount(0);

        // Deploy a high-NAV oracle
        MockHighNavOracle highOracle = new MockHighNavOracle();
        vm.prank(admin);
        fundToken.setOracle(address(highOracle));

        // With NAV = type(uint128).max, 1 wei of ASSET yields 0 shares due to rounding
        vm.prank(user1);
        vm.expectRevert(LibFundErrors.ZeroShares.selector);
        fundToken.mint(1);
    }

    /// @dev N-MNT-14: insufficient ASSET allowance reverts
    function test_N_MNT_14_insufficientAllowance() public {
        address tempUser = makeAddr("tempUser");
        asset.mint(tempUser, 100e6);
        vm.prank(manager);
        fundToken.addToWhitelist(tempUser);

        // Only approve 5e6 but try to mint 10e6
        vm.prank(tempUser);
        asset.approve(address(fundToken), 5e6);

        vm.prank(tempUser);
        vm.expectRevert(); // ERC20 transferFrom fails
        fundToken.mint(10e6);
    }

    /// @dev N-MNT-15: insufficient ASSET balance reverts
    function test_N_MNT_15_insufficientBalance() public {
        address tempUser = makeAddr("tempUser");
        asset.mint(tempUser, 5e6); // only 5 ASSET
        vm.prank(manager);
        fundToken.addToWhitelist(tempUser);

        vm.prank(tempUser);
        asset.approve(address(fundToken), type(uint256).max);

        vm.prank(tempUser);
        vm.expectRevert(); // ERC20 transferFrom fails (insufficient balance)
        fundToken.mint(10e6);
    }

    /// @dev N-MNT-16: amount=0 → revert BelowMinDeposit
    function test_N_MNT_16_amountZero_belowMin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.BelowMinDeposit.selector, 0, MIN_DEPOSIT_AMOUNT));
        fundToken.mint(0);
    }

    /// @dev N-MNT-17: minDepositAmount=0, mint(0) → revert ZeroShares
    function test_N_MNT_17_minDepositZero_mintZero() public {
        vm.prank(admin);
        fundToken.setMinDepositAmount(0);

        // 0 ASSET → 0 shares → revert ZeroShares
        vm.prank(user1);
        vm.expectRevert(LibFundErrors.ZeroShares.selector);
        fundToken.mint(0);
    }

    /// @dev N-MNT-18: share calculation 6/18 NAV=1e18: 100e6 → 100e18
    function test_N_MNT_18_shareCalc_nav1() public {
        uint256 shares = _deposit(user1, 100e6);
        // 100e6 * 1e12 * 1e18 / 1e18 = 100e18
        assertEq(shares, 100e18);
    }

    /// @dev N-MNT-19: share calculation 6/18 NAV=2e18: 100e6 → 50e18
    function test_N_MNT_19_shareCalc_nav2() public {
        // Advance time so NAV roughly doubles — or use a mock oracle
        MockFixedOracle fixedOracle = new MockFixedOracle(2e18);
        vm.prank(admin);
        fundToken.setOracle(address(fixedOracle));

        uint256 shares = _deposit(user1, 100e6);
        // 100e6 * 1e12 * 1e18 / 2e18 = 50e18
        assertEq(shares, 50e18);
    }

    /// @dev N-MNT-20: share calculation 6/18 NAV=1000e18: 100e6 → 1e17
    function test_N_MNT_20_shareCalc_nav1000() public {
        MockFixedOracle fixedOracle = new MockFixedOracle(1000e18);
        vm.prank(admin);
        fundToken.setOracle(address(fixedOracle));

        uint256 shares = _deposit(user1, 100e6);
        // 100e6 * 1e12 * 1e18 / 1000e18 = 1e17
        assertEq(shares, 1e17);
    }

    /// @dev N-MNT-21: share calculation 6/18 NAV=1.05e18: 100e6 → ~95.238e18
    function test_N_MNT_21_shareCalc_nav105() public {
        vm.warp(block.timestamp + 365 days); // APR 5% → NAV = 1.05e18

        uint256 shares = _deposit(user1, 100e6);
        uint256 expected = (uint256(100e6) * uint256(1e12) * uint256(1e18)) / uint256(1.05e18);
        assertEq(shares, expected);
    }

    /// @dev N-MNT-25: share calculation 6/18 NAV=1e18, 1 wei → 1e12 shares
    function test_N_MNT_25_shareCalc_minUnit() public {
        vm.prank(admin);
        fundToken.setMinDepositAmount(0);

        uint256 shares = _deposit(user1, 1);
        // 1 * 1e12 * 1e18 / 1e18 = 1e12
        assertEq(shares, 1e12);
    }

    /// @dev N-MNT-26: mint return value equals user balance increase
    function test_N_MNT_26_returnValue() public {
        uint256 balBefore = fundToken.balanceOf(user1);
        uint256 shares = _deposit(user1, 10e6);
        uint256 balAfter = fundToken.balanceOf(user1);
        assertEq(shares, balAfter - balBefore);
    }

    /// @dev N-MNT-27: vault set to address with no ASSET balance / transfer issue
    ///      We test that the entire tx reverts if the ASSET transfer to vault fails.
    ///      Here we simulate by making the vault a contract that causes transfer to fail
    ///      using a FailingERC20 token.
    function test_N_MNT_27_vaultTransferFails() public {
        // Deploy a FailingERC20 that reverts on transfer
        FailingERC20 failToken = new FailingERC20();
        failToken.mint(user1, 1000e6);

        // Deploy a fresh fundToken with failToken as asset
        CoboFundToken freshImpl = new CoboFundToken();
        uint64 nonce = vm.getNonce(address(this));
        address predictedVault2 = vm.computeCreateAddress(address(this), nonce + 1);

        CoboFundToken freshNav = CoboFundToken(
            address(
                new ERC1967Proxy(
                    address(freshImpl),
                    abi.encodeCall(
                        CoboFundToken.initialize,
                        ("T", "T", 18, address(failToken), address(oracle), predictedVault2, admin, 1e6, 1e18)
                    )
                )
            )
        );

        CoboFundVault freshVault = CoboFundVault(
            address(
                new ERC1967Proxy(
                    address(vaultImpl),
                    abi.encodeCall(CoboFundVault.initialize, (address(failToken), address(freshNav), admin))
                )
            )
        );

        assertEq(address(freshVault), predictedVault2);

        vm.startPrank(admin);
        freshNav.grantRole(MANAGER_ROLE, admin);
        freshNav.addToWhitelist(user1);
        vm.stopPrank();

        vm.prank(user1);
        failToken.approve(address(freshNav), type(uint256).max);

        // Enable the fail flag
        failToken.setFailTransfer(true);

        vm.prank(user1);
        vm.expectRevert("transfer failed");
        freshNav.mint(10e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.3 requestRedemption — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-REQ-2: shares immediately burned
    function test_N_REQ_2_sharesBurned() public {
        _deposit(user1, 10e6); // 10 SHARE
        uint256 totalBefore = fundToken.totalSupply();
        uint256 balBefore = fundToken.balanceOf(user1);

        _requestRedemption(user1, 5e18);

        assertEq(fundToken.balanceOf(user1), balBefore - 5e18);
        assertEq(fundToken.totalSupply(), totalBefore - 5e18);
    }

    /// @dev N-REQ-3: request record completeness
    function test_N_REQ_3_requestRecord() public {
        _deposit(user1, 10e6);

        uint256 ts = block.timestamp;
        uint256 reqId = _requestRedemption(user1, 5e18);

        (
            uint256 id,
            address ruser,
            uint256 assetAmt,
            uint256 shareAmt,
            uint256 requestedAt,
            CoboFundToken.RedemptionStatus status
        ) = fundToken.redemptions(reqId);

        assertEq(id, 0);
        assertEq(ruser, user1);
        assertEq(shareAmt, 5e18);
        assertEq(requestedAt, ts);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Pending));
        // assetAmount = 5e18 * 1e18 / (1e12 * 1e18) = 5e6
        assertEq(assetAmt, 5e6);
    }

    /// @dev N-REQ-4: RedemptionRequested event emitted
    function test_N_REQ_4_event() public {
        _deposit(user1, 10e6);

        // Expected assetAmt at NAV=1e18: 5e18 * 1e18 / (1e12 * 1e18) = 5e6
        uint256 expectedXaut = 5e6;
        uint256 expectedXaue = 5e18;

        vm.expectEmit(true, true, false, true, address(fundToken));
        emit CoboFundToken.RedemptionRequested(0, user1, expectedXaut, expectedXaue, block.timestamp, user1);

        _requestRedemption(user1, 5e18);
    }

    /// @dev N-REQ-5: reqId increments
    function test_N_REQ_5_reqIdIncrements() public {
        _deposit(user1, 100e6);

        uint256 r0 = _requestRedemption(user1, 10e18);
        uint256 r1 = _requestRedemption(user1, 10e18);
        uint256 r2 = _requestRedemption(user1, 10e18);

        assertEq(r0, 0);
        assertEq(r1, 1);
        assertEq(r2, 2);
        assertEq(fundToken.redemptionCount(), 3);
    }

    /// @dev N-REQ-7: frozen user reverts
    function test_N_REQ_7_frozenRevert() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.requestRedemption(5e18);
    }

    /// @dev N-REQ-8: paused reverts
    function test_N_REQ_8_pausedRevert() public {
        _deposit(user1, 10e6);

        vm.prank(admin);
        fundToken.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundToken.requestRedemption(5e18);
    }

    /// @dev N-REQ-10: exactly min redeem shares boundary succeeds
    function test_N_REQ_10_exactlyMinRedeem() public {
        _deposit(user1, 10e6);

        // minRedeemShares = 1e18
        uint256 reqId = _requestRedemption(user1, 1e18);
        (,,,,, CoboFundToken.RedemptionStatus status) = fundToken.redemptions(reqId);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Pending));
    }

    /// @dev N-REQ-11: insufficient balance reverts
    function test_N_REQ_11_insufficientBalance() public {
        _deposit(user1, 10e6); // 10 SHARE

        vm.prank(user1);
        vm.expectRevert(); // ERC20 _burn insufficient balance
        fundToken.requestRedemption(50e18);
    }

    /// @dev N-REQ-12: redeem all balance
    function test_N_REQ_12_redeemAll() public {
        _deposit(user1, 100e6); // 100 SHARE

        _requestRedemption(user1, 100e18);
        assertEq(fundToken.balanceOf(user1), 0);
    }

    /// @dev N-REQ-13: multiple redemption requests from same user
    function test_N_REQ_13_multipleRequests() public {
        _deposit(user1, 100e6); // 100 SHARE

        uint256 r0 = _requestRedemption(user1, 30e18);
        uint256 r1 = _requestRedemption(user1, 30e18);

        assertEq(r0, 0);
        assertEq(r1, 1);
        assertEq(fundToken.balanceOf(user1), 40e18);

        // Both should be Pending
        (,,,,, CoboFundToken.RedemptionStatus s0) = fundToken.redemptions(r0);
        (,,,,, CoboFundToken.RedemptionStatus s1) = fundToken.redemptions(r1);
        assertEq(uint8(s0), uint8(CoboFundToken.RedemptionStatus.Pending));
        assertEq(uint8(s1), uint8(CoboFundToken.RedemptionStatus.Pending));
    }

    /// @dev N-REQ-14: insufficient balance after partial redemption
    function test_N_REQ_14_insufficientAfterPartial() public {
        _deposit(user1, 100e6); // 100 SHARE

        _requestRedemption(user1, 80e18); // 20 left
        assertEq(fundToken.balanceOf(user1), 20e18);

        vm.prank(user1);
        vm.expectRevert(); // only 20 left, try 30
        fundToken.requestRedemption(30e18);
    }

    /// @dev N-REQ-15: asset amount calculation at NAV=1e18
    function test_N_REQ_15_xautCalc_nav1() public {
        _deposit(user1, 100e6);

        uint256 reqId = _requestRedemption(user1, 100e18);
        (,, uint256 assetAmt,,,) = fundToken.redemptions(reqId);
        // 100e18 * 1e18 / (1e12 * 1e18) = 100e6
        assertEq(assetAmt, 100e6);
    }

    /// @dev N-REQ-16: asset amount calculation at NAV=1.05e18
    function test_N_REQ_16_xautCalc_nav105() public {
        _deposit(user1, 100e6);

        vm.warp(block.timestamp + 365 days); // APR 5% → NAV ~ 1.05e18

        uint256 reqId = _requestRedemption(user1, 100e18);
        (,, uint256 assetAmt,,,) = fundToken.redemptions(reqId);
        // 100e18 * 1.05e18 / (1e12 * 1e18) = 105e6
        uint256 navNow = oracle.getLatestPrice();
        uint256 expected = (uint256(100e18) * navNow) / (uint256(1e12) * uint256(1e18));
        assertEq(assetAmt, expected);
    }

    /// @dev N-REQ-17: asset amount calculation at NAV=1000e18
    function test_N_REQ_17_xautCalc_nav1000() public {
        MockFixedOracle fixedOracle = new MockFixedOracle(1000e18);
        vm.prank(admin);
        fundToken.setOracle(address(fixedOracle));

        // Lower min redeem so we can redeem the small share amount
        vm.prank(admin);
        fundToken.setMinRedeemShares(0);

        // First mint to get shares
        uint256 shares = _deposit(user1, 100e6);
        // 100e6 * 1e12 * 1e18 / 1000e18 = 1e17
        assertEq(shares, 1e17);

        uint256 reqId = _requestRedemption(user1, shares);
        (,, uint256 assetAmt,,,) = fundToken.redemptions(reqId);
        // shares * 1000e18 / (1e12 * 1e18) = 1e17 * 1000e18 / 1e30 = 100e6
        assertEq(assetAmt, 100e6);
    }

    /// @dev N-REQ-20: assetAmount=0 edge case reverts ZeroAssetAmount
    function test_N_REQ_20_zeroXautAmount() public {
        // Strategy: mint shares with a low NAV, then switch to a high NAV for redemption.
        // With high NAV at redemption time, assetAmount = shares * nav / (1e12 * 1e18)
        // We need a small number of shares and moderate nav so that the product rounds to 0.
        // Actually simpler: use nav=1 (1 wei). Then assetAmt = shares * 1 / (1e12 * 1e18) = shares / 1e30.
        // So if shares < 1e30, assetAmt rounds to 0.

        // Set min thresholds to 0 to bypass boundary checks
        vm.prank(admin);
        fundToken.setMinDepositAmount(0);
        vm.prank(admin);
        fundToken.setMinRedeemShares(0);

        // Mint shares at NAV=1e18 (normal)
        _deposit(user1, 10e6); // 10 SHARE = 10e18 shares

        // Now switch oracle to NAV=1 (1 wei)
        MockFixedOracle tinyOracle = new MockFixedOracle(1);
        vm.prank(admin);
        fundToken.setOracle(address(tinyOracle));

        // Redeem 1 share: assetAmt = 1 * 1 / (1e12 * 1e18) = 0
        vm.prank(user1);
        vm.expectRevert(LibFundErrors.ZeroAssetAmount.selector);
        fundToken.requestRedemption(1);
    }

    /// @dev N-REQ-21: return value
    function test_N_REQ_21_returnValue() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(5e18);
        assertEq(reqId, 0);

        // Verify the returned reqId matches stored
        (uint256 id,,,,,) = fundToken.redemptions(reqId);
        assertEq(id, reqId);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.4 approveRedemption — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-APR-2: ASSET flows from Vault to user on approval
    function test_N_APR_2_xautFlow() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        uint256 vaultBefore = asset.balanceOf(address(vault));
        uint256 userBefore = asset.balanceOf(user1);

        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        assertEq(asset.balanceOf(address(vault)), vaultBefore - assetAmt);
        assertEq(asset.balanceOf(user1), userBefore + assetAmt);
    }

    /// @dev N-APR-3: RedemptionExecuted event emitted
    function test_N_APR_3_event() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.expectEmit(true, true, false, true, address(fundToken));
        emit CoboFundToken.RedemptionExecuted(reqId, user1, assetAmt, shareAmt, block.timestamp, redemptionApprover);

        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-APR-7: already rejected request → revert "not pending"
    function test_N_APR_7_alreadyRejected() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        // Reject first
        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        // Try approve
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId));
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-APR-9: user param mismatch
    function test_N_APR_9_userMismatch() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionParamMismatch.selector, reqId));
        fundToken.approveRedemption(reqId, user2, assetAmt, shareAmt);
    }

    /// @dev N-APR-10: assetAmount mismatch
    function test_N_APR_10_xautMismatch() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionParamMismatch.selector, reqId));
        fundToken.approveRedemption(reqId, user1, assetAmt + 1, shareAmt);
    }

    /// @dev N-APR-11: shareAmount mismatch
    function test_N_APR_11_xaueMismatch() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionParamMismatch.selector, reqId));
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt + 1);
    }

    /// @dev N-APR-12: Vault insufficient ASSET
    function test_N_APR_12_vaultInsufficient() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        // Drain vault via settlement
        uint256 vaultBal = asset.balanceOf(address(vault));
        vm.prank(admin);
        vault.setWhitelist(admin, true);
        vm.prank(settlementOperator);
        vault.withdraw(admin, vaultBal);

        vm.prank(redemptionApprover);
        vm.expectRevert(); // transferFrom from vault fails
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-APR-14: nonexistent reqId with non-zero params → revert "user mismatch" (or invalid request)
    function test_N_APR_14_nonExistentReqId_nonZeroParams() public {
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.InvalidRedemptionRequest.selector, 999));
        fundToken.approveRedemption(999, user1, 100, 100);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.5 rejectRedemption — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-REJ-2: shares returned after reject
    function test_N_REJ_2_sharesReturned() public {
        _deposit(user1, 10e6); // 10 SHARE
        uint256 balBefore = fundToken.balanceOf(user1);
        uint256 supplyBefore = fundToken.totalSupply();

        uint256 reqId = _requestRedemption(user1, 5e18);
        assertEq(fundToken.balanceOf(user1), balBefore - 5e18);
        assertEq(fundToken.totalSupply(), supplyBefore - 5e18);

        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        // Shares restored
        assertEq(fundToken.balanceOf(user1), balBefore);
        assertEq(fundToken.totalSupply(), supplyBefore);
    }

    /// @dev N-REJ-3: RedemptionRejected event emitted
    function test_N_REJ_3_event() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.expectEmit(true, true, false, true, address(fundToken));
        emit CoboFundToken.RedemptionRejected(reqId, user1, assetAmt, shareAmt, block.timestamp, redemptionApprover);

        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-REJ-5: non-approver reverts
    function test_N_REJ_5_notApprover() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(attacker);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-REJ-6: reject already executed request → revert "not pending"
    function test_N_REJ_6_notPending() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        // Execute first
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmt, shareAmt);

        // Try reject
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId));
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-REJ-7: user param mismatch
    function test_N_REJ_7_userMismatch() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionParamMismatch.selector, reqId));
        fundToken.rejectRedemption(reqId, user2, assetAmt, shareAmt);
    }

    /// @dev N-REJ-8: assetAmount mismatch
    function test_N_REJ_8_xautMismatch() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionParamMismatch.selector, reqId));
        fundToken.rejectRedemption(reqId, user1, assetAmt + 1, shareAmt);
    }

    /// @dev N-REJ-9: shareAmount mismatch
    function test_N_REJ_9_xaueMismatch() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionParamMismatch.selector, reqId));
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt + 1);
    }

    /// @dev N-REJ-10: nonexistent reqId (all-zero params) → revert "invalid request"
    function test_N_REJ_10_nonExistentReqId() public {
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.InvalidRedemptionRequest.selector, 999));
        fundToken.rejectRedemption(999, address(0), 0, 0);
    }

    /// @dev N-REJ-C1: normal path — whitelisted, not frozen, not paused → success
    function test_N_REJ_C1_normalPath() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        (,,,,, CoboFundToken.RedemptionStatus status) = fundToken.redemptions(reqId);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Rejected));
        assertEq(fundToken.balanceOf(user1), 10e18);
    }

    /// @dev N-REJ-C3: whitelisted + frozen → success (bypass frozen)
    function test_N_REJ_C3_whitelisted_frozen() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        // Freeze user
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        assertEq(fundToken.balanceOf(user1), 10e18);
    }

    /// @dev N-REJ-C4: removed + frozen → success (bypass both)
    function test_N_REJ_C4_removed_frozen() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        // Remove + freeze
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);

        assertEq(fundToken.balanceOf(user1), 10e18);
    }

    /// @dev N-REJ-C5: whitelisted + not frozen + paused → revert "paused"
    function test_N_REJ_C5_paused() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(admin);
        fundToken.pause();

        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-REJ-C6: removed + frozen + paused → revert "paused"
    function test_N_REJ_C6_removed_frozen_paused() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        vm.prank(admin);
        fundToken.pause();

        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-REJ-C7: removed + not frozen + paused → revert "paused"
    function test_N_REJ_C7_removed_paused() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        vm.prank(admin);
        fundToken.pause();

        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    /// @dev N-REJ-C8: whitelisted + frozen + paused → revert "paused"
    function test_N_REJ_C8_whitelisted_frozen_paused() public {
        _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, 5e18);
        (,, uint256 assetAmt, uint256 shareAmt,,) = fundToken.redemptions(reqId);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        vm.prank(admin);
        fundToken.pause();

        vm.prank(redemptionApprover);
        vm.expectRevert();
        fundToken.rejectRedemption(reqId, user1, assetAmt, shareAmt);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.6 forceRedeem — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-FR-3: not whitelisted, not frozen, not paused → success (_burnBypass)
    function test_N_FR_3_notWhitelisted() public {
        _deposit(user1, 10e6);
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(admin);
        fundToken.forceRedeem(user1, 5e18);
        assertEq(fundToken.balanceOf(user1), 5e18);
    }

    /// @dev N-FR-7: not whitelisted + paused → success
    function test_N_FR_7_notWhitelisted_paused() public {
        _deposit(user1, 10e6);
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        vm.prank(admin);
        fundToken.pause();

        vm.prank(admin);
        fundToken.forceRedeem(user1, 5e18);
        assertEq(fundToken.balanceOf(user1), 5e18);
    }

    /// @dev N-FR-10: user balance=0 → revert
    function test_N_FR_10_zeroBalance() public {
        // user3 has no shares
        vm.prank(admin);
        vm.expectRevert(LibFundErrors.ZeroAmount.selector);
        fundToken.forceRedeem(user3, 0);
    }

    /// @dev N-FR-10b: user has 0 shares but forceRedeem non-zero → revert ERC20 burn
    function test_N_FR_10b_insufficientShares() public {
        vm.prank(admin);
        vm.expectRevert(); // ERC20 _burn underflow
        fundToken.forceRedeem(user3, 100e18);
    }

    /// @dev N-FR-11: partial force redeem
    function test_N_FR_11_partial() public {
        _deposit(user1, 100e6); // 100 SHARE
        vm.prank(admin);
        fundToken.forceRedeem(user1, 60e18);
        assertEq(fundToken.balanceOf(user1), 40e18);
    }

    /// @dev N-FR-12: full force redeem
    function test_N_FR_12_full() public {
        _deposit(user1, 100e6); // 100 SHARE
        vm.prank(admin);
        fundToken.forceRedeem(user1, 100e18);
        assertEq(fundToken.balanceOf(user1), 0);
    }

    /// @dev N-FR-13: ForceRedeemed event emitted
    function test_N_FR_13_event() public {
        _deposit(user1, 10e6);

        uint256 nav = oracle.getLatestPrice();
        vm.expectEmit(true, false, false, true, address(fundToken));
        emit CoboFundToken.ForceRedeemed(user1, 5e18, nav);

        vm.prank(admin);
        fundToken.forceRedeem(user1, 5e18);
    }

    /// @dev N-FR-14: totalSupply decreases
    function test_N_FR_14_totalSupplyDecrease() public {
        _deposit(user1, 100e6);
        uint256 supplyBefore = fundToken.totalSupply();

        vm.prank(admin);
        fundToken.forceRedeem(user1, 60e18);

        assertEq(fundToken.totalSupply(), supplyBefore - 60e18);
    }

    /// @dev N-FR-15: Transfer event (burn) emitted
    function test_N_FR_15_transferEvent() public {
        _deposit(user1, 10e6);

        vm.expectEmit(true, true, true, true, address(fundToken));
        emit IERC20.Transfer(user1, address(0), 5e18);

        vm.prank(admin);
        fundToken.forceRedeem(user1, 5e18);
    }

    /// @dev N-FR-16: forceRedeem exceeds balance → burns available balance (auto-adjusts)
    function test_N_FR_16_exceedsBalance() public {
        _deposit(user1, 10e6); // 10 SHARE

        vm.prank(admin);
        fundToken.forceRedeem(user1, 11e18); // Request 11, burns available 10

        assertEq(fundToken.balanceOf(user1), 0); // All balance burned
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.7 ERC20 — additional transfer/transferFrom/approve cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-TF-4: sender whitelisted, receiver NOT whitelisted → revert "receiver not whitelisted"
    function test_N_TF_4_receiverNotWhitelisted() public {
        _deposit(user1, 10e6);

        // user4 is not whitelisted
        address user4 = makeAddr("user4");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user4));
        fundToken.transfer(user4, 3e18);
    }

    /// @dev N-TF-5: receiver frozen → revert "receiver frozen"
    function test_N_TF_5_receiverFrozen() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user2);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user2));
        fundToken.transfer(user2, 3e18);
    }

    /// @dev N-TF-7: sender frozen + receiver not whitelisted → revert "sender frozen" (frozen checked first)
    function test_N_TF_7_senderFrozen_receiverNotWL() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        address notWL = makeAddr("notWL");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.transfer(notWL, 3e18);
    }

    /// @dev N-TF-8: paused + both bad → revert "paused" (whenNotPaused first)
    function test_N_TF_8_paused_overrides_all() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);
        vm.prank(admin);
        fundToken.pause();

        vm.prank(user1);
        vm.expectRevert(); // EnforcedPause
        fundToken.transfer(user2, 3e18);
    }

    /// @dev N-TF-9: insufficient balance
    function test_N_TF_9_insufficientBalance() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        vm.expectRevert(); // ERC20 insufficient balance
        fundToken.transfer(user2, 100e18);
    }

    /// @dev N-TF-10: zero amount transfer succeeds
    function test_N_TF_10_zeroAmount() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        fundToken.transfer(user2, 0);
        assertEq(fundToken.balanceOf(user1), 10e18);
        assertEq(fundToken.balanceOf(user2), 0);
    }

    /// @dev N-TF-11: self transfer succeeds
    function test_N_TF_11_selfTransfer() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        fundToken.transfer(user1, 5e18);
        assertEq(fundToken.balanceOf(user1), 10e18);
    }

    /// @dev N-TFF-1: normal transferFrom with sufficient allowance
    function test_N_TFF_1_normal() public {
        _deposit(user1, 10e6);

        // user1 approves user2
        vm.prank(user1);
        fundToken.approve(user2, 5e18);

        vm.prank(user2);
        fundToken.transferFrom(user1, user2, 3e18);
        assertEq(fundToken.balanceOf(user1), 7e18);
        assertEq(fundToken.balanceOf(user2), 3e18);
    }

    /// @dev N-TFF-2: insufficient allowance reverts
    function test_N_TFF_2_insufficientAllowance() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        fundToken.approve(user2, 1e18);

        vm.prank(user2);
        vm.expectRevert(); // ERC20 insufficient allowance
        fundToken.transferFrom(user1, user2, 5e18);
    }

    /// @dev N-TFF-3: unlimited allowance (type(uint256).max) not deducted
    function test_N_TFF_3_unlimitedAllowance() public {
        _deposit(user1, 10e6);

        vm.prank(user1);
        fundToken.approve(user2, type(uint256).max);

        vm.prank(user2);
        fundToken.transferFrom(user1, user2, 3e18);

        assertEq(fundToken.allowance(user1, user2), type(uint256).max);
    }

    /// @dev N-TFF-4: sender (from) not whitelisted → revert
    function test_N_TFF_4_senderNotWhitelisted() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        vm.prank(user1);
        fundToken.approve(user2, 10e18);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.transferFrom(user1, user2, 3e18);
    }

    /// @dev N-TFF-5: receiver frozen → revert
    function test_N_TFF_5_receiverFrozen() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user2);

        vm.prank(user1);
        fundToken.approve(user3, 10e18);

        vm.prank(user3);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user2));
        fundToken.transferFrom(user1, user2, 3e18);
    }

    /// @dev N-TFF-6: from=caller (self approve + transferFrom)
    function test_N_TFF_6_fromIsCaller() public {
        _deposit(user1, 10e6);

        // user1 approves self and calls transferFrom to user2
        vm.prank(user1);
        fundToken.approve(user1, 10e18);

        vm.prank(user1);
        fundToken.transferFrom(user1, user2, 3e18);
        assertEq(fundToken.balanceOf(user1), 7e18);
        assertEq(fundToken.balanceOf(user2), 3e18);
    }

    /// @dev N-APV-1: normal approve
    function test_N_APV_1_normalApprove() public {
        vm.expectEmit(true, true, false, true, address(fundToken));
        emit IERC20.Approval(user1, user2, 5e18);

        vm.prank(user1);
        fundToken.approve(user2, 5e18);
        assertEq(fundToken.allowance(user1, user2), 5e18);
    }

    /// @dev N-APV-2: overwrite existing approve
    function test_N_APV_2_overwrite() public {
        vm.prank(user1);
        fundToken.approve(user2, 5e18);

        vm.prank(user1);
        fundToken.approve(user2, 10e18);
        assertEq(fundToken.allowance(user1, user2), 10e18);
    }

    /// @dev N-APV-3: approve to 0 (cancel)
    function test_N_APV_3_approveZero() public {
        vm.prank(user1);
        fundToken.approve(user2, 5e18);

        vm.prank(user1);
        fundToken.approve(user2, 0);
        assertEq(fundToken.allowance(user1, user2), 0);
    }

    /// @dev N-APV-4: approve type(uint256).max
    function test_N_APV_4_approveMax() public {
        vm.prank(user1);
        fundToken.approve(user2, type(uint256).max);
        assertEq(fundToken.allowance(user1, user2), type(uint256).max);
    }

    /// @dev N-APV-5: approve works even when paused
    function test_N_APV_5_approveWhilePaused() public {
        vm.prank(admin);
        fundToken.pause();

        vm.prank(user1);
        fundToken.approve(user2, 5e18);
        assertEq(fundToken.allowance(user1, user2), 5e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.8 Pause — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-PS-5: double pause reverts EnforcedPause
    function test_N_PS_5_doublePause() public {
        vm.prank(admin);
        fundToken.pause();

        vm.prank(admin);
        vm.expectRevert(); // EnforcedPause
        fundToken.pause();
    }

    /// @dev N-PS-6: double unpause reverts ExpectedPause
    function test_N_PS_6_doubleUnpause() public {
        // Already unpaused
        vm.prank(admin);
        vm.expectRevert(); // ExpectedPause
        fundToken.unpause();
    }

    /// @dev N-PS-7: guardian can pause but NOT unpause (asymmetric)
    function test_N_PS_7_guardianAsymmetric() public {
        // Guardian pauses
        vm.prank(emergencyGuardian);
        fundToken.pause();
        assertTrue(fundToken.paused());

        // Guardian cannot unpause
        vm.prank(emergencyGuardian);
        vm.expectRevert();
        fundToken.unpause();

        // Admin unpauses
        vm.prank(admin);
        fundToken.unpause();
        assertFalse(fundToken.paused());
    }

    /// @dev N-PS-8: guardian cannot do other admin operations (setOracle, forceRedeem, etc.)
    function test_N_PS_8_guardianCannotAdmin() public {
        // Guardian cannot setOracle
        vm.prank(emergencyGuardian);
        vm.expectRevert();
        fundToken.setOracle(address(1));

        // Guardian cannot forceRedeem
        _deposit(user1, 10e6);
        vm.prank(emergencyGuardian);
        vm.expectRevert();
        fundToken.forceRedeem(user1, 5e18);

        // Guardian cannot setVault
        vm.prank(emergencyGuardian);
        vm.expectRevert();
        fundToken.setVault(address(1));

        // Guardian cannot setMinDepositAmount
        vm.prank(emergencyGuardian);
        vm.expectRevert();
        fundToken.setMinDepositAmount(0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.9 Admin config — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-ADM-2: setVault emits VaultUpdated event
    function test_N_ADM_2_setVaultEvent() public {
        address newVault = makeAddr("newVault");

        vm.expectEmit(true, false, false, true, address(fundToken));
        emit CoboFundToken.VaultUpdated(newVault);

        vm.prank(admin);
        fundToken.setVault(newVault);
    }

    /// @dev N-ADM-4: setMinDepositAmount(0)
    function test_N_ADM_4_setMinDeposit_zero() public {
        vm.prank(admin);
        fundToken.setMinDepositAmount(0);
        assertEq(fundToken.minDepositAmount(), 0);

        // Any positive deposit should now work (even 1 wei)
        uint256 shares = _deposit(user1, 1);
        assertGt(shares, 0);
    }

    /// @dev N-ADM-6: setMinRedeemShares(0)
    function test_N_ADM_6_setMinRedeem_zero() public {
        vm.prank(admin);
        fundToken.setMinRedeemShares(0);
        assertEq(fundToken.minRedeemShares(), 0);
    }

    /// @dev N-ADM-7: setOracle by non-admin reverts
    function test_N_ADM_7_setOracle_nonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        fundToken.setOracle(makeAddr("newOracle"));
    }

    /// @dev N-ADM-8: setVault by non-admin reverts
    function test_N_ADM_8_setVault_nonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        fundToken.setVault(makeAddr("newVault"));
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.10 Whitelist — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-WL-2: remove user from whitelist
    function test_N_WL_2_removeUser() public {
        address newUser = makeAddr("wlUser");
        vm.prank(manager);
        fundToken.addToWhitelist(newUser);
        assertTrue(fundToken.whitelist(newUser));

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(newUser);
        assertFalse(fundToken.whitelist(newUser));
    }

    /// @dev N-WL-4: repeat add — no side effect
    function test_N_WL_4_repeatAdd() public {
        // user1 is already whitelisted
        assertTrue(fundToken.whitelist(user1));

        vm.prank(manager);
        fundToken.addToWhitelist(user1);
        assertTrue(fundToken.whitelist(user1));
    }

    /// @dev N-WL-5: repeat remove — no side effect
    function test_N_WL_5_repeatRemove() public {
        address nonUser = makeAddr("nonUser2");
        // Add then remove, then remove again
        vm.prank(manager);
        fundToken.addToWhitelist(nonUser);
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(nonUser);
        assertFalse(fundToken.whitelist(nonUser));

        // Remove again — no error
        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(nonUser);
        assertFalse(fundToken.whitelist(nonUser));
    }

    /// @dev N-WL-6: removed user blocked from mint, requestRedemption, transfer
    function test_N_WL_6_removedUserBlocked() public {
        _deposit(user1, 10e6);

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user1);

        // Cannot mint
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.mint(1e6);

        // Cannot requestRedemption
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.requestRedemption(1e18);

        // Cannot transfer (as sender)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.transfer(user2, 1e18);

        // Cannot receive transfer
        _deposit(user2, 10e6);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotWhitelisted.selector, user1));
        fundToken.transfer(user1, 1e18);
    }

    /// @dev N-WL-7: setWhitelist(address(0)) reverts
    function test_N_WL_7_zeroAddress() public {
        vm.prank(manager);
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        fundToken.addToWhitelist(address(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2.12 rescue — additional cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev N-RSC-2: to=address(0) reverts
    function test_N_RSC_2_zeroTo() public {
        MockERC20 randomToken = new MockERC20("R", "R", 18);
        randomToken.mint(address(fundToken), 100e18);

        vm.prank(admin);
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        fundToken.rescueERC20(address(randomToken), address(0), 100e18);
    }

    /// @dev N-RSC-3: non-admin reverts
    function test_N_RSC_3_nonAdmin() public {
        MockERC20 randomToken = new MockERC20("R", "R", 18);
        randomToken.mint(address(fundToken), 100e18);

        vm.prank(attacker);
        vm.expectRevert();
        fundToken.rescueERC20(address(randomToken), attacker, 100e18);
    }

    /// @dev N-RSC-4: no balance → revert
    function test_N_RSC_4_noBalance() public {
        MockERC20 randomToken = new MockERC20("R", "R", 18);
        // No tokens minted to fundToken

        vm.prank(admin);
        vm.expectRevert(); // ERC20 transfer fails (insufficient balance)
        fundToken.rescueERC20(address(randomToken), admin, 100e18);
    }
}

// ═══════════════════════════════════════════════════════════════════
// Helper mock contracts for tests
// ═══════════════════════════════════════════════════════════════════

/// @dev Oracle mock that returns 0 NAV
contract MockZeroOracle {
    function getLatestPrice() external pure returns (uint256) {
        return 0;
    }
}

/// @dev Oracle mock that returns very high NAV (causes 0 shares)
contract MockHighNavOracle {
    function getLatestPrice() external pure returns (uint256) {
        return type(uint128).max;
    }
}

/// @dev Oracle mock that returns a fixed NAV
contract MockFixedOracle {
    uint256 private _price;

    constructor(uint256 price_) {
        _price = price_;
    }

    function getLatestPrice() external view returns (uint256) {
        return _price;
    }
}

/// @dev Contract that reverts on any token receive attempt
contract RevertOnReceive {
    fallback() external {
        revert("no receive");
    }
}

/// @dev ERC20 mock that can be set to fail on transfer (but not transferFrom, so the initial safeTransferFrom succeeds)
contract FailingERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    string public name = "FailToken";
    string public symbol = "FAIL";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    bool public failTransfer;

    function setFailTransfer(bool _fail) external {
        failTransfer = _fail;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (failTransfer) revert("transfer failed");
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (failTransfer) revert("transfer failed");
        require(balanceOf[from] >= amount, "insufficient");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function forceApprove(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }
}

// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "./FundTestBase.sol";

contract CoboFundVaultTest is FundTestBase {
    // ═══════════════════════════════════════════════════════════════════
    // 3.1 initialize
    // ═══════════════════════════════════════════════════════════════════

    function test_vault_initialize_normal() public view {
        assertEq(address(vault.xaut()), address(xaut));
        assertEq(address(vault.fundToken()), address(fundToken));
        assertTrue(vault.hasRole(DEFAULT_ADMIN_ROLE, admin));
        // Vault approved Nav4626 for max uint256
        assertEq(xaut.allowance(address(vault), address(fundToken)), type(uint256).max);
    }

    function test_vault_initialize_revert_double() public {
        vm.expectRevert();
        vault.initialize(address(xaut), address(fundToken), admin);
    }

    function test_vault_initialize_revert_zeroXaut() public {
        CoboFundVault impl = new CoboFundVault();
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl), abi.encodeCall(CoboFundVault.initialize, (address(0), address(fundToken), admin))
        );
    }

    function test_vault_initialize_revert_zeroNav4626() public {
        CoboFundVault impl = new CoboFundVault();
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(CoboFundVault.initialize, (address(xaut), address(0), admin)));
    }

    function test_vault_initialize_revert_zeroAdmin() public {
        CoboFundVault impl = new CoboFundVault();
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl), abi.encodeCall(CoboFundVault.initialize, (address(xaut), address(fundToken), address(0)))
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.2 withdraw
    // ═══════════════════════════════════════════════════════════════════

    function test_vault_withdraw_normal() public {
        // Fund vault with XAUT
        xaut.mint(address(vault), 100e6);

        vm.prank(settlementOperator);
        vault.withdraw(user1, 50e6);
        assertEq(xaut.balanceOf(user1), 1050e6); // 1000 + 50
    }

    function test_vault_withdraw_revert_notOperator() public {
        xaut.mint(address(vault), 100e6);
        vm.prank(attacker);
        vm.expectRevert();
        vault.withdraw(user1, 50e6);
    }

    function test_vault_withdraw_revert_notWhitelisted() public {
        xaut.mint(address(vault), 100e6);
        vm.prank(settlementOperator);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotInVaultWhitelist.selector, user3));
        vault.withdraw(user3, 50e6); // user3 not in vault whitelist
    }

    function test_vault_withdraw_revert_zeroAddress() public {
        xaut.mint(address(vault), 100e6);
        vm.prank(settlementOperator);
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        vault.withdraw(address(0), 50e6);
    }

    // Security fix: withdraw with zero amount reverts
    function test_vault_withdraw_revert_zeroAmount() public {
        xaut.mint(address(vault), 100e6);
        vm.prank(settlementOperator);
        vm.expectRevert(LibFundErrors.ZeroAmount.selector);
        vault.withdraw(user1, 0);
    }

    function test_vault_withdraw_revert_paused() public {
        xaut.mint(address(vault), 100e6);

        // Pause via Nav4626
        vm.prank(admin);
        fundToken.pause();

        vm.prank(settlementOperator);
        vm.expectRevert(LibFundErrors.SystemPaused.selector);
        vault.withdraw(user1, 50e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.3 setWhitelist
    // ═══════════════════════════════════════════════════════════════════

    function test_vault_setWhitelist() public {
        address target = makeAddr("target");
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit CoboFundVault.WhitelistUpdated(target, true);
        vault.setWhitelist(target, true);
        assertTrue(vault.whitelist(target));

        vm.prank(admin);
        vault.setWhitelist(target, false);
        assertFalse(vault.whitelist(target));
    }

    function test_vault_setWhitelist_revert_nonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.setWhitelist(attacker, true);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.4 setFundToken
    // ═══════════════════════════════════════════════════════════════════

    function test_vault_setFundToken() public {
        address newNav = makeAddr("newNav4626");

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit CoboFundVault.FundTokenUpdated(newNav);
        vault.setFundToken(newNav);

        assertEq(address(vault.fundToken()), newNav);
        // Old approval revoked, new approval set
        assertEq(xaut.allowance(address(vault), address(fundToken)), 0);
        assertEq(xaut.allowance(address(vault), newNav), type(uint256).max);
    }

    function test_vault_setFundToken_revert_zeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        vault.setFundToken(address(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.5 rescueERC20
    // ═══════════════════════════════════════════════════════════════════

    function test_vault_rescueERC20_normal() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(vault), 100e18);

        vm.prank(admin);
        vault.rescueERC20(address(randomToken), admin, 100e18);
        assertEq(randomToken.balanceOf(admin), 100e18);
    }

    function test_vault_rescueERC20_revert_coreAsset() public {
        xaut.mint(address(vault), 100e6);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.CannotRescueCoreAsset.selector, address(xaut)));
        vault.rescueERC20(address(xaut), admin, 100e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.6 Admin self-protection
    // ═══════════════════════════════════════════════════════════════════

    function test_vault_lastAdmin_protected() public {
        vm.prank(admin);
        vm.expectRevert(LibFundErrors.LastAdminCannotBeRevoked.selector);
        vault.revokeRole(DEFAULT_ADMIN_ROLE, admin);

        vm.prank(admin);
        vm.expectRevert(LibFundErrors.LastAdminCannotBeRevoked.selector);
        vault.renounceRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function test_vault_version() public view {
        assertEq(vault.version(), 1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.2 withdraw — additional tests
    // ═══════════════════════════════════════════════════════════════════

    /// @dev V-WD-2: Verify XAUT balance changes (vault -amount, recipient +amount)
    function test_vault_withdraw_balanceChanges() public {
        xaut.mint(address(vault), 100e6);

        uint256 vaultBefore = xaut.balanceOf(address(vault));
        uint256 user1Before = xaut.balanceOf(user1);

        vm.prank(settlementOperator);
        vault.withdraw(user1, 60e6);

        assertEq(xaut.balanceOf(address(vault)), vaultBefore - 60e6);
        assertEq(xaut.balanceOf(user1), user1Before + 60e6);
    }

    /// @dev V-WD-4: Owner (non-operator) cannot withdraw
    function test_vault_withdraw_revert_ownerNotOperator() public {
        xaut.mint(address(vault), 100e6);
        vm.prank(admin);
        vm.expectRevert();
        vault.withdraw(user1, 50e6);
    }

    /// @dev V-WD-8: Insufficient vault XAUT balance reverts
    function test_vault_withdraw_revert_insufficientBalance() public {
        // Vault has 0 XAUT
        vm.prank(settlementOperator);
        vm.expectRevert();
        vault.withdraw(user1, 1e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.3 setWhitelist — additional tests
    // ═══════════════════════════════════════════════════════════════════

    /// @dev V-WL-4: After removing whitelist, withdraw to that address fails
    function test_vault_whitelist_removeAndWithdrawFails() public {
        xaut.mint(address(vault), 100e6);

        // user1 is whitelisted, confirm withdraw works
        vm.prank(settlementOperator);
        vault.withdraw(user1, 10e6);

        // Admin removes user1 from whitelist
        vm.prank(admin);
        vault.setWhitelist(user1, false);

        // Now withdraw to user1 should fail
        vm.prank(settlementOperator);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.NotInVaultWhitelist.selector, user1));
        vault.withdraw(user1, 10e6);
    }

    /// @dev Additional: setWhitelist with zero address reverts
    function test_vault_setWhitelist_revert_zeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        vault.setWhitelist(address(0), true);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.4 setFundToken — additional tests
    // ═══════════════════════════════════════════════════════════════════

    /// @dev V-SN-5: Old Nav4626 cannot transferFrom vault after setFundToken
    function test_vault_setFundToken_oldCannotTransferFrom() public {
        xaut.mint(address(vault), 100e6);
        address oldNav = address(fundToken);
        address newNav = makeAddr("newNav4626");

        vm.prank(admin);
        vault.setFundToken(newNav);

        // Old Nav4626 tries to pull XAUT from vault — should fail (allowance == 0)
        vm.prank(oldNav);
        vm.expectRevert();
        xaut.transferFrom(address(vault), oldNav, 1e6);
    }

    /// @dev V-SN-6: New Nav4626 can transferFrom vault after setFundToken
    function test_vault_setFundToken_newCanTransferFrom() public {
        xaut.mint(address(vault), 100e6);
        address newNav = makeAddr("newNav4626");

        vm.prank(admin);
        vault.setFundToken(newNav);

        // New Nav4626 pulls XAUT from vault — should succeed (allowance == max)
        vm.prank(newNav);
        xaut.transferFrom(address(vault), newNav, 1e6);

        assertEq(xaut.balanceOf(newNav), 1e6);
    }

    /// @dev V-SN-7: After setFundToken to a paused Nav4626, vault withdraw reverts
    function test_vault_setFundToken_newPaused_withdrawReverts() public {
        xaut.mint(address(vault), 100e6);

        // Deploy a second Nav4626 that will be paused
        uint64 nonce = vm.getNonce(address(this));
        address predictedVault2 = vm.computeCreateAddress(address(this), nonce + 1);

        bytes memory fundTokenInit2 = abi.encodeCall(
            CoboFundToken.initialize,
            (
                "XAUE2",
                "XAUE2",
                XAUE_DECIMALS,
                address(xaut),
                address(oracle),
                predictedVault2,
                admin,
                MIN_DEPOSIT_AMOUNT,
                MIN_REDEEM_SHARES
            )
        );
        CoboFundToken newNav4626 = CoboFundToken(address(new ERC1967Proxy(address(fundTokenImpl), fundTokenInit2)));

        // Deploy a dummy vault for the new fundToken (to satisfy predictedVault2)
        CoboFundVault dummyVault = CoboFundVault(
            address(
                new ERC1967Proxy(
                    address(vaultImpl),
                    abi.encodeCall(CoboFundVault.initialize, (address(xaut), address(newNav4626), admin))
                )
            )
        );
        assertEq(address(dummyVault), predictedVault2);

        // Pause the new Nav4626
        vm.prank(admin);
        newNav4626.pause();

        // Point our vault to the new (paused) Nav4626
        vm.prank(admin);
        vault.setFundToken(address(newNav4626));

        // Withdraw should revert because new fundToken is paused
        vm.prank(settlementOperator);
        vm.expectRevert(LibFundErrors.SystemPaused.selector);
        vault.withdraw(user1, 10e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.5 SETTLEMENT_OPERATOR_ROLE management
    // ═══════════════════════════════════════════════════════════════════

    /// @dev V-SO-1: Grant SETTLEMENT_OPERATOR_ROLE to new operator, they can withdraw
    function test_vault_grantSettlementOperator_newOperatorCanWithdraw() public {
        xaut.mint(address(vault), 100e6);
        address newOperator = makeAddr("newOperator");

        vm.prank(admin);
        vault.grantRole(SETTLEMENT_OPERATOR_ROLE, newOperator);

        vm.prank(newOperator);
        vault.withdraw(user1, 10e6);
        assertEq(xaut.balanceOf(user1), 1010e6); // 1000 initial + 10
    }

    /// @dev V-SO-2: Non-admin cannot grant SETTLEMENT_OPERATOR_ROLE
    function test_vault_grantSettlementOperator_revert_nonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.grantRole(SETTLEMENT_OPERATOR_ROLE, attacker);
    }

    /// @dev V-SO-3: New operator can withdraw (confirmed via full flow)
    function test_vault_settlementOperator_newOperatorWithdrawFlow() public {
        xaut.mint(address(vault), 200e6);
        address newOp = makeAddr("newOp");

        // Grant new operator
        vm.prank(admin);
        vault.grantRole(SETTLEMENT_OPERATOR_ROLE, newOp);

        // New operator withdraws
        vm.prank(newOp);
        vault.withdraw(user1, 50e6);

        // Original operator also still works
        vm.prank(settlementOperator);
        vault.withdraw(user2, 50e6);

        assertEq(xaut.balanceOf(user1), 1050e6);
        assertEq(xaut.balanceOf(user2), 1050e6);
    }

    /// @dev V-SO-4: After revoking SETTLEMENT_OPERATOR_ROLE, old operator cannot withdraw
    function test_vault_revokeSettlementOperator_cannotWithdraw() public {
        xaut.mint(address(vault), 100e6);

        // Revoke from current settlementOperator
        vm.prank(admin);
        vault.revokeRole(SETTLEMENT_OPERATOR_ROLE, settlementOperator);

        vm.prank(settlementOperator);
        vm.expectRevert();
        vault.withdraw(user1, 10e6);
    }

    /// @dev V-SO-5: If no one has SETTLEMENT_OPERATOR_ROLE, no one can withdraw
    function test_vault_noSettlementOperator_nobodyCanWithdraw() public {
        xaut.mint(address(vault), 100e6);

        // Revoke from the only settlement operator
        vm.prank(admin);
        vault.revokeRole(SETTLEMENT_OPERATOR_ROLE, settlementOperator);

        // Even admin cannot withdraw
        vm.prank(admin);
        vm.expectRevert();
        vault.withdraw(user1, 10e6);

        // Random user cannot withdraw
        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(user1, 10e6);

        // Attacker cannot withdraw
        vm.prank(attacker);
        vm.expectRevert();
        vault.withdraw(user1, 10e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3.5 rescueERC20 — additional edge cases
    // ═══════════════════════════════════════════════════════════════════

    /// @dev rescueERC20 with zero recipient reverts
    function test_vault_rescueERC20_revert_zeroRecipient() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(vault), 100e18);

        vm.prank(admin);
        vm.expectRevert(LibFundErrors.ZeroAddress.selector);
        vault.rescueERC20(address(randomToken), address(0), 100e18);
    }

    /// @dev rescueERC20 by non-admin reverts
    function test_vault_rescueERC20_revert_nonAdmin() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(vault), 100e18);

        vm.prank(attacker);
        vm.expectRevert();
        vault.rescueERC20(address(randomToken), attacker, 100e18);
    }

    /// @dev rescueERC20 when vault has no balance of the token reverts
    function test_vault_rescueERC20_revert_noBalance() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        // vault has 0 balance of randomToken

        vm.prank(admin);
        vm.expectRevert();
        vault.rescueERC20(address(randomToken), admin, 100e18);
    }
}

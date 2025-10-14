// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title Role Access Upgradeable
 * @author Cobo Dev Team https://www.cobo.com/
 * @notice This abstract contract provides internal contract logic for managing access control roles.
 */
abstract contract RoleAccessUpgradeable is Initializable, AccessControlEnumerableUpgradeable {
    /// Functions

    /**
     * @notice This is an initializer function for the abstract contract.
     * @dev Standard Initializable contract behavior.
     *
     * Calling Conditions:
     *
     * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
     */
    function __RoleAccess_init() internal onlyInitializing {
        __AccessControlEnumerable_init();
    }

    /**
     * @notice This function revokes an Access Control role from an account, except for the _msgSender()'s "DEFAULT_ADMIN_ROLE".
     *
     * @dev Calling Conditions:
     *
     * - The caller must be the role admin of the `role`.
     * - The caller must not be the `account` itself with the "DEFAULT_ADMIN_ROLE".
     * - The `account` must be a non-zero address.
     *
     * This function emits a {RoleRevoked} event as part of {AccessControlUpgradeable._revokeRole}.
     *
     * @param role The role that will be revoked.
     * @param account The address from which role is revoked
     */
    function revokeRole(bytes32 role, address account) public virtual override(AccessControlUpgradeable, IAccessControl) {
        if (role == DEFAULT_ADMIN_ROLE && account == _msgSender()) {
            revert LibErrors.DefaultAdminError();
        }
        super.revokeRole(role, account); // In {AccessControlUpgradeable}
    }

    /**
     * @notice  This function renounces an Access Control role from an account, except for the "DEFAULT_ADMIN_ROLE".
     *
     * @dev Only the account itself can renounce its own roles, and not any other account. 
     *
     * Calling Conditions:
     *
     * - The `account` must be the caller of the transaction.
     * - The `account` cannot renounce the "DEFAULT_ADMIN_ROLE".
     */
    function renounceRole(bytes32 role, address account) public virtual override(AccessControlUpgradeable, IAccessControl) {
        if (role == DEFAULT_ADMIN_ROLE && getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1) {
            revert LibErrors.DefaultAdminError();
        }
        super.renounceRole(role, account); // In {AccessControlUpgradeable}
    }

    /* solhint-enable func-name-mixedcase */
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    //slither-disable-next-line naming-convention
    uint256[50] private __gap;
}

// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title AccessList Upgradeable
 * @author Cobo Dev Team https://www.cobo.com/
 * @notice The AccessList Upgradeable establishes an on-chain AccessList and BlockList for the CoboERC20 contract.
 * It maintains a registry of addresses allowed to participate in the system and blocked from participating in the system.
 */
abstract contract AccessListUpgradeable is
	Initializable
{
	using EnumerableSet for EnumerableSet.AddressSet;

	/// State

	bool public accessListEnabled;

	/**
	 * @notice A set that tracks address Access List membership.
	 * @dev Default `false` indicates that an address is not in the Access List. A value of `true`
	 * indicates the address is in the Access List.
	 */
	EnumerableSet.AddressSet internal _accessList;

	/**
	 * @notice A set that tracks address Block List membership.
	 * @dev Default `false` indicates that an address is not in the Block List. A value of `true`
	 * indicates the address is in the Block List.
	 */
	EnumerableSet.AddressSet internal _blockList;

	/// Events

	/**
	 * @notice This event is logged when an address is added to the Access list.
	 *
	 * @dev Notifies that the ability of logged address to participant is changed as per the implementation contract.
	 *
	 * @param account The (indexed) address which was added to the Access list.
	 */
	event AccessListAddressAdded(address indexed account);

	/**
	 * @notice This event is logged when an address is removed from the Access list.
	 * @dev Notifies that the ability of logged address to participant is changed as per the implementation contract.
	 *
	 * @param account The (indexed) address which was removed from the Access list.
	 */
	event AccessListAddressRemoved(address indexed account);

	/**
	 * @notice This event is logged when an address is added to the Block list.
	 *
	 * @dev Notifies that the ability of logged address to participant is changed as per the implementation contract.
	 *
	 * @param account The (indexed) address which was added to the Block list.
	 */
	event BlockListAddressAdded(address indexed account);

	/**
	 * @notice This event is logged when an address is removed from the Block list.
	 * @dev Notifies that the ability of logged address to participant is changed as per the implementation contract.
	 *
	 * @param account The (indexed) address which was removed from the Block list.
	 */
	event BlockListAddressRemoved(address indexed account);

	/**
	 * @notice This event is logged when the access list is toggled.
	 * @dev Notifies that the access list is enabled or disabled.
	 *
	 * @param enabled The (indexed) boolean value indicating whether the access list is enabled.
	 */
	event AccesslistToggled(bool indexed enabled);
	
	/// Functions

	/**
	 * @notice Initializes the contract and its inherited base contracts.
	 *
	 * @dev  Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 */
	/* solhint-disable func-name-mixedcase */
	function __AccessList_init() internal virtual onlyInitializing {
		accessListEnabled = false;
	}

	/**
	 * @notice This function toggles the access list. The function can be called by the address which has the "MANAGER_ROLE".
	 * The access list is disabled by default.
	 *
	 * @dev Calling Conditions:
	 *
	 * - The caller must hold the "MANAGER_ROLE" role.
	 *
	 * This function emits a {AccesslistToggled} event only when it successfully toggles the access list.
	 *
	 * @param enabled The boolean value indicating whether the access list is enabled.
	 */
	function toggleAccesslist(
        bool enabled
    ) external virtual {
		_authorizeAccessList();
        accessListEnabled = enabled;
        emit AccesslistToggled(enabled);
    }


	/**
	 * @notice This function adds a list of given address to the AccessList. This will allow the specified addresses
	 * to interact with the CoboERC20 contract. The function can be called by the address which has the "MANAGER_ROLE".
	 * The access list is disabled by default.
	 *
	 * @dev Calling Conditions:
	 *
	 * - The caller must hold the "MANAGER_ROLE" role.
	 * - All the addresses in the`accounts` array must be a non-zero address.
	 *
	 * This function emits a {AccessListAddressAdded} event only when it successfully adds an address to
	 * the `_accessList` mapping, given that the address was previously not present on AccessList.
	 *
	 * @param accounts The list addresses to be added to the AccessList.
	 */
	function accessListAdd(address[] calldata accounts) external virtual {
		_authorizeAccessList();
		uint256 length = accounts.length;
		for (uint256 i = 0; i < length; ++i) {
			if (accounts[i] == address(0)) {
				revert LibErrors.InvalidAddress();
			}
			if (_accessList.add(accounts[i])) {
				emit AccessListAddressAdded(accounts[i]);
			}
		}
	}

	/**
	 * @notice This function removes a list of given address from the AccessList. The function can be
	 * called by the address which has the "MANAGER_ROLE".
	 *
	 * @dev Calling Conditions:
	 *
	 * - The caller must hold the "MANAGER_ROLE" role.
	 *
	 * This function emits a {AccessListAddressRemoved} event only when it successfully removes an address from
	 * the `_accessList` mapping, given that the address was previously present on AccessList.
	 *
	 * @param accounts The list addresses to be removed from the AccessList.
	 */
	function accessListRemove(
		address[] calldata accounts
	) external virtual {
		_authorizeAccessList();
		uint256 length = accounts.length;
		for (uint256 i = 0; i < length; ++i) {
			if (_accessList.remove(accounts[i])) {
				emit AccessListAddressRemoved(accounts[i]);
			}
		}
	}

	/**
	 * @notice This function adds a list of given address to the BlockList. This will block the specified addresses
	 * from interacting with the CoboERC20 contract. The function can be called by the address which has the "MANAGER_ROLE".
	 *
	 * @dev Calling Conditions:
	 *
	 * - The caller must hold the "MANAGER_ROLE" role.
	 * - All the addresses in the`accounts` array must be a non-zero address.
	 *
	 * This function emits a {BlockListAddressAdded} event only when it successfully adds an address to
	 * the `_blockList` mapping, given that the address was previously not present on BlockList.
	 *
	 * @param accounts The list addresses to be added to the BlockList.
	 */
	function blockListAdd(address[] calldata accounts) external virtual {
		_authorizeBlockList();
		uint256 length = accounts.length;
		for (uint256 i = 0; i < length; ++i) {
			if (accounts[i] == address(0)) {
				revert LibErrors.InvalidAddress();
			}
			if (_blockList.add(accounts[i])) {
				emit BlockListAddressAdded(accounts[i]);
			}
		}
	}

	/**
	 * @notice This function removes a list of given address from the BlockList. The function can be
	 * called by the address which has the "MANAGER_ROLE".
	 *
	 * @dev Calling Conditions:
	 *
	 * - The caller must hold the "MANAGER_ROLE" role.
	 *
	 * This function emits a {BlockListAddressRemoved} event only when it successfully removes an address from
	 * the `_blockList` mapping, given that the address was previously present on BlockList.
	 *
	 * @param accounts The list addresses to be removed from the BlockList.
	 */
	function blockListRemove(
		address[] calldata accounts
	) external virtual {
		_authorizeBlockList();
		uint256 length = accounts.length;
		for (uint256 i = 0; i < length; ++i) {
			if (_blockList.remove(accounts[i])) {
				emit BlockListAddressRemoved(accounts[i]);
			}
		}
	}

	/**
	 * @notice This function returns the list of addresses that are in the access list.
	 *
	 * @dev This function returns the list of addresses that are in the `_accessList`.
	 *
	 * Note: This is designed to be a helper function that is called from off-chain.
	 * If the `_accessList` is large, this function will consume a lot of gas or revert.
	 *
	 * @return The list of addresses that are in the access list.
	 */
	function getAccessList() external view virtual returns (address[] memory) {
		return _accessList.values();
	}

	/**
	 * @notice This function checks if an address is present in the AccessList. By doing so, it confirms that whether
	 * the  address is allowed to participate in the system.
	 * @dev This function returns `true` if the address is present in the AccessList, otherwise it returns `false`.
	 *
	 * @param account The address to be checked.
	 * @return `true` if the address is present in the AccessList, otherwise it returns `false`.
	 */
	function isAccessListed(address account) external view virtual returns (bool) {
		return _accessList.contains(account);
	}

	/**
	 * @notice This function returns the list of addresses that are in the BlockList.
	 *
	 * @dev This function returns the list of addresses that are in the `_blockList`.
	 *
	 * Note: This is designed to be a helper function that is called from off-chain.
	 * If the `_blockList` is large, this function will consume a lot of gas or revert.
	 *
	 * @return The list of addresses that are in the BlockList.
	 */
	function getBlockList() external view virtual returns (address[] memory) {
		return _blockList.values();
	}

	/**
	 * @notice This function checks if an address is present in the BlockList. By doing so, it confirms that whether
	 * the  address is blocked from participating in the system.
	 * @dev This function returns `true` if the address is present in the BlockList, otherwise it returns `false`.
	 *
	 * @param account The address to be checked.
	 * @return `true` if the address is present in the BlockList, otherwise it returns `false`.
	 */
	function isBlockListed(address account) external view virtual returns (bool) {
		return _blockList.contains(account);
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control for the AccessList.
	 */
	function _authorizeAccessList() internal virtual;

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control for the BlockList.
	 */
	function _authorizeBlockList() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[48] private __gap;
}

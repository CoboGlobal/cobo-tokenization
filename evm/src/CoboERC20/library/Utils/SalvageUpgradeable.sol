// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title Salvage Upgradeable
 * @author Cobo Dev Team https://www.cobo.com/
 * @notice This abstract contract provides internal contract logic for salvaging native token and ERC20 tokens.
 */
abstract contract SalvageUpgradeable is Initializable, ContextUpgradeable {
	using SafeERC20 for IERC20;

	/// Events
	/**
	 * @notice This event is logged when ERC20 tokens are salvaged.
	 *
	 * @param caller The (indexed) address of the entity that triggered the salvage.
	 * @param token The (indexed) address of the ERC20 token which was salvaged.
	 * @param amount The (indexed) amount of tokens salvaged.
	 */
	event TokenSalvaged(address indexed caller, address indexed token, uint256 indexed amount);

	/**
	 * @notice This event is logged when Native token is salvaged.
	 *
	 * @param caller The (indexed) address of the entity that triggered the salvage.
	 * @param amount The (indexed) amount of native token salvaged.
	 */
	event NativeSalvaged(address indexed caller, uint256 indexed amount);

	/// Functions

	/**
	 * @notice This is an initializer function for the abstract contract.
	 * @dev Standard Initializable contract behavior.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 */
	/* solhint-disable func-name-mixedcase */
	function __Salvage_init() internal onlyInitializing {}

	/**
	 * @notice A function used to salvage ERC20 tokens sent to the contract using this abstract contract.
	 *
	 * @dev Calling Conditions:
	 *
	 * - The `amount` must be greater than 0.
	 *
	 * This function emits a {TokenSalvaged} event, indicating that funds were salvaged.
	 *
	 * @param token The ERC20 asset which is to be salvaged.
	 * @param amount The amount to be salvaged.
	 */
	function salvageERC20(IERC20 token, uint256 amount) external virtual {
		if (amount == 0) {
			revert LibErrors.ZeroAmount();
		}
		_authorizeSalvage();
		token.safeTransfer(_msgSender(), amount);
		emit TokenSalvaged(_msgSender(), address(token), amount);
	}

	/**
	 * @notice A function used to salvage native token sent to the contract using this abstract contract.
	 *
	 * @dev Calling Conditions:
	 *
	 * - The `amount` must be greater than 0.
	 *
	 * This function emits a {NativeSalvaged} event, indicating that funds were salvaged.
	 *
	 * @param amount The amount to be salvaged.
	 */
	function salvageNative(uint256 amount) external virtual {
		if (amount == 0) {
			revert LibErrors.ZeroAmount();
		}
		_authorizeSalvage();
		(bool succeed, ) = _msgSender().call{value: amount}("");
		if (!succeed) {
			revert LibErrors.SalvageNativeFailed();
		}
		emit NativeSalvaged(_msgSender(), amount);
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control for the salvage.
	 */
	function _authorizeSalvage() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[50] private __gap;
}

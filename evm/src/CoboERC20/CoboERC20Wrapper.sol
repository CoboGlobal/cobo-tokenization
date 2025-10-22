// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Upgradeable, IERC20, IERC20Metadata} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {UUPSUpgradeable, IERC1822Proxiable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ContractUriUpgradeable} from "./library/Utils/ContractUriUpgradeable.sol";
import {SalvageUpgradeable} from "./library/Utils/SalvageUpgradeable.sol";
import {PauseUpgradeable} from "./library/Utils/PauseUpgradeable.sol";
import {RoleAccessUpgradeable} from "./library/Utils/RoleAccessUpgradeable.sol";
import {AccessListUpgradeable} from "./library/Utils/AccessListUpgradeable.sol";
import {LibErrors} from "./library/Errors/LibErrors.sol";

/**
 * @title CoboERC20Wrapper
 * @author Cobo Dev Team https://www.cobo.com/
 *
 * This contract Role Based Access Control employs following roles:
 *
 *  - MINTER_ROLE
 *  - WRAPPER_ROLE
 *  - MANAGER_ROLE
 *  - SALVAGER_ROLE
 *  - PAUSER_ROLE
 *  - UPGRADER_ROLE
 *  - DEFAULT_ADMIN_ROLE

 */
contract CoboERC20Wrapper is
    Initializable,
    ERC20Upgradeable,
    MulticallUpgradeable,
    SalvageUpgradeable,
    ContractUriUpgradeable,
    PauseUpgradeable,
    RoleAccessUpgradeable,
    AccessListUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// Constants
    /**
     * @notice The version of the contract.
     * @dev This constant holds the version of the contract.
     */
    uint64 public constant VERSION = 1;

    /**
     * @notice The Access Control identifier for the Upgrader Role.
     * An account with "UPGRADER_ROLE" can upgrade the implementation contract address.
     *
     * @dev This constant holds the hash of the string "UPGRADER_ROLE".
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /**
     * @notice The Access Control identifier for the Pauser Role.
     * An account with "PAUSER_ROLE" can pause the contract.
     *
     * @dev This constant holds the hash of the string "PAUSER_ROLE".
     */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @notice The Access Control identifier for the Manager Role.
     * An account with "MANAGER_ROLE" can update the contract URI,
     * unpause the contract, toggle the access list status, update the access list, and update the block list.
     *
     * @dev This constant holds the hash of the string "MANAGER_ROLE".
     */
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /**
     * @notice The Access Control identifier for the Minter Role.
     * An account with "MINTER_ROLE" can mint tokens to the specified address.
     *
     * @dev This constant holds the hash of the string "MINTER_ROLE".
     */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice The Access Control identifier for the Wrapper Role.
     * An account with "WRAPPER_ROLE" can wrap tokens from their own address.
     *
     * @dev This constant holds the hash of the string "WRAPPER_ROLE".
     */
    bytes32 public constant WRAPPER_ROLE = keccak256("WRAPPER_ROLE");

    /**
     * @notice The Access Control identifier for the Salvager Role.
     * An account with "SALVAGER_ROLE" can salvage native and ERC20 tokens from the contract.
     *
     * @dev This constant holds the hash of the string "SALVAGER_ROLE".
     */
    bytes32 public constant SALVAGER_ROLE = keccak256("SALVAGER_ROLE");

    /// State Variables

    /// @notice The decimal of the token.
    uint8 internal _decimals;

    IERC20 private _underlying;

    /**
     * @dev The underlying token couldn't be wrapped.
     */
    error ERC20InvalidUnderlying(address token);

    /**
     * @dev The underlying token couldn't be salvaged.
     */
    error ERC20InvalidSalvage();

    event  Deposit(address indexed account, uint256 value);
    event  Withdrawal(address indexed account, uint256 value);

    /// Functions

    /**
     * @notice This function acts as the constructor of the contract.
     * @dev This function disables the initializers.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice This function configures the CoboERC20 contract with the initial state and granting
     * privileged roles.
     *
     * @dev Calling Conditions:
     *
     * - Can only be invoked once (controlled via the {initializer} modifier).
     *
     * @param underlyingToken The underlying token.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param uri The URI of the token.
     * @param admin The address of the admin.
     */
    function initialize(
        IERC20 underlyingToken,
        string calldata name,
        string calldata symbol,
        string calldata uri,
        address admin
    ) external virtual initializer {
        if (underlyingToken == this) {
            revert ERC20InvalidUnderlying(address(this));
        }
        _underlying = underlyingToken;
        _decimals = IERC20Metadata(address(_underlying)).decimals();

        if (admin == address(0)) {
            revert LibErrors.InvalidAddress();
        }

        __UUPSUpgradeable_init();
        __ERC20_init(name, symbol);
        __Multicall_init();
        __Salvage_init();
        __ContractUri_init(uri);
        __Pause_init();
        __RoleAccess_init();
        __AccessList_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice This is a function used to issue new tokens.
     * The caller will issue tokens to the `to` address.
     *
     * @dev Calling Conditions:
     *
     * - Can only be invoked by the address that has the role "MINTER_ROLE".
     * - {CoboERC20} is not paused.
     * - `to` is a non-zero address. (checked internally by {ERC20Upgradeable}.{_mint})
     * - `to` is allowed to receive tokens.
     *
     * This function emits a {Transfer} event as part of {ERC20Upgradeable._mint}.
     *
     * @param to The address that will receive the issued tokens.
     */
    function mint(address to) external virtual whenNotPaused onlyRole(MINTER_ROLE) {
        _requireAccess(to);
        _recover(to);
    }

    /**
     * @notice This is a function used to transfer tokens from the sender to the `to` address.
     *
     * @dev Calling Conditions:
     *
     * - {CoboERC20} is not paused.
     * - The `sender` is allowed to send tokens. (checked internally by {_requireAccess})
     * - The `to` is allowed to receive tokens. (checked internally by {_requireAccess})
     * - `to` is a non-zero address. (checked internally by {ERC20Upgradeable}.{_transfer})
     * - `amount` is not greater than sender's balance. (checked internally by {ERC20Upgradeable}.{_transfer})
     *
     * This function emits a {Transfer} event as part of {ERC20Upgradeable._transfer}.
     *
     * @param to The address that will receive the tokens.
     * @param amount The number of tokens that will be sent to the `to` address.
     * @return True if the function was successful.
     */
    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        _requireAccess(_msgSender());
        _requireAccess(to);

        return super.transfer(to, amount);
    }

    /**
     * @notice This is a function used to transfer tokens on behalf of the `from` address to the `to` address.
     *
     * This function emits an {Approval} event as part of {ERC20Upgradeable._approve}.
     * This function emits a {Transfer} event as part of {ERC20Upgradeable._transfer}.
     *
     * @dev Calling Conditions:
     *
     * - {CoboERC20} is not paused.
     * - The `from` is allowed to send tokens. (checked internally by {_requireAccess})
     * - The `to` is allowed to receive tokens. (checked internally by {_requireAccess})
     * - `from` is a non-zero address. (checked internally by {ERC20Upgradeable}.{_transfer})
     * - `to` is a non-zero address. (checked internally by {ERC20Upgradeable}.{_transfer})
     * - `amount` is not greater than `from`'s balance or caller's allowance of `from`'s funds. (checked internally
     *   by {ERC20Upgradeable}.{transferFrom})
     * - `amount` is greater than 0. (checked internally by {_spendAllowance})
     *
     * @param from The address that tokens will be transferred on behalf of.
     * @param to The address that will receive the tokens.
     * @param amount The number of tokens that will be sent to the `to` address.
     * @return True if the function was successful.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override whenNotPaused returns (bool) {
        _requireAccess(_msgSender());
        _requireAccess(from);
        _requireAccess(to);

        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice This is a function used to get the version of the contract.
     * @dev This function get the latest deployment version from the {Initializable}.{_getInitializedVersion}.
     * With every new deployment, the version number will be incremented.
     * @return The version of the contract.
     */
    function version() external view virtual returns (uint64) {
        return uint64(super._getInitializedVersion());
    }

    /**
     * @notice This is a function used to check if an interface is supported by this contract.
     * @dev This function returns `true` if the interface is supported, otherwise it returns `false`.
     * @return `true` if the interface is supported, otherwise it returns `false`.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId ||
            interfaceId == type(IERC1967).interfaceId ||
            interfaceId == type(IERC1822Proxiable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice Returns the number of decimals used to get its user representation.
     *         For example, if `decimals` equals `2`, a balance of `505` tokens should
     *         be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     *         NOTE: This information is only used for _display_ purposes: it in
     *         no way affects any of the arithmetic of the contract.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the address of the underlying ERC-20 token that is being wrapped.
     */
    function underlying() public view returns (IERC20) {
        return _underlying;
    }

    /**
     * @dev Allow a user to deposit underlying tokens and mint the corresponding number of wrapped tokens.
     */
    function deposit(uint256 value) public virtual whenNotPaused onlyRole(WRAPPER_ROLE) returns (bool) {
        address sender = _msgSender();
        IERC20(_underlying).safeTransferFrom(sender, address(this), value);
        _mint(sender, value);
        emit Deposit(sender, value);
        return true;
    }

    /**
     * @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
     */
    function withdraw(uint256 value) public virtual whenNotPaused onlyRole(WRAPPER_ROLE) returns (bool) {
        address sender = _msgSender();
        _burn(sender, value);
        IERC20(_underlying).safeTransfer(sender, value);
        emit Withdrawal(sender, value);
        return true;
    }

    /**
     * @notice A function used to salvage ERC20 tokens sent to the contract using this abstract contract.
     *
     * @dev Calling Conditions:
     *
     * - The `token` must not be the same as the underlying token.
     * - The `amount` must be greater than 0.
     *
     * This function emits a {TokenSalvaged} event, indicating that funds were salvaged.
     *
     * @param token The ERC20 asset which is to be salvaged. (must not be the same as the underlying token)
     * @param amount The amount to be salvaged.
     */
    function salvageERC20(IERC20 token, uint256 amount) external virtual override {
        if (token == _underlying) {
            revert ERC20InvalidSalvage();
        }
        if (amount == 0) {
            revert LibErrors.ZeroAmount();
        }
        _authorizeSalvage();
        token.safeTransfer(_msgSender(), amount);
        emit TokenSalvaged(_msgSender(), address(token), amount);
    }

    /**
     * @notice This is a function that applies any validations required to allow upgrade operations.
     *
     * @dev Reverts when the caller does not have the "UPGRADER_ROLE".
     *
     * Calling Conditions:
     *
     * - Only the "UPGRADER_ROLE" can execute.
     *
     * @param newImplementation The address of the new logic contract.
     */
    /* solhint-disable no-empty-blocks */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice This is a function that applies any validations required to allow salvage operations
     *
     * @dev Reverts when the caller does not have the "SALVAGER_ROLE".
     *
     * Calling Conditions:
     *
     * - Only the "SALVAGER_ROLE" can execute.
     */
    /* solhint-disable no-empty-blocks */
    function _authorizeSalvage() internal virtual override onlyRole(SALVAGER_ROLE) {}

    /**
     * @notice This is a function that applies any validations required to allow Contract Uri updates.
     *
     * @dev Reverts when the caller does not have the "MANAGER_ROLE".
     *
     * Calling Conditions:
     *
     * - Only the "MANAGER_ROLE" can execute.
     */
    /* solhint-disable no-empty-blocks */
    function _authorizeContractUriUpdate() internal virtual override onlyRole(MANAGER_ROLE) {}

    /**
     * @notice This is a function that applies any validations required to allow pause operations to be executed.
     *
     * @dev Reverts when the caller does not have the "PAUSER_ROLE".
     *
     * Calling Conditions:
     *
     * - Only the "PAUSER_ROLE" can execute.
     */
    /* solhint-disable no-empty-blocks */
    function _authorizePause() internal virtual override onlyRole(PAUSER_ROLE) {}

    /**
     * @notice This is a function that applies any validations required to allow unpause operations to be executed.
     *
     * @dev Reverts when the caller does not have the "MANAGER_ROLE".
     *
     * Calling Conditions:
     *
     * - Only the "MANAGER_ROLE" can execute.
     */
    function _authorizeUnpause() internal virtual override onlyRole(MANAGER_ROLE) {}

    /**
     * @notice This is a function that applies any validations required to allow access list operations to be executed.
     *
     * @dev Reverts when the caller does not have the "MANAGER_ROLE".
     *
     * Calling Conditions:
     *
     * - Only the "MANAGER_ROLE" can execute.
     */
    function _authorizeAccessList() internal virtual override onlyRole(MANAGER_ROLE) {}

    /**
     * @notice This is a function that applies any validations required to allow block list operations to be executed.
     *
     * @dev Reverts when the caller does not have the "MANAGER_ROLE".
     *
     * Calling Conditions:
     *
     * - Only the "MANAGER_ROLE" can execute.
     */
    function _authorizeBlockList() internal virtual override onlyRole(MANAGER_ROLE) {}

    /**
     * @notice This is a function that checks if the specified address is in the access list or block list.
     *
     * @dev Reverts when the address is in the block list.
     *
     * @param account The address to check.
     */
    function _requireAccess(address account) internal view virtual {
        if (accessListEnabled) {
            if (!_accessList.contains(account)) revert LibErrors.NotAccessListAddress(account);
        }

        if (_blockList.contains(account)) revert LibErrors.BlockedAddress(account);
    }

    /**
     * @dev Mint wrapped token to cover any underlyingTokens that would have been transferred by mistake or acquired from
     * rebasing mechanisms. Internal function that can be exposed with access control if desired.
     */
    function _recover(address account) internal virtual returns (uint256) {
        uint256 value = IERC20(_underlying).balanceOf(address(this)) - totalSupply();
        _mint(account, value);
        return value;
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    ///      variables without shifting down storage in the inheritance chain.
    ///      See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;
}

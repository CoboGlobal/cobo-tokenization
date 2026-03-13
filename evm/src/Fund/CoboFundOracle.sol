// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LibFundErrors} from "./libraries/LibFundErrors.sol";

/// @notice Minimal interface for NAV oracle consumers.
interface ICoboFundOracle {
    /// @notice Returns the latest interpolated NAV per share (1e18 precision).
    function getLatestPrice() external view returns (uint256);
}

/// @title CoboFundOracle - NAV pricing engine using APR-based linear interpolation.
/// @author Cobo Safe Dev Team https://www.cobo.com/
/// @notice Core formula: NAV(t) = baseNetValue + baseNetValue * currentAPR * (t - lastUpdateTimestamp) / (365 days * 1e18)
/// @dev APR is always >= 0 (uint256), so NAV can only increase or stay flat.
///      Off-chain correction adjusts future APR (potentially to 0) to converge with observed NAV.
contract CoboFundOracle is
    Initializable,
    AccessControlEnumerableUpgradeable,
    MulticallUpgradeable,
    UUPSUpgradeable,
    ICoboFundOracle
{
    using SafeERC20 for IERC20;

    // ─── Constants ──────────────────────────────────────────────────────

    /// @notice Contract version for upgrade tracking.
    uint64 public constant VERSION = 1;

    /// @notice Role for addresses authorized to call updateRate.
    bytes32 public constant NAV_UPDATER_ROLE = keccak256("NAV_UPDATER_ROLE");

    /// @notice Role for addresses authorized to perform UUPS upgrades.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 private constant _SECONDS_PER_YEAR = 365 days;
    uint256 private constant _PRECISION = 1e18;

    // ─── State Variables ────────────────────────────────────────────────

    /// @notice Current period base net value (1e18 precision).
    uint256 public baseNetValue;

    /// @notice Current APR (1e18 precision, e.g. 5e16 = 5%).
    uint256 public currentAPR;

    /// @notice Timestamp when the current period started.
    uint256 public lastUpdateTimestamp;

    /// @notice Maximum allowed APR (1e18 precision).
    uint256 public maxAPR;

    /// @notice Maximum allowed APR change per single update (1e18 precision).
    uint256 public maxAprDelta;

    /// @notice Minimum interval (seconds) between rate updates.
    uint256 public minUpdateInterval;

    /// @dev Monotonically increasing update counter.
    uint256 private _updateId;

    // ─── Events ─────────────────────────────────────────────────────────

    event NavUpdated(
        uint256 indexed updateId,
        uint256 newBase,
        uint256 newAPR,
        uint256 timestamp,
        string metadata,
        address updater
    );
    event WhitelistUpdated(address indexed account, bool allowed);
    event MaxAPRUpdated(uint256 maxAPR);
    event MaxAprDeltaUpdated(uint256 maxAprDelta);
    event MinUpdateIntervalUpdated(uint256 minUpdateInterval);
    event RescueToken(address indexed token, address to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─── Initializer ────────────────────────────────────────────────────

    /// @notice Initialize the oracle with initial parameters.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param initialNetValue Initial base net value (1e18 precision, must be > 0).
    /// @param initialAPR Initial APR (1e18 precision, must be <= _maxAPR).
    /// @param _maxAPR Maximum allowed APR.
    /// @param _maxAprDelta Maximum allowed APR change per update.
    /// @param _minUpdateInterval Minimum seconds between updates.
    function initialize(
        address admin,
        uint256 initialNetValue,
        uint256 initialAPR,
        uint256 _maxAPR,
        uint256 _maxAprDelta,
        uint256 _minUpdateInterval
    ) external initializer {
        if (admin == address(0)) revert LibFundErrors.ZeroAddress();
        if (initialNetValue == 0) revert LibFundErrors.ZeroNetValue();
        if (initialAPR > _maxAPR) revert LibFundErrors.APRExceedsMax(initialAPR, _maxAPR);

        __AccessControlEnumerable_init();
        __Multicall_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        baseNetValue = initialNetValue;
        currentAPR = initialAPR;
        lastUpdateTimestamp = block.timestamp;
        maxAPR = _maxAPR;
        maxAprDelta = _maxAprDelta;
        minUpdateInterval = _minUpdateInterval;
    }

    // ─── NAV Query (public view) ────────────────────────────────────────

    /// @inheritdoc ICoboFundOracle
    function getLatestPrice() public view override returns (uint256) {
        uint256 elapsed = block.timestamp - lastUpdateTimestamp;
        // Multiply before divide to preserve precision; use mulDiv to prevent intermediate overflow.
        // growth = baseNetValue * currentAPR * elapsed / (_PRECISION * _SECONDS_PER_YEAR)
        uint256 growth = Math.mulDiv(baseNetValue * currentAPR, elapsed, _PRECISION * _SECONDS_PER_YEAR);
        return baseNetValue + growth;
    }

    // ─── NAV Update (NAV_UPDATER_ROLE only) ─────────────────────────────

    /// @notice Submit a new APR for the next period.
    /// @dev Solidifies current interpolated NAV as new baseNetValue, then sets new APR.
    /// @param newAPR New APR value (1e18 precision).
    /// @param metadata Off-chain reference (e.g., IPFS hash, date string).
    function updateRate(uint256 newAPR, string calldata metadata) external onlyRole(NAV_UPDATER_ROLE) {
        uint256 elapsed = block.timestamp - lastUpdateTimestamp;
        if (elapsed < minUpdateInterval) {
            revert LibFundErrors.UpdateTooFrequent(elapsed, minUpdateInterval);
        }
        if (newAPR > maxAPR) {
            revert LibFundErrors.APRExceedsMax(newAPR, maxAPR);
        }

        uint256 delta = newAPR > currentAPR ? newAPR - currentAPR : currentAPR - newAPR;
        if (delta > maxAprDelta) {
            revert LibFundErrors.APRDeltaExceedsMax(delta, maxAprDelta);
        }

        // Solidify current interpolated NAV as new base
        baseNetValue = getLatestPrice();
        lastUpdateTimestamp = block.timestamp;
        currentAPR = newAPR;

        _updateId++;
        emit NavUpdated(_updateId, baseNetValue, newAPR, block.timestamp, metadata, msg.sender);
    }

    // ─── Configuration (DEFAULT_ADMIN_ROLE only) ────────────────────────

    /// @notice Set maximum allowed APR.
    function setMaxAPR(uint256 _maxAPR) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxAPR < currentAPR) revert LibFundErrors.APRExceedsMax(currentAPR, _maxAPR);
        maxAPR = _maxAPR;
        emit MaxAPRUpdated(_maxAPR);
    }

    /// @notice Set maximum allowed APR change per single update.
    function setMaxAprDelta(uint256 _maxAprDelta) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxAprDelta = _maxAprDelta;
        emit MaxAprDeltaUpdated(_maxAprDelta);
    }

    /// @notice Set minimum interval between rate updates.
    function setMinUpdateInterval(uint256 _minUpdateInterval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minUpdateInterval = _minUpdateInterval;
        emit MinUpdateIntervalUpdated(_minUpdateInterval);
    }

    // ─── Whitelist Management (Cobo Guard compatibility) ─────────────────

    /// @notice Grant or revoke NAV_UPDATER_ROLE via a convenience wrapper.
    /// @dev Preserves setWhitelist(addr, bool) signature for Cobo Guard calldata signing.
    function setWhitelist(address account, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert LibFundErrors.ZeroAddress();
        if (allowed) {
            _grantRole(NAV_UPDATER_ROLE, account);
        } else {
            _revokeRole(NAV_UPDATER_ROLE, account);
        }
        emit WhitelistUpdated(account, allowed);
    }

    /// @notice Check if an address has NAV_UPDATER_ROLE.
    /// @dev Backward-compatible view matching mock's `whitelist(address)` getter.
    function whitelist(address account) external view returns (bool) {
        return hasRole(NAV_UPDATER_ROLE, account);
    }

    // ─── Admin Self-Protection ──────────────────────────────────────────

    /// @dev Prevents revoking the last DEFAULT_ADMIN_ROLE holder.
    function revokeRole(bytes32 role, address account) public override(AccessControlUpgradeable, IAccessControl) {
        if (
            role == DEFAULT_ADMIN_ROLE &&
            hasRole(DEFAULT_ADMIN_ROLE, account) &&
            getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1
        ) {
            revert LibFundErrors.LastAdminCannotBeRevoked();
        }
        super.revokeRole(role, account);
    }

    /// @dev Prevents renouncing the last DEFAULT_ADMIN_ROLE.
    function renounceRole(bytes32 role, address account) public override(AccessControlUpgradeable, IAccessControl) {
        if (role == DEFAULT_ADMIN_ROLE && getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1) {
            revert LibFundErrors.LastAdminCannotBeRevoked();
        }
        super.renounceRole(role, account);
    }

    // ─── Asset Rescue ───────────────────────────────────────────────────

    /// @notice Rescue accidentally sent ERC20 tokens.
    function rescueERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert LibFundErrors.ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit RescueToken(token, to, amount);
    }

    // ─── Version ────────────────────────────────────────────────────────

    /// @notice Returns the initialized version of the contract.
    function version() external view returns (uint64) {
        return uint64(_getInitializedVersion());
    }

    // ─── UUPS Upgrade Authorization ─────────────────────────────────────

    /* solhint-disable no-empty-blocks */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // ─── Storage Gap ────────────────────────────────────────────────────

    /// @dev Reserved storage for future upgrades.
    uint256[50] private __gap;
}

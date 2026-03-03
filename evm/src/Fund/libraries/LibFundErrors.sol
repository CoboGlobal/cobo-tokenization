// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

/// @title LibFundErrors - Centralized custom errors for Fund contracts.
/// @author Cobo Safe Dev Team https://www.cobo.com/
library LibFundErrors {
    // ──────────────────── Common ────────────────────
    error ZeroAddress();
    error ZeroAmount();

    // ──────────────────── FundOracle ─────────────────
    error ZeroNetValue();
    error APRExceedsMax(uint256 apr, uint256 maxAPR);
    error APRDeltaExceedsMax(uint256 delta, uint256 maxAprDelta);
    error UpdateTooFrequent(uint256 elapsed, uint256 minInterval);
    error IntervalTooLarge(uint256 interval, uint256 maxInterval);

    // ──────────────────── FundToken ───────────────────
    error NotWhitelisted(address account);
    error BelowMinDeposit(uint256 amount, uint256 minDeposit);
    error BelowMinRedeem(uint256 shares, uint256 minRedeem);
    error ZeroShares();
    error ZeroAssetAmount();
    error InsufficientBalance(address user, uint256 requested, uint256 available);
    error InvalidRedemptionRequest(uint256 reqId);
    error RedemptionNotPending(uint256 reqId);
    error RedemptionParamMismatch(uint256 reqId);
    error CannotRescueCoreAsset(address token);

    // ──────────────────── FundVault ──────────────────
    error SystemPaused();
    error NotInVaultWhitelist(address to);

    // ──────────────────── AccessControl ─────────────
    error LastAdminCannotBeRevoked();
}

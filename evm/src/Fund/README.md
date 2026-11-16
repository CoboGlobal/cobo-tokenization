# Cobo Fund Tokenization

A NAV-based fund contract suite with ERC20 share tokens, APR-based NAV accrual, asynchronous redemption, and a custody vault. Contracts use OpenZeppelin role-based access control and UUPS upgrades.

## Contracts

| Contract | Responsibility |
|----------|----------------|
| [CoboFundOracle](CoboFundOracle.sol) | Calculates NAV from a base value, APR, and elapsed time; bounds rate updates |
| [CoboFundToken](CoboFundToken.sol) | Issues fund shares, records redemption requests, and manages investor eligibility |
| [CoboFundVault](CoboFundVault.sol) | Holds the underlying ERC20 asset and supports restricted settlement transfers |
| [ISanctionsOracle](../interfaces/ISanctionsOracle.sol) | Shared interface for optional external address screening |

## Asset and Share Flow

- An eligible investor approves the FundToken proxy to spend the underlying asset and calls `mint`. The asset moves directly to the vault, and the investor receives shares priced at the current NAV.
- `requestRedemption` burns shares and records a pending claim at the NAV at request time. Approval pays the recorded asset amount from the vault; rejection restores the recorded shares.
- The vault approves FundToken to transfer the underlying asset for redemption payments. Settlement withdrawals require both the settlement operator role and an approved recipient.
- The investor whitelist controls deposits and redemption requests; it does not restrict ordinary share transfers. Approval also requires the investor to remain whitelisted. Rejection does not require whitelist membership.

NAV uses `1e18` precision and represents underlying asset units per share:

```text
NAV(t) = baseNetValue + baseNetValue * currentAPR * (t - lastUpdateTimestamp) / (365 days * 1e18)
```

APR is non-negative. Updating APR crystallizes accrued NAV and changes the subsequent rate, subject to the configured maximum APR, maximum rate change, and minimum update interval. Asset amounts and share amounts use their respective token decimals.

## Roles and Privileged Operations

| Contract | Roles |
|----------|-------|
| `CoboFundOracle` | `DEFAULT_ADMIN_ROLE`, `NAV_UPDATER_ROLE`, `UPGRADER_ROLE` |
| `CoboFundToken` | `DEFAULT_ADMIN_ROLE`, `MANAGER_ROLE`, `REDEMPTION_APPROVER_ROLE`, `EMERGENCY_GUARDIAN_ROLE`, `UPGRADER_ROLE` |
| `CoboFundVault` | `DEFAULT_ADMIN_ROLE`, `SETTLEMENT_OPERATOR_ROLE`, `UPGRADER_ROLE` |

Administrators manage role assignments and contract settings. Initialization grants the administrator role only; it does not automatically assign the operational roles. Managers maintain the investor whitelist, redemption approvers settle or reject claims, and settlement operators withdraw to approved recipients. Upgraders authorize implementation changes.

FundToken can be paused by its administrator or emergency guardian, but only the administrator can unpause it. The vault checks FundToken's pause state before settlement withdrawals.

**Administrator forfeiture powers:** `forceRedeem` burns a holder's shares without an asset payout and bypasses screening and pause checks. `adminForfeitPending` permanently releases a pending redemption claim without paying assets or restoring shares; assets remain in the vault. These are privileged forfeiture operations, not ordinary redemptions.

## Optional Address Screening

The administrator configures `CoboFundToken.sanctionsOracle`; the vault reads the same setting. The interface is `ISanctionsOracle.isSanctioned(address)`.

| Operation | Screened addresses |
|-----------|--------------------|
| `mint`, `requestRedemption` | Caller |
| `approveRedemption`, `rejectRedemption` | Investor recorded in the claim |
| `transfer`, `transferFrom` | Share sender and recipient |
| Vault `withdraw` | Settlement recipient |

A zero oracle address disables screening. Non-zero candidates are probed for a callable interface, but that probe does not establish that their answers are correct. A configured oracle that reverts blocks screened operations. Screening depends on the external oracle and on administrators who can replace or disable it; it is not identity verification or a guarantee of regulatory compliance. Administrator forfeiture operations are not subject to these checks.

## Deployment Information

Published implementation addresses and explorer links are listed in the [repository README](../../../README.md#logic-contracts). They are implementation addresses, not initialized fund products, and need not match bytecode compiled from the current source revision.

Each fund product uses three initialized proxies connected to the oracle, share token, and vault implementations. Implementations are not initialized directly. NAV, APR, the underlying asset, share parameters, and role assignments belong to product configuration, not implementation deployment.

The source scripts are in [script/Fund](../../script/Fund): implementation deployment, product proxy creation, and role configuration are separate concerns. `DeployMockERC20.s.sol` supplies test assets only.

## Testing

From `evm/`:

```bash
forge test --match-path 'test/Fund/*'
```

The Fund tests cover contract behavior, numerical precision, integration, security, screening, fuzzing, and upgrades. See [EVM README](../../README.md) for build configuration.

## License

LGPL-3.0-only.

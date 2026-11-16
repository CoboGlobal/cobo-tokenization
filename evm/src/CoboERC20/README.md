# Cobo ERC20 and Wrapper

Upgradeable ERC20 contracts with role-based permissions, transfer access lists, optional external address screening, and multicall support.

## Contracts

| Contract | Responsibility |
|----------|----------------|
| [CoboERC20](CoboERC20.sol) | ERC20 issuance and burning with designated roles |
| [CoboERC20Wrapper](CoboERC20Wrapper.sol) | Wraps an underlying ERC20 asset into matching token units |
| [AccessListUpgradeable](library/Utils/AccessListUpgradeable.sol) | Optional whitelist and blacklist checks |
| [ISanctionsOracle](../interfaces/ISanctionsOracle.sol) | Shared interface for external address screening |

## Token Behavior

`CoboERC20.mint(to, amount)` requires `MINTER_ROLE`. `burn(amount)` requires `BURNER_ROLE` and burns the caller's tokens. `burnFrom(account, amount)` requires `MANAGER_ROLE` and burns the specified account's tokens without an allowance from that account. Both burn operations bypass pause, access-list, and sanctions checks.

For `CoboERC20Wrapper`, `deposit(value)` transfers underlying tokens from the caller and issues the same number of wrapper units; `withdraw(value)` burns the caller's wrapper units and returns underlying tokens. Both require `WRAPPER_ROLE`, an unpaused contract, and a caller permitted by the configured sanctions oracle. Deposit requires an underlying-token allowance to the wrapper proxy. These two entry points do not apply the wrapper's own access-list checks; restrictions in the underlying asset can still reject a transfer.

The wrapper's `mint(to)` requires `MINTER_ROLE` and issues the positive difference between the underlying-token balance and wrapper supply. It is not an unrestricted amount-based mint. There is no separate public `burn` or `burnFrom` entry point on the wrapper.

## Roles

| Role | CoboERC20 | CoboERC20Wrapper |
|------|-----------|------------------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke roles and configure the sanctions oracle | Same |
| `MINTER_ROLE` | Mint a specified amount | Mint underlying balance surplus |
| `BURNER_ROLE` | Burn caller's tokens | Not used |
| `WRAPPER_ROLE` | Not used | Deposit and withdraw underlying tokens |
| `MANAGER_ROLE` | Burn from accounts, unpause, manage access lists and metadata | Unpause, manage access lists and metadata |
| `PAUSER_ROLE` | Pause | Pause |
| `UPGRADER_ROLE` | Authorize UUPS upgrades | Same |
| `SALVAGER_ROLE` | Recover native currency and ERC20 tokens | Recover native currency and ERC20 tokens other than the underlying asset |

Each contract has seven roles. Initialization grants only `DEFAULT_ADMIN_ROLE`; other permissions must be assigned separately. Administrator status does not directly bypass operational role checks. An authorized upgrade can change contract behavior.

Pause restricts minting and transfers, and wrapper deposits and withdrawals. It does not freeze every contract function: approvals, role management, and other administrative functions remain available, as do the ERC20 burn operations described above.

## Access Lists and Optional Screening

Whitelist enforcement is disabled by default. Where access-list checks apply, blacklisted addresses are rejected, and enabling the whitelist also requires membership. A whitelist entry does not override a blacklist entry.

`CoboERC20` and `CoboERC20Wrapper` apply both access-list and configured sanctions checks to the mint recipient, both parties of `transfer`, and the caller, sender, and recipient of `transferFrom`. Wrapper deposits and withdrawals apply sanctions checks to the caller as described above.

The `DEFAULT_ADMIN_ROLE` can set, replace, or clear `sanctionsOracle`. A zero address disables sanctions queries without disabling access-list checks; new instances have no oracle configured. A non-zero candidate is probed for a callable `isSanctioned(address)` interface, but the returned value is ignored and does not establish data accuracy. A configured oracle that reverts blocks screened operations; there is no automatic fallback that ignores errors.

Address screening is not identity verification or a guarantee of regulatory compliance. Its behavior depends on the external oracle and administrators who can replace or disable it. ERC20 burn operations intentionally bypass screening and retain their role restrictions.

## Deployment Information

Published addresses and block explorer links are listed in the [repository README](../../../README.md). The token and wrapper use UUPS implementations behind initialized proxies; implementation addresses are not product token addresses. The current source revision may differ from a published implementation.

Deployment scripts are located in [script/CoboERC20](../../script/CoboERC20). Proxy initialization and implementation deployment are separate concepts; proxy creation and initialization must occur atomically, and implementations are not initialized directly.

## Build and Tests

See [EVM README](../../README.md) for shared build configuration and test commands. The test suite includes token behavior, screening, and upgrade coverage for both contracts.

## License

LGPL-3.0-only.

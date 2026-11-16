# Cobo Tokenization EVM Contracts

Upgradeable Solidity contracts for ERC20 tokens, wrapped assets, and NAV-based fund shares, built with Foundry and OpenZeppelin Contracts.

## Modules

| Module | Contracts | Description |
|--------|-----------|-------------|
| [ERC20 and Wrapper](src/CoboERC20/README.md) | `CoboERC20`, `CoboERC20Wrapper` | Role-controlled tokens and ERC20 asset wrapping |
| [Fund](src/Fund/README.md) | `CoboFundOracle`, `CoboFundToken`, `CoboFundVault` | NAV pricing, fund shares, asynchronous redemption, and asset custody |

## Source Layout

```text
src/
├── CoboERC20/       # Token, wrapper, access lists, and error definitions
├── Fund/           # Fund oracle, share token, and vault
├── interfaces/     # Shared sanctions screening interface
└── deploy/         # Proxy factory
script/
├── CoboERC20/      # ERC20 implementation scripts
└── Fund/           # Fund implementation and product scripts
test/               # Unit, integration, security, and upgrade tests
```

## Build and Test

[Foundry](https://getfoundry.sh/) is required. Run commands from `evm/` with dependencies matching [foundry.lock](foundry.lock). Dependency versions affect compiled bytecode; do not substitute newer versions when reproducing an existing release.

```bash
forge build
forge test
```

Build configuration is defined in [foundry.toml](foundry.toml): Solidity `0.8.23`, EVM `london`, optimizer enabled with `20000` runs, and `via_ir = true`.

## Deployed Contracts

See the [repository contract address list](../README.md) for networks, published addresses, and block explorer links. Module documentation describes the source in this checkout; a published implementation can represent a different source revision.

EVM contracts use UUPS upgradeable implementations behind proxies. An implementation address is not a product token address. Interactions with an initialized token or fund use its proxy address. Implementation constructors disable initialization; proxy deployment and initialization must be atomic.

## Security Model

Permissions are role-based. Administrators can grant and revoke roles; designated roles can mint, burn, pause, recover assets, or authorize upgrades according to the module. An upgrade can change contract behavior.

Optional address screening uses [ISanctionsOracle](src/interfaces/ISanctionsOracle.sol). It is not identity verification or a guarantee of regulatory compliance. Screening behavior, privileged exceptions, and oracle trust assumptions are documented in each module.

## License

LGPL-3.0-only. See [LICENSE.txt](../LICENSE.txt).

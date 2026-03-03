# Cobo ERC20 Tokenization

A sophisticated, upgradeable ERC20 token implementation with role-based access control, built using the Foundry framework and OpenZeppelin's upgradeable contracts.

## 🌟 Features

### Core Token Functionality
- **ERC20 Standard**: Full compliance with ERC20 token standard
- **Upgradeable**: UUPS (Universal Upgradeable Proxy Standard) implementation
- **Multicall Support**: Batch multiple function calls in a single transaction

### Access Control & Security
- **Role-Based Access Control**: Six distinct roles with specific permissions:
  - `DEFAULT_ADMIN_ROLE`: Full administrative control
  - `MINTER_ROLE`: Token minting permissions
  - `BURNER_ROLE`: Token burning permissions
  - `MANAGER_ROLE`: Contract management and token burning from any address
  - `PAUSER_ROLE`: Emergency pause functionality
  - `UPGRADER_ROLE`: Contract upgrade permissions
  - `SALVAGER_ROLE`: Asset recovery capabilities

### Advanced Features
- **Pause/Unpause**: Emergency stop mechanism
- **Access List Control**: Whitelist/blacklist functionality for transfers
- **Asset Salvage**: Recovery of accidentally sent tokens or ETH
- **Contract URI**: Metadata support for contract information

## 🏗️ Architecture

The project uses a modular architecture with the following components:

```
src/
├── CoboERC20/
│   ├── CoboERC20.sol          # Main token contract
│   └── library/
│       ├── Utils/             # Utility contracts
│       └── Errors/            # Error definitions
├── deploy/
    └── ProxyFactory.sol       # Deployment factory
```

## 🔧 Setup

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed
- Node.js and npm (optional, for additional tooling)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd CoboTokenization
   ```

2. **Install dependencies**
   ```bash
   forge install OpenZeppelin/openzeppelin-contracts@v5.3.0 --no-git --shallow
   forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.3.0 --no-git --shallow
   forge install foundry-rs/forge-std --no-git --shallow
   ```

3. **Build the project**
   ```bash
   forge build
   ```

## 🧪 Testing

Run the test suite:
```bash
forge test
```

For verbose output:
```bash
forge test -vvv
```

## 🚀 Deployment

### Manual Deployment

You can also deploy manually by following these steps:

1. Deploy the implementation contract
2. Deploy a proxy pointing to the implementation
3. Initialize the contract with required parameters

### Initialization Parameters

When initializing the contract, provide:
- `name`: Token name (e.g., "CoboERC20")
- `symbol`: Token symbol (e.g., "COBO")
- `uri`: Contract metadata URI
- `decimal`: Token decimal
- `admin`: Initial admin address (receives DEFAULT_ADMIN_ROLE)

## 📋 Usage

### Basic Token Operations

```solidity
// Mint tokens (requires MINTER_ROLE)
coboToken.mint(recipient, amount);

// Burn tokens (requires BURNER_ROLE)
coboToken.burn(amount);

// Burn tokens from specific address (requires MANAGER_ROLE)
coboToken.burnFrom(account, amount);
```

### Access Control

```solidity
// Grant roles (requires DEFAULT_ADMIN_ROLE)
coboToken.grantRole(MINTER_ROLE, minterAddress);

// Check role membership
bool isMinter = coboToken.hasRole(MINTER_ROLE, address);

// Revoke roles
coboToken.revokeRole(MINTER_ROLE, address);
```

### Emergency Controls

```solidity
// Pause the contract (requires PAUSER_ROLE)
coboToken.pause();

// Unpause the contract (requires MANAGER_ROLE)
coboToken.unpause();
```

## 🔐 Security Features

### Role Permissions Matrix

| Role | Mint | Burn Self | Burn Others | Pause | Unpause | Upgrade | Manage Access List | Salvage |
|------|------|-----------|-------------|-------|---------|---------|-------------------|---------|
| MINTER_ROLE | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| BURNER_ROLE | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| MANAGER_ROLE | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ |
| PAUSER_ROLE | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| UPGRADER_ROLE | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| SALVAGER_ROLE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| DEFAULT_ADMIN_ROLE | Grant/Revoke all roles | | | | | | | |

### Access List Control
- Configure allowed/denied addresses for transfers
- Granular control over who can send/receive tokens
- Useful for compliance and regulatory requirements

## ⚙️ Configuration

### Foundry Configuration

The project is configured with:
- Solidity version: 0.8.23
- EVM version: London
- Optimizer: Enabled with 20,000 runs
- IR optimization: Enabled

### Contract Configuration

Key contract settings:
- Upgradeable using UUPS pattern
- Initializer-based setup
- Comprehensive role-based access control

## 🔍 Verification

After deployment, verify your contracts on block explorers:

```bash
forge verify-contract <CONTRACT_ADDRESS> src/CoboERC20/CoboERC20.sol:CoboERC20 --etherscan-api-key <API_KEY>
```

## 📄 License

This project is licensed under LGPL-3.0-only.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📞 Support

For questions or support, please contact the Cobo development team at [https://www.cobo.com/](https://www.cobo.com/).

---

Built with ❤️ by the Cobo team

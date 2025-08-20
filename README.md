Pump.fun-style Bonding Curve dApp (EVM)

A decentralized application (dApp) that implements a bonding curve token launch mechanism on EVM-compatible chains (Ethereum, Base, Arbitrum, etc.).

Inspired by pump.fun on Solana, this project allows users to buy and sell tokens directly from the bonding curve, gradually increasing token prices until a defined threshold is reached — after which the liquidity is migrated to a DEX like Uniswap V2 automatically.

🚀 Features

Bonding Curve Pricing
Implements an automated token pricing model using a constant product formula:
```
vTOKEN * vETH = k
```

Token Launch
Deploys an ERC20 token and launches it directly on the bonding curve.

Dynamic Pricing
The token price increases automatically as tokens are purchased.

Migration to Uniswap
At ~80% sold allocation, tokens & collateral migrate to Uniswap V2 liquidity pool.

Fee Deduction
Migration fees deducted automatically for pool creation and protocol fee.

Upgradeable Contract Architecture (optional)
Future-ready design for protocol updates.


📜 Bonding Curve Overview

This dApp uses a virtual reserves-based constant product formula to control price dynamics:
```
vTOKEN * vETH = k
```
Where:

. vTOKEN → Virtual reserve of tokens

. vETH → Virtual reserve of collateral (ETH or chain native token)

. k → Constant that defines curve shape

Initial Parameters

| Parameter           | Value                  |
| ------------------- | ---------------------- |
| Total Supply (T)    | `1,000,000,000` tokens |
| Initial Price       | `1 gwei`               |
| Initial vTOKEN      | `1.06 * 10^27`         |
| Initial vETH        | `1.6 * 10^18`          |
| Migration Threshold | `~80%` sold            |
| Migration Fee (F)   | `0.15 ETH`             |



⚡ How It Works
1. Token Deployment

Deploy ERC20 token with 18 decimals.

Initialize bonding curve contract with initial virtual reserves.

2. Buying Tokens

Users call buyTokens() with ETH.

Contract calculates amount of tokens to dispense based on new price from bonding curve.

3. Selling Tokens

Users call sellTokens() to return tokens.

Contract refunds ETH based on inverse curve formula.

4. Migration to Uniswap

When ~80% tokens are sold:

Remaining tokens & ETH collateral migrate to a Uniswap V2 pool.

Curve trading stops, and trading continues on DEX.


🛠️ Tech Stack

Smart Contracts → Solidity ^0.8.20

Framework → Foundry (recommended) or Hardhat

Frontend → React + Next.js (optional for later)

DEX Integration → Uniswap V2 Router


📂 Project Structure

pump-curve-evm/
│── contracts/
│   ├── BondingCurve.sol        # Core bonding curve logic
│   ├── Token.sol               # ERC20 token
│   ├── UniswapMigrator.sol     # Handles migration to Uniswap
│
│── scripts/
│   ├── deploy.ts               # Deployment script
│   ├── simulate.ts             # Simulate price changes
│
│── test/
│   ├── BondingCurve.t.sol      # Unit tests
│   ├── Migration.t.sol         # Migration logic tests
│
│── frontend/                   # Optional React app
│
└── README.md

📦 Installation & Setup

1. Clone the Repository
```
git clone https://github.com/yourusername/pump-curve-evm.git
cd pump-curve-evm
```

2. Install Dependencies
```
npm install
```

3. Compile Contracts
```
forge build
# or
npx hardhat compile
```

4. Run Tests
```
forge test -vvvv
# or
npx hardhat test
```

🧠 Key Formulas

Token Price
```
price = vETH / vTOKEN
```

Tokens Bought
```
ΔTOKEN = vTOKEN - (k / (vETH + ETH_in))
```

Tokens Sold
```
ΔETH = vETH - (k / (vTOKEN + TOKEN_in))
```

🛤️ Roadmap

 Bonding curve buy/sell logic

 ERC20 token integration

 Uniswap V2 migration

 Frontend UI with Next.js

 Wallet integrations (MetaMask, WalletConnect)


🔒 Security

Uses reentrancy guards for buy/sell functions.

Ensures migration can only happen once.

Tested against common exploits.


📜 License

MIT License © 2025 [Packagefather]

🔗 References

[Pump.fun (Solana)](https://pump.fun) 

[Uniswap V2 Docs](https://uniswap.org)

[Foundry Book](https://getfoundry.sh/)
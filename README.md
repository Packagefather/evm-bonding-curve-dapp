Pump.fun-style Bonding Curve dApp (EVM)

[![Foundry CI](https://github.com/packagefather/evm-bonding-curve-dapp/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/packagefather/evm-bonding-curve-dapp/actions/workflows/test.yml)


A decentralized application (dApp) that implements a bonding curve token launch mechanism on EVM-compatible chains (Ethereum, Base, Arbitrum, etc.).

Inspired by pump.fun on Solana, this project allows users to buy and sell tokens directly from the bonding curve, gradually increasing token prices until a defined threshold is reached — after which the liquidity is migrated to a DEX like Uniswap V2 automatically.

🚀 Features

## **Core Features**

### **1. Bonding Curve Pricing**
Implements an **automated token pricing model** using the constant product formula:
```
vTOKEN * vETH = k
```


- **Dynamic price discovery** → Token price automatically adjusts based on demand.
- **Fair entry & exit points** → No manual intervention; the curve determines price.

---

### **2. Token Launch**
- Deploys a new **ERC20 token** directly from the **factory contract**.
- Immediately integrates the token with the bonding curve.
- Token allocation defined at creation — **e.g., 10 BNB → 20 BNB liquidity range**.

---

### **3. Dynamic Pricing**
- Token price **increases automatically** as tokens are purchased.
- Early buyers benefit from **cheaper entry prices**.
- Encourages **faster participation** due to increasing cost curve.

---

### **4. Migration to PancakeSwap**
- At **~80% token allocation sold**, remaining tokens + raised BNB **automatically migrate** to a **PancakeSwap V2 liquidity pool**.
- Liquidity tokens are **burned** to ensure **permanent liquidity locking**.

---

### **5. Fee Mechanisms**

#### **Platform & Trading Fees**
- **2% platform fee** on buys.
- **2% platform fee** on sells.
- **Separate wallets** handle:
  - Trading fees.
  - Migration fees.

#### **Referral System**
- **2% referral reward** from **every buyer’s** purchase.
- If no referral is provided, the **launcher** (token creator) receives the referral fee.
- Referral rewards are **claimable** by users — **not auto-transferred**.

---

### **6. Anti-Fraud Mechanism (AntiFud)**
- **30% antifud fee** applied under special protective scenarios.
- Collected antifud fee split:
  - **50% credited to the token launcher**.
  - **50% added to liquidity** to strengthen price stability.

---

### **7. Graduation Rewards**
Upon **migration completion**:
- **Launcher** receives **5% of total raised funds**.
- **Platform** receives **5% of total raised funds**.
- **90%+ of total raised funds** are added to **permanent liquidity**.
- If antifud fees were collected, **even more liquidity** gets added.

---

### **8. Liquidity Migration & Burn**
- Migrated liquidity is locked permanently:
  - Tokens and BNB are paired on **PancakeSwap V2**.
  - Liquidity pool (LP) tokens are **burned**.
- Ensures **rug-pull resistance** and **trustless liquidity locking**.

---

### **9. Event Emissions**
- Emit comprehensive events for:
  - Token launches.
  - Purchases.
  - Sells.
  - Migration.
  - Referral rewards.
  - Graduation rewards.
  - Top traders leaderboard.

---

### **10. Top Traders Leaderboard**
- Weekly tracking of **top traders** based on:
  - **Buy volumes**.
  - **Sell volumes**.
- Emit events to highlight active users and drive engagement.

---

### **11. Ownership & Permissions**
- **Factory contract** transfers ownership of the deployed token/curve **to the creator**.
- Creator can:
  - Retain control.
  - Or **renounce ownership** to make the token fully decentralized.

---

### **12. Claimable Rewards**
- **Referral rewards**, **launcher fees**, and **creator allocations** are:
  - **Stored in the contract**.
  - **Claimable** by users via explicit functions.
  - **Not auto-distributed**, reducing gas and increasing user control.

---

### **13. Upgradeable Contract Architecture (Optional)**
- Factory uses **OpenZeppelin’s Clones library** for efficient deployment.
- Future upgrades supported by:
  - **Versioned implementations**.
  - Existing clones remain unaffected.
- Enables smooth rollout of **new features** without disrupting old launches.

---

## **High-Level Flow**

1. **Creator** initiates a token launch via the **Factory**.
2. **Factory**:
   - Deploys a **new ERC20 token**.
   - Deploys a **Bonding Curve clone**.
   - Initializes it with token details and allocations.
3. Users **buy tokens** → **price increases** via bonding curve math.
4. **Referrals** and **fees** are processed in real time.
5. Upon reaching ~80% allocation:
   - Tokens + raised funds **migrate** to PancakeSwap V2.
   - LP tokens are **burned**.
6. Graduation rewards, platform fees, and launcher incentives become **claimable**.

---

## **Key Contract Components**

| **Component**        | **Responsibility**                               |
|----------------------|--------------------------------------------------|
| **Factory**          | Deploys tokens & bonding curves, handles ownership transfer. |
| **BondingCurve**     | Manages buy/sell pricing, fee deductions, antifud, and migration. |
| **Token (ERC20)**    | Newly deployed project token with integrated trading logic. |
| **Referral System**  | Tracks referrals, calculates claimable rewards. |
| **Leaderboard**      | Tracks and emits weekly top trader volumes. |

---

## **Summary**
This launchpad combines **bonding curve tokenomics**, **referral incentives**, **automated liquidity migration**, and **anti-fraud protections** into a single **scalable**, **upgradeable** ecosystem.




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
│   ├── BondingCurve.sol        # Core bonding curve logic implementation
│   ├── Token.sol               # ERC20 token
|   ├── Factory.sol             # Central point where curve implemetations are called from
│   ├── UniswapMigrator.sol     # Handles migration to Uniswap
│
│── scripts/
│   ├── DeployBondingCurve.s.sol               # Deployment script
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
 
 Factory contract to handle implementation deployments

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
# Fairs 代币部署指南

本文档详细说明如何在不同网络上部署 Fairs 代币合约。

## 目录

- [前置要求](#前置要求)
- [环境配置](#环境配置)
- [本地部署（Anvil）](#本地部署anvil)
- [测试网部署（Sepolia）](#测试网部署sepolia)
- [主网部署](#主网部署)
- [验证合约](#验证合约)
- [部署后检查](#部署后检查)

## 前置要求

### 1. 安装 Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. 安装依赖

```bash
forge install
```

### 3. 编译合约

```bash
forge build
```

## 环境配置

### 1. 创建环境变量文件

```bash
cp .env.example .env
```

### 2. 配置 .env 文件

编辑 `.env` 文件，填写以下信息：

```bash
# Sepolia 测试网
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
SEPOLIA_PRIVATE_KEY=0x... # 你的私钥
ORGANIZATION_ADDRESS=0x... # 组织地址

# Etherscan（用于验证）
ETHERSCAN_API_KEY=YOUR_API_KEY
```

⚠️ **安全提醒**：
- 永远不要将 `.env` 文件提交到 Git
- 不要在测试网使用主网私钥
- 妥善保管私钥

## 本地部署（Anvil）

### 1. 启动本地节点

```bash
anvil
```

### 2. 部署合约

在新终端中运行：

```bash
forge script script/DeployFairs.s.sol:DeployFairs --rpc-url http://localhost:8545 --broadcast -vvvv
```

### 3. 默认配置

Anvil 部署使用以下默认配置：
- **Buy Slope**: `1e15` (0.001 ETH per token)
- **Investment Ratio**: `3000` (30%)
- **Distribution Ratio**: `2000` (20%)
- **Organization Address**: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (Anvil 账户 #1)
- **Deployer**: Anvil 默认账户 #0

## 测试网部署（Sepolia）

### 1. 确保有测试 ETH

从水龙头获取 Sepolia ETH：
- https://sepoliafaucet.com/
- https://www.alchemy.com/faucets/ethereum-sepolia

### 2. 部署合约

```bash
forge script script/DeployFairs.s.sol:DeployFairs \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    -vvvv
```

### 3. 查看部署信息

部署成功后，控制台会显示：
```
========================================
Fairs Token Deployed Successfully!
========================================
Contract Address: 0x...
Chain ID: 11155111

Configuration:
- Buy Slope: 1000000000000000
- Investment Ratio: 3000 (basis points)
- Distribution Ratio: 2000 (basis points)
- Organization Address: 0x...

Token Info:
- Name: Fairs Token
- Symbol: FAIRS
- Decimals: 18
- Owner: 0x...
========================================
```

## 主网部署

⚠️ **主网部署前的重要检查**：

### 1. 安全检查清单

- [ ] 已完成代码审计
- [ ] 在测试网充分测试
- [ ] 确认所有参数正确
- [ ] 准备足够的 ETH（gas 费用）
- [ ] 组织地址正确无误
- [ ] 私钥安全存储

### 2. 配置主网参数

在 `.env` 中配置：

```bash
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
MAINNET_PRIVATE_KEY=0x...
ORGANIZATION_ADDRESS=0x...
MAINNET_BUY_SLOPE=1000000000000000
MAINNET_INVESTMENT_RATIO=3000
MAINNET_DISTRIBUTION_RATIO=2000
```

### 3. 部署到主网

```bash
forge script script/DeployFairs.s.sol:DeployFairs \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify \
    -vvvv
```

### 4. 多重签名建议

对于主网部署，建议：
- 使用硬件钱包
- 设置多重签名作为 owner
- 转移 ownership 到 Gnosis Safe

```solidity
// 部署后转移 ownership
fairs.transferOwnership(gnosisSafeAddress);
```

## 验证合约

### 自动验证（推荐）

部署时添加 `--verify` 标志会自动验证。

### 手动验证

```bash
forge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(uint256,uint16,uint16,address)" 1000000000000000 3000 2000 0x...) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.28 \
    0x... \  # 合约地址
    src/Fairs.sol:Fairs
```

## 部署后检查

### 1. 验证合约配置

```bash
# 检查购买斜率
cast call <CONTRACT_ADDRESS> "buySlope()" --rpc-url $SEPOLIA_RPC_URL

# 检查投资比例
cast call <CONTRACT_ADDRESS> "investmentRatio()" --rpc-url $SEPOLIA_RPC_URL

# 检查组织地址
cast call <CONTRACT_ADDRESS> "organizationAddress()" --rpc-url $SEPOLIA_RPC_URL

# 检查 owner
cast call <CONTRACT_ADDRESS> "owner()" --rpc-url $SEPOLIA_RPC_URL
```

### 2. 测试基本功能

```bash
# 测试购买（发送 0.01 ETH）
cast send <CONTRACT_ADDRESS> "buy()" \
    --value 0.01ether \
    --private-key $SEPOLIA_PRIVATE_KEY \
    --rpc-url $SEPOLIA_RPC_URL

# 检查余额
cast call <CONTRACT_ADDRESS> "balanceOf(address)(uint256)" <YOUR_ADDRESS> \
    --rpc-url $SEPOLIA_RPC_URL
```

### 3. 在 Etherscan 上验证

访问 Etherscan 查看：
- Sepolia: `https://sepolia.etherscan.io/address/<CONTRACT_ADDRESS>`
- Mainnet: `https://etherscan.io/address/<CONTRACT_ADDRESS>`

确认：
- ✅ 合约已验证
- ✅ 源代码可见
- ✅ 构造函数参数正确
- ✅ 能够进行读写操作

## 常见问题

### Q: 部署失败，提示 "insufficient funds"
A: 确保部署地址有足够的 ETH 支付 gas 费用。

### Q: 验证失败
A: 确保：
- Etherscan API key 正确
- 编译器版本匹配（0.8.28）
- 优化次数正确（200）
- 构造函数参数格式正确

### Q: 如何更新组织地址？
A: Fairs 合约当前不支持更新组织地址。如需更改，需要重新部署合约。

### Q: 如何估算 gas 成本？
A: 使用 Foundry 的 gas 报告：
```bash
forge test --gas-report
```

## 网络配置参考

### Sepolia 测试网
- Chain ID: 11155111
- Currency: ETH (测试币)
- Block Explorer: https://sepolia.etherscan.io

### Ethereum 主网
- Chain ID: 1
- Currency: ETH
- Block Explorer: https://etherscan.io

## 支持

如有问题，请：
1. 查看 Foundry 文档：https://book.getfoundry.sh/
2. 查看项目 README
3. 提交 GitHub Issue
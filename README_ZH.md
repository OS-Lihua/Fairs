## Fairs

本项目参考 [C-ORG 白皮书](https://github.com/C-ORG/whitepaper) 做的完整实现。

这是一个基于持续组织（Continuous Organizations）的 CSO（持续证券发行，Continuous Securities Offering）项目。

用户可以从 DAT(Decentralized Autonomous Trust，去中心化自治信托) 中购买 Fairs 代币来投资持续组织。

用户购买 Fairs 的曲线为 $B(x) = b \times x$ ( $b$ 在初始化时定义)。

用户出售 Fairs 的曲线为 $S(x) = s \times x$ ( $s$ 动态变化)。

其中 $B(x)>S(x) (\forall  x \in [0,\infty])$。

## Future

1. 添加预铸 `preMint` $Fairs$ 函数。

2. 添加 `MFG` 函数, 即传统证券 打新。

3. 添加 `close` 函数。

4. 添加 投资者 可以自定义分配比例的功能，并且可以限制范围。

## Foundry

**Foundry 是一个用 Rust 编写的快速、可移植且模块化的以太坊应用程序开发工具包。**

Foundry 包含以下组件：

- **Forge**：以太坊测试框架（类似于 Truffle、Hardhat 和 DappTools）。
- **Cast**：与 EVM 智能合约交互、发送交易和获取链数据的瑞士军刀工具。
- **Anvil**：本地以太坊节点，类似于 Ganache 和 Hardhat Network。
- **Chisel**：快速、实用且详细的 Solidity REPL 工具。

## 文档

https://book.getfoundry.sh/

## 使用方法

### 构建

```shell
$ forge build
```

### 测试

```shell
$ forge test
```

### 格式化

```shell
$ forge fmt
```

### Gas 快照

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### 部署

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### 帮助

```shell
$ forge --help
$ anvil --help
$ cast --help
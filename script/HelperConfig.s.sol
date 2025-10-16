// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

/// @title HelperConfig
/// @notice 管理不同网络的部署配置
/// @dev 支持 Sepolia 测试网和 Anvil 本地网络
contract HelperConfig is Script {
    
    ////// Errors //////
    error HelperConfig__InvalidChainId();
    
    ////// Type Declarations //////
    struct NetworkConfig {
        uint256 buySlope;              // 购买曲线斜率
        uint16 investmentRatio;        // 投资比例（基点制）
        uint16 distributionRatio;      // 分配比例（基点制）
        address organizationAddress;   // 组织地址
        uint256 deployerKey;           // 部署者私钥
    }
    
    ////// Constants //////
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    
    // 推荐的默认参数
    uint256 public constant DEFAULT_BUY_SLOPE = 1e15;      // 0.001 ETH per token
    uint16 public constant DEFAULT_INVESTMENT_RATIO = 3000; // 30%
    uint16 public constant DEFAULT_DISTRIBUTION_RATIO = 2000; // 20%
    
    ////// State Variables //////
    NetworkConfig private activeNetworkConfig;
    
    ////// Constructor //////
    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }
    
    ////// Getter Functions //////
    
    /// @notice 获取当前激活的网络配置
    /// @return 当前网络配置
    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
    
    ////// Public Functions //////
    
    /// @notice 获取 Sepolia 测试网配置
    /// @return sepoliaConfig Sepolia 网络配置
    function getSepoliaConfig() public view returns (NetworkConfig memory sepoliaConfig) {
        sepoliaConfig = NetworkConfig({
            buySlope: DEFAULT_BUY_SLOPE,
            investmentRatio: DEFAULT_INVESTMENT_RATIO,
            distributionRatio: DEFAULT_DISTRIBUTION_RATIO,
            organizationAddress: vm.envAddress("ORGANIZATION_ADDRESS"),
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }
    
    /// @notice 获取主网配置
    /// @return mainnetConfig 主网配置
    function getMainnetConfig() public view returns (NetworkConfig memory mainnetConfig) {
        mainnetConfig = NetworkConfig({
            buySlope: vm.envUint("MAINNET_BUY_SLOPE"),
            investmentRatio: uint16(vm.envUint("MAINNET_INVESTMENT_RATIO")),
            distributionRatio: uint16(vm.envUint("MAINNET_DISTRIBUTION_RATIO")),
            organizationAddress: vm.envAddress("ORGANIZATION_ADDRESS"),
            deployerKey: vm.envUint("MAINNET_PRIVATE_KEY")
        });
    }
    
    /// @notice 获取或创建 Anvil 本地网络配置
    /// @return anvilConfig Anvil 网络配置
    function getOrCreateAnvilConfig() public view returns (NetworkConfig memory anvilConfig) {
        // 如果已经设置过，直接返回
        if (activeNetworkConfig.organizationAddress != address(0)) {
            return activeNetworkConfig;
        }
        
        // 使用 Anvil 默认账户作为组织地址（账户#1）
        address defaultOrganization = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        
        anvilConfig = NetworkConfig({
            buySlope: DEFAULT_BUY_SLOPE,
            investmentRatio: DEFAULT_INVESTMENT_RATIO,
            distributionRatio: DEFAULT_DISTRIBUTION_RATIO,
            organizationAddress: defaultOrganization,
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
        
        console.log("Using Anvil local network configuration");
        console.log("Organization Address:", defaultOrganization);
    }
}
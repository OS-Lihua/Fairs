// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Fairs} from "src/Fairs.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

/// @title DeployFairs
/// @notice 部署 Fairs 代币合约
/// @dev 使用 HelperConfig 管理不同网络的配置
contract DeployFairs is Script {
    
    ////// Main Functions //////
    
    /// @notice 主部署函数
    /// @return fairs 部署的 Fairs 合约实例
    /// @return config 使用的网络配置
    function run() external returns (Fairs, HelperConfig) {
        // 获取网络配置
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        
        // 部署合约
        vm.startBroadcast(config.deployerKey);
        Fairs fairs = new Fairs(
            config.buySlope,
            config.investmentRatio,
            config.distributionRatio,
            config.organizationAddress
        );
        vm.stopBroadcast();
        
        // 输出部署信息
        logDeployment(fairs, config);
        
        return (fairs, helperConfig);
    }
    
    ////// Internal Functions //////
    
    /// @notice 记录部署信息
    /// @param fairs 部署的合约实例
    /// @param config 网络配置
    function logDeployment(Fairs fairs, HelperConfig.NetworkConfig memory config) internal view {
        console.log("========================================");
        console.log("Fairs Token Deployed Successfully!");
        console.log("========================================");
        console.log("Contract Address:", address(fairs));
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("Configuration:");
        console.log("- Buy Slope:", config.buySlope);
        console.log("- Investment Ratio:", config.investmentRatio, "(basis points)");
        console.log("- Distribution Ratio:", config.distributionRatio, "(basis points)");
        console.log("- Organization Address:", config.organizationAddress);
        console.log("");
        console.log("Token Info:");
        console.log("- Name:", fairs.name());
        console.log("- Symbol:", fairs.symbol());
        console.log("- Decimals:", fairs.decimals());
        console.log("- Owner:", fairs.owner());
        console.log("========================================");
    }
}
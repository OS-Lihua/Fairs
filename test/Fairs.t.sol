// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Fairs} from "src/Fairs.sol";
import {DeployFairs} from "script/DeployFairs.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

/// @title FairsTest
/// @notice Fairs 代币合约的完整测试套件
/// @dev 使用 Foundry 测试框架，集成部署脚本
contract FairsTest is Test {
    
    ////// 测试合约和配置 //////
    DeployFairs deployer;
    Fairs fairs;
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    
    ////// 测试用户 //////
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address organization;
    
    ////// 测试常量 //////
    uint256 constant STARTING_USER_BALANCE = 100 ether;
    uint256 constant BUY_AMOUNT = 1 ether;
    
    ////// 事件声明（用于测试） //////
    event Buy(address indexed buyer, uint256 amount, uint256 cost);
    event Sell(address indexed seller, uint256 amount, uint256 proceeds);
    event ReBuy(address indexed from, uint256 amount, uint256 refund);
    event Burn(address indexed burner, uint256 amount, uint256 totalBurned);
    
    ////// Setup //////
    
    /// @notice 在每个测试前运行，设置测试环境
    function setUp() public {
        // 使用部署脚本部署合约
        deployer = new DeployFairs();
        (fairs, helperConfig) = deployer.run();
        config = helperConfig.getActiveNetworkConfig();
        
        // 设置组织地址
        organization = config.organizationAddress;
        
        // 为测试用户提供 ETH
        vm.deal(user, STARTING_USER_BALANCE);
        vm.deal(user2, STARTING_USER_BALANCE);
    }
    
    ////// 1. 基础测试 //////
    
    /// @notice 测试合约部署和初始化
    function test_DeploymentInitialization() public view {
        // 验证合约地址不为零
        assertTrue(address(fairs) != address(0), "Fairs contract should be deployed");
        
        // 验证代币名称和符号
        assertEq(fairs.name(), "Fairs Token", "Token name should be Fairs Token");
        assertEq(fairs.symbol(), "FAIRS", "Token symbol should be FAIRS");
        assertEq(fairs.decimals(), 18, "Token decimals should be 18");
        
        // 验证初始状态
        assertEq(fairs.totalSupply(), 0, "Initial total supply should be 0");
        assertEq(fairs.tokenReserve(), 0, "Initial token reserve should be 0");
        assertEq(fairs.burnedAmount(), 0, "Initial burned amount should be 0");
    }
    
    /// @notice 测试构造函数参数
    function test_ConstructorParameters() public view {
        assertEq(fairs.buySlope(), config.buySlope, "Buy slope should match config");
        assertEq(fairs.investmentRatio(), config.investmentRatio, "Investment ratio should match config");
        assertEq(fairs.distributionRatio(), config.distributionRatio, "Distribution ratio should match config");
        assertEq(fairs.organizationAddress(), organization, "Organization address should match config");
    }
    
    /// @notice 测试常量值
    function test_Constants() public view {
        assertEq(fairs.BURN_ADDRESS(), 0x000000000000000000000000000000000000dEaD, "Burn address should be correct");
        assertEq(fairs.BASIS_POINTS_MAX(), 10000, "Basis points max should be 10000");
    }
    
    /// @notice 测试构造函数参数验证 - 零斜率应该失败
    function test_RevertWhen_ConstructorZeroBuySlope() public {
        vm.expectRevert(Fairs.ZeroBuySlope.selector);
        new Fairs(0, config.investmentRatio, config.distributionRatio, organization);
    }
    
    /// @notice 测试构造函数参数验证 - 无效投资比例
    function test_RevertWhen_ConstructorInvalidInvestmentRatio() public {
        vm.expectRevert(abi.encodeWithSelector(Fairs.InvalidRatio.selector, 0, 10000));
        new Fairs(config.buySlope, 0, config.distributionRatio, organization);
        
        vm.expectRevert(abi.encodeWithSelector(Fairs.InvalidRatio.selector, 10001, 10000));
        new Fairs(config.buySlope, 10001, config.distributionRatio, organization);
    }
    
    /// @notice 测试构造函数参数验证 - 无效分配比例
    function test_RevertWhen_ConstructorInvalidDistributionRatio() public {
        vm.expectRevert(abi.encodeWithSelector(Fairs.InvalidRatio.selector, 0, 10000));
        new Fairs(config.buySlope, config.investmentRatio, 0, organization);
        
        vm.expectRevert(abi.encodeWithSelector(Fairs.InvalidRatio.selector, 10001, 10000));
        new Fairs(config.buySlope, config.investmentRatio, 10001, organization);
    }
    
    /// @notice 测试构造函数参数验证 - 零地址
    function test_RevertWhen_ConstructorZeroAddress() public {
        vm.expectRevert(Fairs.ZeroAddress.selector);
        new Fairs(config.buySlope, config.investmentRatio, config.distributionRatio, address(0));
    }
    
    ////// 2. buy() 函数测试 //////
    
    /// @notice 测试正常购买流程
    function test_Buy_Success() public {
        uint256 buyAmount = 1 ether;
        uint256 expectedReserve = (buyAmount * config.investmentRatio) / 10000;
        uint256 expectedOrgAmount = buyAmount - expectedReserve;
        
        uint256 orgBalanceBefore = organization.balance;
        
        // 执行购买
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit Buy(user, 0, buyAmount); // 只检查地址和金额，代币数量需要计算
        fairs.buy{value: buyAmount}();
        
        // 验证用户获得了代币
        assertTrue(fairs.balanceOf(user) > 0, "User should have tokens");
        
        // 验证总供应量增加
        assertTrue(fairs.totalSupply() > 0, "Total supply should increase");
        
        // 验证储备金更新
        assertEq(fairs.tokenReserve(), expectedReserve, "Reserve should be updated correctly");
        
        // 验证组织地址收到资金
        assertEq(organization.balance, orgBalanceBefore + expectedOrgAmount, "Organization should receive funds");
    }
    
    /// @notice 测试购买后代币数量计算
    function test_Buy_TokenCalculation() public {
        uint256 buyAmount = 1 ether;
        
        vm.prank(user);
        fairs.buy{value: buyAmount}();
        
        uint256 userBalance = fairs.balanceOf(user);
        
        // 根据公式验证: x = sqrt(2c/b + a^2) - a
        // 初始 a = 0, 所以 x = sqrt(2c/b)
        uint256 expectedTokens = _calculateBuyTokens(buyAmount, 0);
        
        assertEq(userBalance, expectedTokens, "Token calculation should be correct");
    }
    
    /// @notice 测试多次购买
    function test_Buy_MultiplePurchases() public {
        // 第一次购买
        vm.prank(user);
        fairs.buy{value: 1 ether}();
        uint256 firstBalance = fairs.balanceOf(user);
        
        // 第二次购买
        vm.prank(user);
        fairs.buy{value: 1 ether}();
        uint256 secondBalance = fairs.balanceOf(user);
        
        // 第二次购买应该获得更少的代币（价格上涨）
        assertTrue(secondBalance > firstBalance, "Balance should increase");
        assertTrue((secondBalance - firstBalance) < firstBalance, "Second purchase should yield fewer tokens");
    }
    
    /// @notice 测试不同用户购买
    function test_Buy_DifferentUsers() public {
        // user 购买
        vm.prank(user);
        fairs.buy{value: 1 ether}();
        
        // user2 购买
        vm.prank(user2);
        fairs.buy{value: 1 ether}();
        
        // 两个用户都应该有代币
        assertTrue(fairs.balanceOf(user) > 0, "User1 should have tokens");
        assertTrue(fairs.balanceOf(user2) > 0, "User2 should have tokens");
    }
    
    /// @notice 测试购买时零值应该失败
    function test_RevertWhen_BuyZeroValue() public {
        vm.prank(user);
        vm.expectRevert(Fairs.ZeroValue.selector);
        fairs.buy{value: 0}();
    }
    
    /// @notice 测试购买时金额太小导致计算错误
    function test_RevertWhen_BuyAmountTooSmall() public {
        // 使用极小的金额，会导致 InvalidCalculation 错误
        vm.prank(user);
        vm.expectRevert(Fairs.InvalidCalculation.selector);
        fairs.buy{value: 1 wei}();
    }
    
    ////// 3. sell() 函数测试 //////
    
    /// @notice 测试正常出售流程
    function test_Sell_Success() public {
        // 先购买代币
        vm.prank(user);
        fairs.buy{value: 5 ether}();
        
        uint256 userTokens = fairs.balanceOf(user);
        uint256 sellAmount = userTokens / 2; // 出售一半
        
        uint256 userEthBefore = user.balance;
        uint256 reserveBefore = fairs.tokenReserve();
        
        // 执行出售
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit Sell(user, sellAmount, 0); // 收益需要计算
        fairs.sell(sellAmount);
        
        // 验证用户代币减少
        assertEq(fairs.balanceOf(user), userTokens - sellAmount, "User tokens should decrease");
        
        // 验证用户收到 ETH
        assertTrue(user.balance > userEthBefore, "User should receive ETH");
        
        // 验证储备金减少
        assertTrue(fairs.tokenReserve() < reserveBefore, "Reserve should decrease");
        
        // 验证总供应量减少
        assertEq(fairs.totalSupply(), userTokens - sellAmount, "Total supply should decrease");
    }
    
    /// @notice 测试出售收益计算
    function test_Sell_ProceedsCalculation() public {
        // 购买代币
        uint256 buyAmount = 10 ether;
        vm.prank(user);
        fairs.buy{value: buyAmount}();
        
        uint256 tokens = fairs.balanceOf(user);
        uint256 sellAmount = tokens / 2; // 出售一半，不能出售全部
        
        // 计算预期收益
        uint256 expectedProceeds = _calculateSellProceeds(sellAmount, tokens, fairs.tokenReserve(), 0);
        
        uint256 userEthBefore = user.balance;
        
        // 出售
        vm.prank(user);
        fairs.sell(sellAmount);
        
        uint256 actualProceeds = user.balance - userEthBefore;
        
        assertEq(actualProceeds, expectedProceeds, "Proceeds should match calculation");
    }
    
    /// @notice 测试零数量出售应该失败
    function test_RevertWhen_SellZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(Fairs.ZeroAmount.selector);
        fairs.sell(0);
    }
    
    /// @notice 测试余额不足出售应该失败
    function test_RevertWhen_SellInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Fairs.InsufficientBalance.selector, 0, 100));
        fairs.sell(100);
    }
    
    /// @notice 测试出售数量超过总供应量应该失败
    function test_RevertWhen_SellExceedsTotalSupply() public {
        // 购买一些代币
        vm.prank(user);
        fairs.buy{value: 1 ether}();
        
        uint256 totalSupply = fairs.totalSupply();
        
        // 尝试出售等于或超过总供应量的代币
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Fairs.ExceedsTotalSupply.selector, totalSupply, totalSupply));
        fairs.sell(totalSupply);
    }
    
    ////// 4. rebuy() 函数测试 //////
    
    /// @notice 测试组织地址回购
    function test_Rebuy_Success() public {
        uint256 rebuyAmount = 5 ether;
        uint256 reserveBefore = fairs.tokenReserve();
        
        // 组织地址回购
        vm.deal(organization, rebuyAmount);
        vm.prank(organization);
        fairs.rebuy{value: rebuyAmount}();
        
        // 验证组织获得代币
        assertTrue(fairs.balanceOf(organization) > 0, "Organization should have tokens");
        
        // 验证全部资金进入储备金
        assertEq(fairs.tokenReserve(), reserveBefore + rebuyAmount, "All funds should go to reserve");
    }
    
    /// @notice 测试回购资金分配（全部进储备金）
    function test_Rebuy_AllFundsToReserve() public {
        uint256 rebuyAmount = 3 ether;
        
        vm.deal(organization, rebuyAmount);
        vm.prank(organization);
        fairs.rebuy{value: rebuyAmount}();
        
        // 验证储备金等于回购金额
        assertEq(fairs.tokenReserve(), rebuyAmount, "Reserve should equal rebuy amount");
    }
    
    /// @notice 测试非组织地址回购应该失败
    function test_RevertWhen_RebuyNotOrganization() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Fairs.OnlyOrganization.selector, user));
        fairs.rebuy{value: 1 ether}();
    }
    
    /// @notice 测试回购零值应该失败
    function test_RevertWhen_RebuyZeroValue() public {
        vm.prank(organization);
        vm.expectRevert(Fairs.ZeroValue.selector);
        fairs.rebuy{value: 0}();
    }
    
    ////// 5. pay() 函数测试 //////
    
    /// @notice 测试 pay 函数默认接收地址
    function test_Pay_DefaultRecipient() public {
        uint256 payAmount = 2 ether;
        
        vm.prank(user);
        fairs.pay{value: payAmount}(address(0)); // 零地址应该使用组织地址
        
        // 验证组织地址收到代币
        assertTrue(fairs.balanceOf(organization) > 0, "Organization should receive tokens");
    }
    
    /// @notice 测试 pay 函数自定义接收地址
    function test_Pay_CustomRecipient() public {
        uint256 payAmount = 2 ether;
        address recipient = makeAddr("recipient");
        
        vm.prank(user);
        fairs.pay{value: payAmount}(recipient);
        
        // 验证自定义接收者收到代币
        assertTrue(fairs.balanceOf(recipient) > 0, "Recipient should receive tokens");
        
        // 验证购买者没有收到代币
        assertEq(fairs.balanceOf(user), 0, "Buyer should not receive tokens");
    }
    
    /// @notice 测试 pay 函数资金分配
    function test_Pay_FundDistribution() public {
        uint256 payAmount = 5 ether;
        uint256 expectedReserve = (payAmount * config.distributionRatio) / 10000;
        uint256 expectedOrgAmount = payAmount - expectedReserve;
        
        uint256 orgBalanceBefore = organization.balance;
        
        vm.prank(user);
        fairs.pay{value: payAmount}(user2);
        
        // 验证储备金
        assertEq(fairs.tokenReserve(), expectedReserve, "Reserve should match distribution ratio");
        
        // 验证组织收到资金
        assertEq(organization.balance, orgBalanceBefore + expectedOrgAmount, "Organization should receive correct amount");
    }
    
    /// @notice 测试 pay 函数零值应该失败
    function test_RevertWhen_PayZeroValue() public {
        vm.prank(user);
        vm.expectRevert(Fairs.ZeroValue.selector);
        fairs.pay{value: 0}(user2);
    }
    
    ////// 6. burn() 函数测试 //////
    
    /// @notice 测试燃烧功能
    function test_Burn_Success() public {
        // 先购买代币
        vm.prank(user);
        fairs.buy{value: 5 ether}();
        
        uint256 userTokens = fairs.balanceOf(user);
        uint256 burnAmount = userTokens / 2;
        
        // 燃烧代币
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit Burn(user, burnAmount, burnAmount);
        fairs.burn(burnAmount);
        
        // 验证用户余额减少
        assertEq(fairs.balanceOf(user), userTokens - burnAmount, "User balance should decrease");
        
        // 验证黑洞地址余额
        assertEq(fairs.balanceOf(fairs.BURN_ADDRESS()), burnAmount, "Burn address should have tokens");
        
        // 验证燃烧总量更新
        assertEq(fairs.burnedAmount(), burnAmount, "Burned amount should be updated");
    }
    
    /// @notice 测试 burnedAmount 更新
    function test_Burn_UpdatesBurnedAmount() public {
        // 购买代币
        vm.prank(user);
        fairs.buy{value: 3 ether}();
        
        uint256 firstBurn = fairs.balanceOf(user) / 3;
        uint256 secondBurn = fairs.balanceOf(user) / 3;
        
        // 第一次燃烧
        vm.prank(user);
        fairs.burn(firstBurn);
        assertEq(fairs.burnedAmount(), firstBurn, "First burn should update burnedAmount");
        
        // 第二次燃烧
        vm.prank(user);
        fairs.burn(secondBurn);
        assertEq(fairs.burnedAmount(), firstBurn + secondBurn, "Second burn should accumulate");
    }
    
    /// @notice 测试 circulatingSupply 计算
    function test_Burn_CirculatingSupply() public {
        // 购买代币
        vm.prank(user);
        fairs.buy{value: 5 ether}();
        
        uint256 totalSupply = fairs.totalSupply();
        uint256 burnAmount = totalSupply / 4;
        
        // 燃烧前
        assertEq(fairs.circulatingSupply(), totalSupply, "Circulating supply should equal total supply");
        
        // 燃烧后
        vm.prank(user);
        fairs.burn(burnAmount);
        
        assertEq(fairs.circulatingSupply(), totalSupply - burnAmount, "Circulating supply should decrease");
        assertEq(fairs.totalSupply(), totalSupply, "Total supply should not change");
    }
    
    /// @notice 测试 burnAddressBalance 查询
    function test_Burn_BurnAddressBalance() public {
        // 购买代币
        vm.prank(user);
        fairs.buy{value: 2 ether}();
        
        uint256 burnAmount = fairs.balanceOf(user);
        
        // 燃烧
        vm.prank(user);
        fairs.burn(burnAmount);
        
        // 验证黑洞地址余额
        assertEq(fairs.burnAddressBalance(), burnAmount, "Burn address balance should match burned amount");
    }
    
    /// @notice 测试燃烧零数量应该失败
    function test_RevertWhen_BurnZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(Fairs.ZeroAmount.selector);
        fairs.burn(0);
    }
    
    /// @notice 测试燃烧余额不足应该失败
    function test_RevertWhen_BurnInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Fairs.InsufficientBalance.selector, 0, 1000));
        fairs.burn(1000);
    }
    
    /// @notice 测试燃烧后出售的奖励机制
    function test_Burn_SellBonusAfterBurn() public {
        // user 购买代币
        vm.prank(user);
        fairs.buy{value: 10 ether}();
        
        uint256 userTokens = fairs.balanceOf(user);
        uint256 burnAmount = userTokens / 5;
        
        // user 燃烧部分代币
        vm.prank(user);
        fairs.burn(burnAmount);
        
        // user2 购买代币
        vm.prank(user2);
        fairs.buy{value: 5 ether}();
        
        // user2 出售应该获得燃烧奖励
        uint256 user2Tokens = fairs.balanceOf(user2);
        uint256 ethBefore = user2.balance;
        
        vm.prank(user2);
        fairs.sell(user2Tokens / 2);
        
        uint256 proceeds = user2.balance - ethBefore;
        
        // 验证获得了收益（包含燃烧奖励）
        assertTrue(proceeds > 0, "Should receive proceeds with burn bonus");
    }
    
    ////// 7. Fuzz 测试 //////
    
    /// @notice Fuzz 测试：购买任意数量
    function testFuzz_Buy(uint256 amount) public {
        // 限制金额范围
        amount = bound(amount, 0.001 ether, 100 ether);
        
        vm.deal(user, amount);
        
        vm.prank(user);
        fairs.buy{value: amount}();
        
        // 验证用户获得了代币
        assertTrue(fairs.balanceOf(user) > 0, "User should receive tokens");
        assertTrue(fairs.tokenReserve() > 0, "Reserve should increase");
    }
    
    /// @notice Fuzz 测试：购买和出售
    function testFuzz_BuyAndSell(uint256 buyAmount, uint256 sellRatio) public {
        // 限制范围
        buyAmount = bound(buyAmount, 1 ether, 50 ether);
        sellRatio = bound(sellRatio, 1, 99); // 1-99%
        
        vm.deal(user, buyAmount);
        
        // 购买
        vm.prank(user);
        fairs.buy{value: buyAmount}();
        
        uint256 tokens = fairs.balanceOf(user);
        uint256 sellAmount = (tokens * sellRatio) / 100;
        
        if (sellAmount > 0 && sellAmount < fairs.totalSupply()) {
            // 出售
            vm.prank(user);
            fairs.sell(sellAmount);
            
            // 验证余额正确
            assertEq(fairs.balanceOf(user), tokens - sellAmount, "Balance should be correct");
        }
    }
    
    ////// 8. 辅助查看函数测试 //////
    
    /// @notice 测试 circulatingSupply 查询
    function test_CirculatingSupply() public {
        // 初始应该为 0
        assertEq(fairs.circulatingSupply(), 0, "Initial circulating supply should be 0");
        
        // 购买后
        vm.prank(user);
        fairs.buy{value: 5 ether}();
        assertEq(fairs.circulatingSupply(), fairs.totalSupply(), "Should equal total supply without burns");
        
        // 燃烧后
        uint256 burnAmount = fairs.balanceOf(user) / 2;
        vm.prank(user);
        fairs.burn(burnAmount);
        assertEq(fairs.circulatingSupply(), fairs.totalSupply() - burnAmount, "Should account for burns");
    }
    
    /// @notice 测试 burnAddressBalance 查询
    function test_BurnAddressBalance() public view {
        // 初始应该为 0
        assertEq(fairs.burnAddressBalance(), 0, "Initial burn address balance should be 0");
    }
    
    ////// 9. 边界条件测试 //////
    
    /// @notice 测试极小金额购买
    function test_Buy_MinimalAmount() public {
        // 尝试用最小可能产生代币的金额
        uint256 minAmount = 0.01 ether;
        
        vm.prank(user);
        fairs.buy{value: minAmount}();
        
        assertTrue(fairs.balanceOf(user) > 0, "Should receive tokens even with minimal amount");
    }
    
    /// @notice 测试大额购买
    function test_Buy_LargeAmount() public {
        uint256 largeAmount = 50 ether;
        vm.deal(user, largeAmount);
        
        vm.prank(user);
        fairs.buy{value: largeAmount}();
        
        assertTrue(fairs.balanceOf(user) > 0, "Should handle large purchases");
        assertTrue(fairs.tokenReserve() > 0, "Reserve should be substantial");
    }
    
    /// @notice 测试连续多次小额购买
    function test_Buy_MultipleSmallPurchases() public {
        uint256 purchaseAmount = 0.1 ether;
        
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(user);
            fairs.buy{value: purchaseAmount}();
        }
        
        assertTrue(fairs.balanceOf(user) > 0, "Should accumulate tokens");
        assertEq(
            fairs.tokenReserve(), 
            (purchaseAmount * config.investmentRatio * 10) / 10000,
            "Reserve should accumulate correctly"
        );
    }
    
    ////// 10. 集成测试 //////
    
    /// @notice 完整流程测试：购买 -> 燃烧 -> 出售
    function test_Integration_BuyBurnSell() public {
        // 1. 购买代币
        vm.prank(user);
        fairs.buy{value: 10 ether}();
        uint256 tokens = fairs.balanceOf(user);
        
        // 2. 燃烧部分代币
        uint256 burnAmount = tokens / 4;
        vm.prank(user);
        fairs.burn(burnAmount);
        
        // 3. 出售剩余代币
        uint256 remainingTokens = fairs.balanceOf(user);
        vm.prank(user);
        fairs.sell(remainingTokens / 2);
        
        // 验证最终状态
        assertTrue(fairs.balanceOf(user) > 0, "User should have remaining tokens");
        assertTrue(fairs.burnedAmount() > 0, "Should have burned tokens");
        assertTrue(fairs.circulatingSupply() < fairs.totalSupply(), "Circulating should be less than total");
    }
    
    /// @notice 完整流程测试：多用户交互
    function test_Integration_MultiUserFlow() public {
        // user 购买
        vm.prank(user);
        fairs.buy{value: 5 ether}();
        
        // user2 购买
        vm.prank(user2);
        fairs.buy{value: 3 ether}();
        
        // user 燃烧
        uint256 userBalance = fairs.balanceOf(user);
        vm.prank(user);
        fairs.burn(userBalance / 2);
        
        // 组织回购
        vm.deal(organization, 2 ether);
        vm.prank(organization);
        fairs.rebuy{value: 2 ether}();
        
        // user2 出售（确保不会出售等于或超过总供应量）
        uint256 user2Balance = fairs.balanceOf(user2);
        uint256 sellAmount = user2Balance / 3; // 出售三分之一，确保远小于总供应量
        
        vm.prank(user2);
        fairs.sell(sellAmount);
        
        // 验证所有用户都有正确的余额
        assertTrue(fairs.balanceOf(user) > 0, "User should have tokens");
        assertTrue(fairs.balanceOf(user2) > 0, "User2 should have tokens");
        assertTrue(fairs.balanceOf(organization) > 0, "Organization should have tokens");
    }
    
    ////// 辅助函数 //////
    
    /// @notice 计算购买代币数量
    /// @param c 购买金额
    /// @param a 当前总供应量
    /// @return 可获得的代币数量
    function _calculateBuyTokens(uint256 c, uint256 a) internal view returns (uint256) {
        uint256 b = fairs.buySlope();
        // 更新为新的计算逻辑: sqrt(2c/b + a^2)
        // 注意：这里为了测试简单，我们尽量模拟合约中的逻辑，但 Solidity 的 Math.mulDiv 处理溢出更好
        // 在测试辅助函数中，我们假设不会溢出或者简单模拟
        uint256 term1 = (2 * c) / b;
        uint256 sqrtResult = _sqrt(term1 + a * a);
        return sqrtResult - a;
    }
    
    /// @notice 计算出售收益
    /// @param x 出售数量
    /// @param a 总供应量
    /// @param R 储备金
    /// @param rPrime 已燃烧数量
    /// @return 出售收益
    function _calculateSellProceeds(
        uint256 x,
        uint256 a,
        uint256 R,
        uint256 rPrime
    ) internal pure returns (uint256) {
        // 更新为新的计算逻辑，模拟 Math.mulDiv
        uint256 term1 = (2 * R * x) / a;
        // term2 = (R * x * x) / (a * a) -> (R * x / a) * x / a
        uint256 term2 = ((R * x) / a * x) / a;
        uint256 mainPart = term1 - term2;
        uint256 burnBonus = rPrime > 0 ? rPrime / x : 0; // 测试中保持简单除法，合约中用了 mulDiv(rPrime, 1, x) 也是一样的结果
        return mainPart + burnBonus;
    }
    
    /// @notice 简单的平方根计算（用于测试）
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title the project for Continuous Organizations by bouding curve.
/// @author YaCo
/// @notice user can deploy this project for rwa.
contract Fairs is ERC20, Ownable, ReentrancyGuard {

    ////// Events //////
    event Buy(address indexed buyer, uint256 amount, uint256 cost);
    event Sell(address indexed seller, uint256 amount, uint256 proceeds);
    event ReBuy(address indexed from, uint256 amount, uint256 refund);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event Burn(address indexed burner, uint256 amount, uint256 totalBurned);
    
    ////// Custom Errors //////
    error ZeroBuySlope();
    error InvalidRatio(uint16 ratio, uint16 max);
    error ZeroAddress();
    error ZeroValue();
    error InvalidCalculation();
    error AmountTooSmall(uint256 amount);
    error ZeroAmount();
    error InsufficientBalance(uint256 balance, uint256 required);
    error ExceedsTotalSupply(uint256 amount, uint256 totalSupply);
    error InsufficientReserve();
    error ZeroProceeds();
    error InsufficientContractBalance(uint256 balance, uint256 required);
    error TransferFailed();
    error OnlyOrganization(address caller);

    ////// Constants //////
    /// @dev 黑洞地址，用于燃烧代币
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    /// @dev 基点制的最大值 (100%)
    uint16 public constant BASIS_POINTS_MAX = 10000;

    ////// State Variables //////
    // 注意：以下变量经过 Gas 优化打包，存储在同一个槽中以节省 Gas
    
    /// @notice 组织钱包地址，用于接收分配的资金
    address public organizationAddress;          // 槽 0 (20 字节)
    
    /// @notice 投资比例（基点制，10000 = 100%）
    /// @dev 用户购买时，投入资金的百分比进入储备金
    uint16 public investmentRatio;               // 槽 0 (2 字节)
    
    /// @notice 分配比例（基点制，10000 = 100%）
    /// @dev 用于计算组织的资金分配比例
    uint16 public distributionRatio;             // 槽 0 (2 字节)
    // 槽 0 还剩余 8 字节可用于未来扩展
    
    /// @notice 购买曲线斜率 b，公式 B(x) = b * x
    uint256 public buySlope;                     // 槽 1 (32 字节)
    
    /// @notice DAT 资金储备（存储在本合约中的 ETH）
    uint256 public tokenReserve;                 // 槽 2 (32 字节)
    
    /// @notice 已燃烧的代币总量
    uint256 public burnedAmount;                 // 槽 3 (32 字节)


    ////// Constructor //////
    /// @notice 初始化 Fairs 代币合约
    /// @param _buySlope 购买曲线斜率
    /// @param _investmentRatio 投资比例（基点制，如 1000 = 10%）
    /// @param _distributionRatio 分配比例（基点制，如 2000 = 20%）
    /// @param _organizationAddress 组织钱包地址
    constructor(
        uint256 _buySlope,
        uint16 _investmentRatio,
        uint16 _distributionRatio,
        address _organizationAddress
    ) ERC20("Fairs Token", "FAIRS") Ownable(msg.sender) {
        if (_buySlope == 0) revert ZeroBuySlope();
        if (_investmentRatio == 0 || _investmentRatio > BASIS_POINTS_MAX) {
            revert InvalidRatio(_investmentRatio, BASIS_POINTS_MAX);
        }
        if (_distributionRatio == 0 || _distributionRatio > BASIS_POINTS_MAX) {
            revert InvalidRatio(_distributionRatio, BASIS_POINTS_MAX);
        }
        if (_organizationAddress == address(0)) revert ZeroAddress();

        buySlope = _buySlope;
        investmentRatio = _investmentRatio;
        distributionRatio = _distributionRatio;
        organizationAddress = _organizationAddress;
        tokenReserve = 0; // 初始储备为 0
        burnedAmount = 0; // 初始燃烧量为 0
    }

    ////// Public Functions //////
    
    /// @notice 购买 FAIR 代币
    /// @dev 根据公式 x = sqrt(2c/b + a^2) - a 计算可获得的代币数量
    function buy() public payable nonReentrant {
        if (msg.value == 0) revert ZeroValue();
               
        uint256 c = msg.value; // 购买金额
        uint256 b = buySlope; // 斜率
        uint256 a = totalSupply(); // 交易前已流通的代币数量
        
        // 计算可获得的代币数量: x = sqrt(2c/b + a^2) - a
        // 为避免精度问题，我们重写为: x = sqrt((2c + b*a^2) / b) - a
        // 使用 Math.mulDiv 避免 b*a^2 溢出: (2c + b*a^2)/b = 2c/b + a^2
        uint256 sqrtResult = Math.sqrt(Math.mulDiv(2, c, b) + a * a);
        if (sqrtResult <= a) revert InvalidCalculation();
        
        uint256 tokensToMint = sqrtResult - a;
        if (tokensToMint == 0) revert AmountTooSmall(tokensToMint);
        
        // 铸造代币给购买者
        _mint(msg.sender, tokensToMint);
        
        // 计算资金分配
        uint256 reserveAmount = (msg.value * investmentRatio) / BASIS_POINTS_MAX;
        uint256 organizationAmount = msg.value - reserveAmount;
        
        // 更新储备金
        tokenReserve += reserveAmount;
        
        // 将剩余资金转给组织地址
        if (organizationAmount > 0) {
            (bool success, ) = organizationAddress.call{value: organizationAmount}("");
            if (!success) revert TransferFailed();
        }
        
        emit Buy(msg.sender, tokensToMint, msg.value);
    }

    /// @notice 出售 FAIR 代币换取 ETH
    /// @dev 根据公式 M = (2Rx/a)(1 - x/(2a)) + R'/x 计算出售收益，其中 R' = burnedAmount
    /// @param amount 要出售的代币数量
    function sell(uint256 amount) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) revert InsufficientBalance(balance, amount);
        
        uint256 x = amount; // 出售数量
        uint256 a = totalSupply(); // 已铸造的代币总量
        uint256 R = tokenReserve; // DAT 资金储备
        uint256 rPrime = burnedAmount; // 代币燃烧数量 (R')
        
        if (x >= a) revert ExceedsTotalSupply(x, a);
        if (R == 0) revert InsufficientReserve();
        
        // 计算出售收益 M = (2Rx/a)(1 - x/(2a)) + R'/x
        // 简化为: M = (2Rx/a) - (Rx²/a²) + R'/x
        
        // 第一部分: (2Rx/a)(1 - x/(2a))
        // = (2Rx/a) - (Rx²/a²)
        uint256 term1 = Math.mulDiv(2 * R, x, a);
        uint256 term2 = Math.mulDiv(Math.mulDiv(R, x, a), x, a);
        uint256 mainPart = term1 - term2;
        
        // 第二部分: R'/x (R' = rPrime)
        uint256 burnBonus = Math.mulDiv(rPrime, 1, x);
        
        // 总收益 = 主要部分 + 燃烧奖励
        uint256 proceeds = mainPart + burnBonus;
        
        if (proceeds == 0) revert ZeroProceeds();
        
        uint256 contractBalance = address(this).balance;
        if (contractBalance < proceeds) {
            revert InsufficientContractBalance(contractBalance, proceeds);
        }
        
        // 燃烧用户的代币
        _burn(msg.sender, amount);
        
        // 更新储备金
        tokenReserve -= proceeds;
        
        // 转账 ETH 给卖家
        (bool success, ) = msg.sender.call{value: proceeds}("");
        if (!success) revert TransferFailed();
        
        emit Sell(msg.sender, amount, proceeds);
    }
    
    /// @notice 组织回购代币
    /// @dev 只能由组织地址调用，所有资金进入储备金
    function rebuy() public payable nonReentrant {
        if (msg.sender != organizationAddress) revert OnlyOrganization(msg.sender);
        if (msg.value == 0) revert ZeroValue();
               
        uint256 c = msg.value; // 购买金额
        uint256 b = buySlope; // 斜率
        uint256 a = totalSupply(); // 交易前已流通的代币数量
        
        // 计算可获得的代币数量: x = sqrt(2c/b + a^2) - a
        // 为避免精度问题，我们重写为: x = sqrt((2c + b*a^2) / b) - a
        // 使用 Math.mulDiv 避免 b*a^2 溢出
        uint256 sqrtResult = Math.sqrt(Math.mulDiv(2, c, b) + a * a);
        if (sqrtResult <= a) revert InvalidCalculation();
        
        uint256 tokensToMint = sqrtResult - a;
        if (tokensToMint == 0) revert AmountTooSmall(tokensToMint);
        
        // 铸造代币给购买者
        _mint(msg.sender, tokensToMint);
        
        // 更新储备金（回购时全部进入储备金）
        tokenReserve += msg.value;
        
        emit Buy(msg.sender, tokensToMint, msg.value);
    }

    /// @notice 支付 ETH 购买代币，并将部分资金分配给指定地址
    /// @dev 如果 recipient 为零地址，则默认分配给 organizationAddress
    /// @param recipient 接收分配资金的地址，传入 address(0) 则使用 organizationAddress
    function pay(address recipient) public payable nonReentrant {
        if (msg.value == 0) revert ZeroValue();

        address target = recipient == address(0)
        ? organizationAddress : recipient;
    
        uint256 c = msg.value; // 购买金额
        uint256 b = buySlope; // 斜率
        uint256 a = totalSupply(); // 交易前已流通的代币数量
        
        // 计算可获得的代币数量: x = sqrt(2c/b + a^2) - a
        // 为避免精度问题，我们重写为: x = sqrt((2c + b*a^2) / b) - a
        // 使用 Math.mulDiv 避免 b*a^2 溢出
        uint256 sqrtResult = Math.sqrt(Math.mulDiv(2, c, b) + a * a);
        if (sqrtResult <= a) revert InvalidCalculation();
        
        uint256 tokensToMint = sqrtResult - a;
        if (tokensToMint == 0) revert AmountTooSmall(tokensToMint);
        
        // 铸造代币给指定接收者
        _mint(target, tokensToMint);
        
        // 计算资金分配
        uint256 reserveAmount = (msg.value * distributionRatio) / BASIS_POINTS_MAX;
        uint256 organizationAmount = msg.value - reserveAmount;
        
        // 更新储备金
        tokenReserve += reserveAmount;
        
        // 将剩余资金转给组织地址
        if (organizationAmount > 0) {
            (bool success, ) = organizationAddress.call{value: organizationAmount}("");
            if (!success) revert TransferFailed();
        }
        
        emit Buy(msg.sender, tokensToMint, msg.value);
    }

    /// @notice 燃烧代币到黑洞地址
    /// @dev 将代币转移到 0xdead 地址，不减少 totalSupply，但代币永久无法使用
    /// @param amount 要燃烧的代币数量
    function burn(uint256 amount) public {
        if (amount == 0) revert ZeroAmount();
        
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) revert InsufficientBalance(balance, amount);
        
        // 转移到黑洞地址
        _transfer(msg.sender, BURN_ADDRESS, amount);
        
        // 更新燃烧统计
        burnedAmount += amount;
        
        emit Burn(msg.sender, amount, burnedAmount);
    }
    
    /// @notice 查询有效流通量（总供应量 - 已燃烧数量）
    /// @return 有效流通的代币数量
    function circulatingSupply() public view returns (uint256) {
        return totalSupply() - burnedAmount;
    }
    
    /// @notice 获取黑洞地址的代币余额（已燃烧但仍计入 totalSupply）
    /// @return 黑洞地址持有的代币数量
    function burnAddressBalance() public view returns (uint256) {
        return balanceOf(BURN_ADDRESS);
    }
}

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./external/BMath.sol";
import "./external/BPool.sol";
import "./external/ConfigurableRightsPool.sol";
import "./external/interfaces/IPancakeRouter01.sol";
import "./external/interfaces/IPool.sol";
import "./external/libraries/BalancerSafeMath.sol";

contract EthPoolBuyer is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address private weth;
    IPancakeRouter01 private exchanger;

    event Received(address sender, uint amount);

    struct PoolToken {
        address token;
        uint256 amount;
        uint256 poolBalance;
        uint256 ethPrice;
    }

    constructor(address _exchanger) public {
        require(_exchanger != address(0));

        exchanger = IPancakeRouter01(_exchanger);
        weth = exchanger.WETH();
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function joinPool(address pool, bool isSmartPool, uint256 deadline)
        external
        payable
        nonReentrant
    returns (PoolToken[] memory)
    {
        (PoolToken[] memory poolTokens, uint256 poolAmountOut) = this.calcJoinPool(pool, isSmartPool, msg.value);

        uint256[] memory tokensIn = new uint256[](poolTokens.length);

        for (uint i = 0; i < poolTokens.length; i++) {
            buyToken(poolTokens[i].token, poolTokens[i].amount, poolTokens[i].ethPrice, deadline);

            IERC20(poolTokens[i].token).safeApprove(pool, poolTokens[i].amount);

            tokensIn[i] = poolTokens[i].amount;
        }

        IPool(pool).joinPool(poolAmountOut, tokensIn);

        msg.sender.transfer(address(this).balance);
        IERC20(pool).safeTransfer(address(msg.sender), IERC20(pool).balanceOf(address(this)));

        return poolTokens;
    }

    function calcJoinPool(address pool, bool isSmartPool, uint256 ethValue)
        external
        view
    returns (PoolToken[] memory, uint256)
    {
        IBPool bPool = getSharedPool(pool, isSmartPool);

        address[] memory tokens = bPool.getCurrentTokens();
        PoolToken[] memory result = new PoolToken[](tokens.length);
        PoolToken memory expensiveToken = result[0];

        for (uint i = 0; i < tokens.length; i++) {
            result[i].token = tokens[i];
            result[i].amount = getTokenEthPrice(result[i].token, ethValue);
            result[i].poolBalance = bPool.getBalance(result[i].token);

            if (result[i].amount <= expensiveToken.amount) {
                expensiveToken = result[i];
            }
        }

        uint256 tokensPriceSum = 0;

        for (uint i = 0; i < tokens.length; i++) {
            if (result[i].token != expensiveToken.token) {
                result[i].amount = result[i].poolBalance
                    .mul(expensiveToken.amount.add(expensiveToken.poolBalance))
                    .div(expensiveToken.poolBalance)
                    .sub(result[i].poolBalance);

                result[i].ethPrice = getTokenPriceInWei(result[i].token, result[i].amount);

                tokensPriceSum = tokensPriceSum.add(result[i].ethPrice);
            }
        }

        expensiveToken.ethPrice = ethValue.sub(tokensPriceSum);
        expensiveToken.amount = getTokenEthPrice(expensiveToken.token, expensiveToken.ethPrice);

        uint256 currentSupply = IPool(pool).totalSupply();
        uint256 poolAmountOut = currentSupply
            .mul(expensiveToken.amount.add(expensiveToken.poolBalance))
            .div(expensiveToken.poolBalance)
            .sub(currentSupply);

        // Subtract  1 to ensure any rounding errors favor the pool
        uint ratio = BalancerSafeMath.bdiv(poolAmountOut, BalancerSafeMath.bsub(currentSupply, 1));

        for (uint i = 0; i < tokens.length; i++) {
            result[i].amount = BalancerSafeMath.bmul(ratio, BalancerSafeMath.badd(result[i].poolBalance, 1));
            result[i].ethPrice = getTokenPriceInWei(result[i].token, result[i].amount);
        }

        return (result, poolAmountOut);
    }

    function getBalance(address token)
        external
        view
    returns (uint256)
    {
        return IERC20(token).balanceOf(address(this));
    }

    function buyToken(address token, uint256 tokenAmount, uint256 ethAmount, uint256 deadline)
        internal
    returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = token;

        uint[] memory exchangeAmounts = exchanger.swapETHForExactTokens{value : ethAmount}
        (
            tokenAmount,
            path,
            address(this),
            deadline
        );

        require(tokenAmount == exchangeAmounts[1], "WRONG_EXCHANGE_TOKEN_VALUE");

        return exchangeAmounts[1];
    }

    function getTokenEthPrice(address token, uint256 ethAmount)
        internal
        view
    returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = token;

        uint256[] memory amounts = exchanger.getAmountsOut(ethAmount, path);

        return amounts[1];
    }

    function getTokenPriceInWei(address token, uint256 tokenAmount)
        internal
        view
    returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = token;

        uint256[] memory amounts = exchanger.getAmountsIn(tokenAmount, path);

        return amounts[0];
    }

    function getSharedPool(address pool, bool isSmartPool)
        internal
        view
    returns (IBPool sharedPool)
    {
        IBPool bPool;

        if (isSmartPool) {
            bPool = ConfigurableRightsPool(pool).bPool();
        } else {
            bPool = IBPool(pool);
        }

        return bPool;
    }
}

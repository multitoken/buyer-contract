// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./external/BMath.sol";
import "./external/BPool.sol";
import "./external/ConfigurableRightsPool.sol";
import "./external/interfaces/IPancakeRouter01.sol";
import "./external/interfaces/IWETH.sol";

contract Buyer is Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address private _weth;
    address private _pancakeRouter;
    mapping(address => mapping(address => uint)) private _balances;

    constructor(address weth, address pancakeRouter) public {
        require(weth != address(0));
        require(pancakeRouter != address(0));
        _weth = weth;
        _pancakeRouter = pancakeRouter;
    }

    function buyUnderlyingAssets(
        address pool,
        uint slippage,
        uint deadline,
        bool isSmartPool
    )
        external
        payable
        nonReentrant
    {
        require(pool != address(0), "WRONG_POOL_ADDRESS");
        require(msg.value > 0, "WRONG_MSG_VALUE");

        address[] memory poolTokens = getTokensFromPool(pool, isSmartPool);

        for (uint i = 0; i < poolTokens.length; i++) {
            (uint weiForToken, uint spotPrice) = _calcWeiForToken(
                pool,
                isSmartPool,
                poolTokens[i],
                slippage
            );

            if (poolTokens[i] == _weth) {
                IWETH(_weth).deposit{value : weiForToken}();
                _balances[msg.sender][_weth] = _balances[msg.sender][_weth].add(weiForToken);
                continue;
            }

            address[] memory path = new address[](2);
            path[0] = _weth;
            path[1] = poolTokens[i];

            uint[] memory amounts = IPancakeRouter01(_pancakeRouter).swapETHForExactTokens{value: weiForToken}(
                msg.value.div(spotPrice),
                path,
                address(this),
                deadline
            );
            _balances[msg.sender][poolTokens[i]] = _balances[msg.sender][poolTokens[i]].add(amounts[1]);
        }

        msg.sender.transfer(address(this).balance);
    }

    function joinPool(
        address pool,
        bool isSmartPool,
        uint msgValue,
        uint slippage
    )
        external
        nonReentrant
    {
        require(pool != address(0));

        address[] memory poolTokens = getTokensFromPool(pool, isSmartPool);
        uint[] memory maxAmountsIn = new uint[](poolTokens.length);

        for (uint i = 0; i < poolTokens.length; i++) {
            maxAmountsIn[i] = _balances[msg.sender][poolTokens[i]];
            IERC20(poolTokens[i]).approve(pool, maxAmountsIn[i]);
        }

        uint poolAmountOut = _calcLPTAmount(pool, isSmartPool, msgValue, slippage);

        BPool(pool).joinPool(poolAmountOut, maxAmountsIn);
        IERC20(pool).safeTransfer(msg.sender, poolAmountOut);

        for (uint i = 0; i < poolTokens.length; i++) {
            uint currentAllowance = IERC20(poolTokens[i]).allowance(address(this), pool);
            _balances[msg.sender][poolTokens[i]] = currentAllowance;
        }
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

    function getTokensFromPool(address pool, bool isSmartPool)
        internal
        view
        returns (address[] memory tokens)
    {
        return getSharedPool(pool, isSmartPool).getCurrentTokens();
    }

    function getBalanceFromPool(address pool, bool isSmartPool, address token)
        internal
        view
        returns (uint)
    {
        return getSharedPool(pool, isSmartPool).getBalance(token);
    }

    function withdraw(address[] calldata tokens) external nonReentrant {
        for (uint i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(msg.sender, _balances[msg.sender][tokens[i]]);
            _balances[msg.sender][tokens[i]] = 0;
        }
    }

    function _calcSpotPrice(address poolToken, uint slippage)
        internal
        view
        returns (uint)
    {
        // Spot price - how much of tokenIn you have to pay for one of tokenOut.

        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = poolToken;

        uint[] memory amounts = IPancakeRouter01(_pancakeRouter).getAmountsIn(
            uint256(10) ** ERC20(poolToken).decimals(),
            path
        );

        return amounts[0].mul(100 + slippage).div(100);
    }

    function _calcWeiForToken(
        address[] memory poolTokens,
        uint slippage,
        uint value
    )
        internal
        view
        returns (uint[] memory, uint[] memory)
    {
        uint[] memory maxPrices = new uint[](poolTokens.length);
        uint maxPricesSum;
        uint[] memory weiForToken = new uint[](poolTokens.length);

        for (uint i = 0; i < poolTokens.length; i++) {
            uint maxPrice = _calcSpotPrice(poolTokens[i], slippage);
            maxPrices[i] = maxPrice;
            maxPricesSum = maxPricesSum.add(maxPrice);
        }

        for (uint i = 0; i < poolTokens.length; i++) {
            weiForToken[i] = value.mul(maxPrices[i]).div(maxPricesSum);
        }

        return (weiForToken, maxPrices);
    }

    function _calcLPTAmount(
        address pool,
        bool isSmartPool,
        uint msgValue,
        uint slippage
    )
        internal
        view
        returns (uint)
    {
        address[] memory poolTokens = getTokensFromPool(pool, isSmartPool);
        uint sumWeiForToken;

        for (uint i = 0; i < poolTokens.length; i++) {
            (uint weiForToken, uint spotPrice) = _calcWeiForToken(
                pool,
                isSmartPool,
                poolTokens[i],
                slippage
            );
            sumWeiForToken = sumWeiForToken.add(weiForToken);
        }

        return msgValue.div(sumWeiForToken);
    }

    function _calcWeiForToken(
        address pool,
        bool isSmartPool,
        address poolToken,
        uint slippage
    )
        internal
        view
        returns (uint, uint)
    {
        uint256 poolTotal = ERC20(pool).totalSupply();
        uint tokenBalance = getBalanceFromPool(pool, isSmartPool, poolToken);
        uint spotPrice = _calcSpotPrice(poolToken, slippage);
        uint weiForToken = tokenBalance.mul(spotPrice).div(poolTotal);

        return (spotPrice, weiForToken);
    }
}

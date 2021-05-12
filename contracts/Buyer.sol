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

pragma solidity 0.5.12;


import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./BMath.sol";
import "./BPool.sol";
import "./interfaces/IPancakeRouter01.sol";
import "./interfaces/IWETH.sol";

contract Buyer is Ownable, ReentrancyGuard, BMath {
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
        uint deadline
    )
        external
        payable
        nonReentrant
    {
        require(pool != address(0));

        address[] memory poolTokens = BPool(pool).getCurrentTokens();
        uint[] memory maxAmountsIn = new uint[](poolTokens.length);
        (uint[] memory weiForToken, uint[] memory maxPrices) = _calcWeiForToken(
            pool,
            poolTokens,
            slippage,
            msg.value
        );

        for (uint i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] == _weth) {
                IWETH(_weth).deposit.value(weiForToken[i])();
                _balances[msg.sender][_weth] = _balances[msg.sender][_weth].add(weiForToken[i]);
                continue;
            }

            address[] memory path = new address[](2);
            path[0] = _weth;
            path[1] = poolTokens[i];

            maxAmountsIn[i] = weiForToken[i].div(maxPrices[i]);
            uint[] memory amounts = IPancakeRouter01(_pancakeRouter).swapETHForExactTokens.value(weiForToken[i])(
                maxAmountsIn[i],
                path,
                address(this),
                deadline
            );
            _balances[msg.sender][poolTokens[i]] = _balances[msg.sender][poolTokens[i]].add(amounts[1]);
        }

        msg.sender.transfer(address(this).balance);
    }

    function joinPool(address pool) external nonReentrant {
        require(pool != address(0));
        address[] memory poolTokens = BPool(pool).getCurrentTokens();
        uint[] memory maxAmountsIn = new uint[](poolTokens.length);

        for (uint i = 0; i < poolTokens.length; i++) {
            maxAmountsIn[i] = _balances[msg.sender][poolTokens[i]];
            IERC20(poolTokens[i]).approve(pool, maxAmountsIn[i]);
        }

        uint poolAmountOut = _calcLPTAmount1(pool, poolTokens[0], maxAmountsIn[0]);
        BPool(pool).joinPool(poolAmountOut, maxAmountsIn);
        IERC20(pool).safeTransfer(msg.sender, poolAmountOut);

        for (uint i = 0; i < poolTokens.length; i++) {
            uint currentAllowance = IERC20(poolTokens[i]).allowance(address(this), pool);
            _balances[msg.sender][poolTokens[i]] = currentAllowance;
        }
    }

    function withdraw(address[] calldata tokens) external nonReentrant {
        for (uint i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(msg.sender, _balances[msg.sender][tokens[i]]);
            _balances[msg.sender][tokens[i]] = 0;
        }
    }

    function _calcTokenAmountIn(
        address pool,
        uint poolAmountOut,
        address poolToken
    )
        internal
        view
        returns (uint)
    {
        // Based on the BPool.joinPool
        BPool bPool = BPool(pool);
        uint poolTotal = bPool.totalSupply();
        uint ratio = bdiv(poolAmountOut, poolTotal);

        require(ratio != 0, "ERR_MATH_APPROX");

        return bmul(ratio, bPool.getBalance(poolToken));
    }

    function _calcMaxPrice(
        address pool,
        address poolToken,
        uint slippage
    )
        internal
        view
        returns (uint)
    {
        // Spot price - how much of tokenIn you have to pay for one of tokenOut.
        return 10**18;
    }

    function _calcWeiForToken(
        address pool,
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
            uint maxPrice = _calcMaxPrice(pool, poolTokens[i], slippage);
            maxPrices[i] = maxPrice;
            maxPricesSum = maxPricesSum.add(maxPrice);
        }

        for (uint i = 0; i < poolTokens.length; i++) {
            weiForToken[i] = value.mul(maxPrices[i]).div(maxPricesSum);
        }

        return (weiForToken, maxPrices);
    }

    function _calcLPTAmount1(
        address pool,
        address poolToken,
        uint tokenAmountIn
    )
        internal
        view
        returns (uint)
    {
        BPool bPool = BPool(pool);
        uint poolTotal = bPool.totalSupply();

        return bdiv(bmul(tokenAmountIn, bsub(poolTotal, 1)), badd(bPool.getBalance(poolToken), 1));
    }

    function _calcLPTAmount2(
        address pool,
        address poolToken,
        uint tokenAmountIn
    )
        internal
        view
        returns (uint)
    {
        BPool bPool = BPool(pool);
        uint poolTotal = bPool.totalSupply();

        return bdiv(bmul(poolTotal, tokenAmountIn), bPool.getBalance(poolToken));
    }
}

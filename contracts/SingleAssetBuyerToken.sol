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
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./SingleAssetBuyer.sol";

contract SingleAssetBuyerToken is Ownable, ReentrancyGuard, SingleAssetBuyer {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    constructor(address exchanger) SingleAssetBuyer(exchanger) public {}

    function calcMinPoolAmountOut(
        address pool,
        bool isSmartPool,
        address underlyingToken,
        address tokenIn,
        uint tokenAmountIn
    )
        external
        view
        returns (uint)
    {
        require(underlyingToken != _weth, "WRONG_UNDERLYING_TOKEN");

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = underlyingToken;

        uint[] memory amounts = _exchanger.getAmountsOut(tokenAmountIn, path);
        uint maxUnderlyingIn = _calcMaxTokenIn(pool, isSmartPool, underlyingToken);
        uint underlyingAmountIn = amounts[1];

        if (underlyingAmountIn > maxUnderlyingIn) {
            underlyingAmountIn = maxUnderlyingIn;
        }

        return calcPoolOutGivenSingleIn(pool, isSmartPool, underlyingToken, underlyingAmountIn);
    }

    function joinPool(
        address pool,
        bool isSmartPool,
        address underlyingToken,
        uint minPoolAmountOut,
        uint deadline,
        address tokenIn,
        uint tokenAmountIn
    )
        external
        nonReentrant
    {
        require(pool != address(0), "WRONG_POOL_ADDRESS");
        require(tokenIn != address(0), "WRONG_TOKEN_IN");
        require(tokenAmountIn > 0, "WRONG_TOKEN_AMOUNT_IN");
        require(underlyingToken != _weth, "WRONG_UNDERLYING_TOKEN");
        require(minPoolAmountOut > 0, "WRONG_MIN_POOL_AMOUNT_OUT");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenAmountIn);

        uint maxUnderlyingTokenIn = _calcMaxTokenIn(pool, isSmartPool, underlyingToken);
        uint joinAmountIn;

        if (tokenIn == underlyingToken) {
            if (maxUnderlyingTokenIn > tokenAmountIn) {
                joinAmountIn = tokenAmountIn;
            } else {
                joinAmountIn = maxUnderlyingTokenIn;
            }
        } else {
            IERC20(tokenIn).safeApprove(address(_exchanger), tokenAmountIn);

            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = underlyingToken;

            uint[] memory swapAmountsOut = _exchanger.getAmountsOut(tokenAmountIn, path);

            if (swapAmountsOut[1] > maxUnderlyingTokenIn) {
                uint[] memory amounts = _exchanger.swapTokensForExactTokens(
                    maxUnderlyingTokenIn,
                    tokenAmountIn,
                    path,
                    address(this),
                    deadline
                );
                joinAmountIn = amounts[1];
                IERC20(tokenIn).safeApprove(address(_exchanger), 0);
            } else {
                uint[] memory amounts = _exchanger.swapExactTokensForTokens(
                    tokenAmountIn,
                    1, // amountOutMin
                    path,
                    address(this),
                    deadline
                );
                joinAmountIn = amounts[1];
            }
        }

        IERC20(underlyingToken).safeApprove(pool, joinAmountIn);
        uint poolAmountOut = BPool(pool).joinswapExternAmountIn(
            underlyingToken, joinAmountIn, minPoolAmountOut
        );
        require(poolAmountOut >= minPoolAmountOut, "WRONG_POOL_AMOUNT_OUT");
        IERC20(pool).safeTransfer(msg.sender, poolAmountOut);
        IERC20(tokenIn).safeTransfer(msg.sender, IERC20(tokenIn).balanceOf(address(this)));
    }
}

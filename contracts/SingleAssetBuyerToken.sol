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

    constructor(address exchanger_) SingleAssetBuyer(exchanger_) public {}

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
        require(underlyingToken != weth, "WRONG_UNDERLYING_TOKEN");

        uint maxUnderlyingIn = _calcMaxTokenIn(pool, isSmartPool, underlyingToken);
        uint underlyingAmountIn;

        if (tokenIn == underlyingToken) {
            if (maxUnderlyingIn > tokenAmountIn) {
                underlyingAmountIn = tokenAmountIn;
            } else {
                underlyingAmountIn = maxUnderlyingIn;
            }
        } else {
            address[] memory tokenInToWeth = new address[](2);
            tokenInToWeth[0] = tokenIn;
            tokenInToWeth[1] = weth;
            uint wethAmountOut = exchanger.getAmountsOut(tokenAmountIn, tokenInToWeth)[1];

            address[] memory wethToUnderlying = new address[](2);
            wethToUnderlying[0] = weth;
            wethToUnderlying[1] = underlyingToken;
            uint underlyingAmountOut = exchanger.getAmountsOut(wethAmountOut, wethToUnderlying)[1];

            if (underlyingAmountOut > maxUnderlyingIn) {
                underlyingAmountIn = maxUnderlyingIn;
            } else {
                underlyingAmountIn = underlyingAmountOut;
            }
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
        require(underlyingToken != weth, "WRONG_UNDERLYING_TOKEN");
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
            address[] memory tokenInToWeth = new address[](2);
            tokenInToWeth[0] = tokenIn;
            tokenInToWeth[1] = weth;
            uint wethAmountOut = exchanger.getAmountsOut(tokenAmountIn, tokenInToWeth)[1];

            address[] memory wethToUnderlying = new address[](2);
            wethToUnderlying[0] = weth;
            wethToUnderlying[1] = underlyingToken;
            uint underlyingAmountOut = exchanger.getAmountsOut(wethAmountOut, wethToUnderlying)[1];

            IERC20(tokenIn).safeApprove(address(exchanger), tokenAmountIn);
            IERC20(weth).safeApprove(address(exchanger), wethAmountOut);

            if (underlyingAmountOut > maxUnderlyingTokenIn) {
                uint[] memory amounts;

                amounts = exchanger.swapTokensForExactTokens(
                    wethAmountOut, // amountOut
                    tokenAmountIn, // amountInMax
                    tokenInToWeth,
                    address(this),
                    deadline
                );
                amounts = exchanger.swapTokensForExactTokens(
                    maxUnderlyingTokenIn, // amountOut
                    wethAmountOut, // amountInMax
                    wethToUnderlying,
                    address(this),
                    deadline
                );
                joinAmountIn = amounts[1];
                IERC20(tokenIn).safeApprove(address(exchanger), 0);
                IERC20(weth).safeApprove(address(exchanger), 0);
            } else {
                uint[] memory amounts;

                amounts = exchanger.swapExactTokensForTokens(
                    tokenAmountIn, // amountIn
                    1, // amountOutMin
                    tokenInToWeth,
                    address(this),
                    deadline
                );
                amounts = exchanger.swapExactTokensForTokens(
                    amounts[1], // amountIn
                    1, // amountOutMin
                    wethToUnderlying,
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
        IERC20(weth).safeTransfer(msg.sender, IERC20(weth).balanceOf(address(this)));
    }
}

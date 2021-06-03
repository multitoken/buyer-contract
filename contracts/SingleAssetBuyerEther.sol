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

contract SingleAssetBuyerEther is Ownable, ReentrancyGuard, SingleAssetBuyer {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    constructor(address exchanger) SingleAssetBuyer(exchanger) public {}

    function calcMinPoolAmountOut(
        address pool,
        bool isSmartPool,
        address underlyingToken,
        uint weiAmountIn
    )
        external
        view
        returns (uint)
    {
        require(underlyingToken != _weth, "WRONG_UNDERLYING_TOKEN");

        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = underlyingToken;

        uint[] memory amounts = _exchanger.getAmountsOut(weiAmountIn, path);
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
        uint deadline
    )
        external
        payable
        nonReentrant
    {
        require(pool != address(0), "WRONG_POOL_ADDRESS");
        require(msg.value > 0, "WRONG_MSG_VALUE");
        require(underlyingToken != _weth, "WRONG_UNDERLYING_TOKEN");

        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = underlyingToken;

        uint maxTokenIn = _calcMaxTokenIn(pool, isSmartPool, underlyingToken);
        uint[] memory swapAmountsOut = _exchanger.getAmountsOut(msg.value, path);
        uint[] memory amounts;

        if (swapAmountsOut[1] > maxTokenIn) {
            amounts = _exchanger.swapETHForExactTokens{value: msg.value}(
                maxTokenIn,
                path,
                address(this),
                deadline
            );
        } else {
            amounts = _exchanger.swapExactETHForTokens{value: msg.value}(
                1,
                path,
                address(this),
                deadline
            );
        }

        IERC20(underlyingToken).safeIncreaseAllowance(pool, amounts[1]);
        uint poolAmountOut = BPool(pool).joinswapExternAmountIn(
            underlyingToken, amounts[1], minPoolAmountOut
        );
        require(poolAmountOut >= minPoolAmountOut, "WRONG_POOL_AMOUNT_OUT");
        IERC20(pool).safeTransfer(msg.sender, poolAmountOut);
        msg.sender.transfer(address(this).balance);
    }
}

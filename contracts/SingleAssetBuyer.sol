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
import "./SharedPoolBuyer.sol";

contract SingleAssetBuyer is Ownable, ReentrancyGuard, SharedPoolBuyer, BConst {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address private _weth;
    IPancakeRouter01 private _exchanger;

    constructor(address exchanger) public {
        require(exchanger != address(0));

        _exchanger = IPancakeRouter01(exchanger);
        _weth = _exchanger.WETH();
    }

    function chooseUnderlyingToken(address pool, bool isSmartPool)
        external
        view
        returns (address)
    {
        address[] memory poolTokens = getTokensFromPool(pool, isSmartPool);
        address resultToken;
        uint resultPoolAmountOut;

        for (uint i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] == _weth) {
                continue;
            }

            address[] memory path = new address[](2);
            path[0] = _weth;
            path[1] = poolTokens[i];

            uint[] memory amounts = _exchanger.getAmountsOut(1, path);
            uint poolAmountOut = calcPoolOutGivenSingleIn(
                pool, isSmartPool, poolTokens[i], amounts[1]
            );

            if (resultToken == address(0) || resultPoolAmountOut == 0) {
                resultToken = poolTokens[i];
                resultPoolAmountOut = poolAmountOut;
                continue;
            }

            if (poolAmountOut > resultPoolAmountOut) {
                resultToken = poolTokens[i];
                resultPoolAmountOut = poolAmountOut;
            }
        }

        return resultToken;
    }

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
        uint poolAmountOut = calcPoolOutGivenSingleIn(
            pool, isSmartPool, underlyingToken, amounts[1]
        );

        return poolAmountOut;
    }

    function joinPool(
        address pool,
        bool /*isSmartPool*/,
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

        uint[] memory amounts = _exchanger.swapExactETHForTokens{value: msg.value}(
            1,
            path,
            address(this),
            deadline
        );

        IERC20(underlyingToken).safeIncreaseAllowance(pool, amounts[1]);
        uint poolAmountOut = BPool(pool).joinswapExternAmountIn(
            underlyingToken, amounts[1], minPoolAmountOut
        );
        require(poolAmountOut >= minPoolAmountOut, "WRONG_POOL_AMOUNT_OUT");
        IERC20(pool).safeTransfer(msg.sender, poolAmountOut);
        msg.sender.transfer(address(this).balance);
    }
}

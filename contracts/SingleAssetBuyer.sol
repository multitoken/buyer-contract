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

import "./SharedPoolBuyer.sol";
import "./external/BMath.sol";
import "./external/BPool.sol";
import "./external/interfaces/IPancakeRouter01.sol";

contract SingleAssetBuyer is SharedPoolBuyer, BConst, BMath {
    address public weth;
    IPancakeRouter01 public exchanger;

    event Received(address sender, uint amount);

    constructor(address exchanger_) public {
        require(exchanger_ != address(0));

        exchanger = IPancakeRouter01(exchanger_);
        weth = exchanger.WETH();
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
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
            if (poolTokens[i] == weth) {
                continue;
            }

            address[] memory path = new address[](2);
            path[0] = weth;
            path[1] = poolTokens[i];

            uint[] memory amounts = exchanger.getAmountsOut(1, path);
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

    function _calcMaxTokenIn(
        address pool,
        bool isSmartPool,
        address underlyingToken
    )
        internal
        view
        returns (uint)
    {
        uint balance = getBalanceFromPool(pool, isSmartPool, underlyingToken);
        return bmul(balance, MAX_IN_RATIO);
    }
}

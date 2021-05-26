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


import "./external/ConfigurableRightsPool.sol";

contract SharedPoolBuyer {
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

    function getDenormalizedWeight(address pool, bool isSmartPool, address token)
        internal
        view
        returns (uint)
    {
        return getSharedPool(pool, isSmartPool).getDenormalizedWeight(token);
    }

    function getTotalDenormalizedWeight(address pool, bool isSmartPool)
        internal
        view
        returns (uint)
    {
        return getSharedPool(pool, isSmartPool).getTotalDenormalizedWeight();
    }

    function getSwapFeeFromPool(address pool, bool isSmartPool)
        internal
        view
        returns (uint)
    {
        return getSharedPool(pool, isSmartPool).getSwapFee();
    }

    function getBalanceFromPool(address pool, bool isSmartPool, address token)
        internal
        view
        returns (uint)
    {
        return getSharedPool(pool, isSmartPool).getBalance(token);
    }

    function calcPoolOutGivenSingleIn(address pool, bool isSmartPool, address tokenIn, uint amountIn)
        internal
        view
        returns (uint)
    {
        IBPool bPool = getSharedPool(pool, isSmartPool);

        return bPool.calcPoolOutGivenSingleIn(
            bPool.getBalance(tokenIn),
            bPool.getDenormalizedWeight(tokenIn),
            ERC20(pool).totalSupply(),
            bPool.getTotalDenormalizedWeight(),
            amountIn,
            bPool.getSwapFee()
        );
    }
}

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
    IPancakeRouter01 private _exchanger;
    mapping(address => mapping(address => uint)) private _balances;

    constructor(address exchanger) public {
        require(exchanger != address(0));

        _exchanger = IPancakeRouter01(exchanger);
        _weth = _exchanger.WETH();
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
        (
            uint lpTokensTotal,
            uint[] memory maxAmountsIn,
            uint[] memory spotPrices
        ) = _calcJoinPoolData(pool, isSmartPool, slippage, msg.value);

        for (uint i = 0; i < poolTokens.length; i++) {
            uint weiForTokens = maxAmountsIn[i].mul(spotPrices[i]);

            if (poolTokens[i] == _weth) {
                IWETH(_weth).deposit{value: weiForTokens}();
                _balances[msg.sender][_weth] = _balances[msg.sender][_weth].add(weiForTokens);
                continue;
            }

            address[] memory path = new address[](2);
            path[0] = _weth;
            path[1] = poolTokens[i];

            require(spotPrices[i] > 0, "WRONG_SPOT_PRICE");
            require(address(this).balance >= weiForTokens, "WRONG_BALANCE");
            require(weiForTokens > spotPrices[i], "WRONG_WEI_FOR_TOKENS");
            require(maxAmountsIn[i] > 0, "WRONG_MAX_AMOUNTS_IN");
            uint[] memory amounts = _exchanger.swapExactETHForTokens{value: weiForTokens}(
                1,
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
        (
            uint lpTokensTotal,
            uint[] memory maxAmountsIn,
            uint[] memory spotPrices
        ) = _calcJoinPoolData(pool, isSmartPool, slippage, msgValue);

        for (uint i = 0; i < poolTokens.length; i++) {
            IERC20(poolTokens[i]).approve(pool, maxAmountsIn[i]);
        }

        BPool(pool).joinPool(lpTokensTotal, maxAmountsIn);
        IERC20(pool).safeTransfer(msg.sender, lpTokensTotal);

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

    function _calcJoinPoolData(
        address pool,
        bool isSmartPool,
        uint slippage,
        uint msgValue
    )
        internal
        view
        returns (uint, uint[] memory, uint[] memory)
    {
        (
            uint weiForOneLPT,
            uint[] memory spotPrices,
            uint[] memory balances
        ) = _calcWeiForOneLPT(pool, isSmartPool, slippage);
        uint lpTokensTotal = msgValue.div(weiForOneLPT);
        uint totalSupply = ERC20(pool).totalSupply();

        address[] memory poolTokens = getTokensFromPool(pool, isSmartPool);
        uint[] memory maxAmountsIn = new uint[](poolTokens.length);

        for (uint i = 0; i < poolTokens.length; i++) {
            maxAmountsIn[i] = balances[i].mul(lpTokensTotal).div(totalSupply);
        }

        return (lpTokensTotal, maxAmountsIn, spotPrices);
    }

    function _calcWeiForOneLPT(
        address pool,
        bool isSmartPool,
        uint slippage
    )
        internal
        view
        returns (uint, uint[] memory, uint[] memory)
    {
        uint weiForOneLPT = 0;
        IBPool bPool = getSharedPool(pool, isSmartPool);
        uint totalSupply = ERC20(pool).totalSupply();
        address[] memory poolTokens = getTokensFromPool(pool, isSmartPool);
        uint[] memory spotPrices = new uint[](poolTokens.length);
        uint[] memory balances = new uint[](poolTokens.length);

        for (uint i = 0; i < poolTokens.length; i++) {
            spotPrices[i] = _calcSpotPrice(poolTokens[i], slippage);
            balances[i] = bPool.getBalance(poolTokens[i]);
            weiForOneLPT = weiForOneLPT.add(balances[i].mul(spotPrices[i]).div(totalSupply));
        }

        return (weiForOneLPT, spotPrices, balances);
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

        uint[] memory amounts = _exchanger.getAmountsIn(uint(10) ** uint(ERC20(poolToken).decimals()), path);

        return amounts[0].mul(100 + slippage).div(100);
    }
}

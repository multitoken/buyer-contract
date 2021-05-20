pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import './interfaces/IWETH.sol';

contract PancakeRouterMock {
    using SafeMath for uint;

    address public WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'PancakeRouter: EXPIRED');
        _;
    }

    constructor(address _WETH) public {
        WETH = _WETH;
    }

//    function swapExactETHForTokensSupportingFeeOnTransferTokens(
//        uint amountOutMin,
//        address[] calldata path,
//        address to,
//        uint deadline
//    )
//        external
//        virtual
//        override
//        payable
//        ensure(deadline)
//    {
//        require(path[0] == WETH, 'PancakeRouter: INVALID_PATH');
//        uint amountIn = msg.value;
//        IWETH(WETH).deposit{value : amountIn}();
//        assert(IWETH(WETH).transfer(PancakeLibrary.pairFor(factory, path[0], path[1]), amountIn));
//        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
//        _swapSupportingFeeOnTransferTokens(path, to);
//        require(
//            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
//            'PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT'
//        );
//    }

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'PancakeRouter: INVALID_PATH');
        require(amountOut > 0, 'EXCHANGER_WRONG_AMOUNT_OUT');
        require(msg.value > 0, 'EXCHANGER_WRONG_AMOUNT_IN');

        uint[] memory amounts = new uint[](2);
        amounts[0] = msg.value;
        amounts[1] = amountOut;

        IERC20(path[1]).transfer(msg.sender, amountOut);

        return amounts;
    }

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'PancakeRouter: INVALID_PATH');
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        IERC20(path[1]).transfer(to, amounts[1]);
    }

    function getAmountsIn(uint amountOut, address[] calldata path)
        external
        view
        returns (uint[] memory amounts)
    {
        require(path.length >= 2, 'PancakeLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;

        uint reserveIn = ERC20(path[0]).balanceOf(address(this));
        uint reserveOut = ERC20(path[1]).balanceOf(address(this));

        amounts[0] = getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'PancakeLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;

        uint reserveIn = ERC20(path[0]).balanceOf(address(this));
        uint reserveOut = ERC20(path[1]).balanceOf(address(this));

        amounts[1] = getAmountOut(amounts[0], reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'PancakeLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(998);
        amountIn = (numerator / denominator).add(1);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'PancakeLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(998);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function withdraw(address token) external {
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, balance);
    }
}
//function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
//external
//virtual
//override
//payable
//ensure(deadline)
//returns (uint[] memory amounts)
//{
//require(path[0] == WETH, 'PancakeRouter: INVALID_PATH');
//amounts = PancakeLibrary.getAmountsIn(factory, amountOut, path);
//require(amounts[0] <= msg.value, 'PancakeRouter: EXCESSIVE_INPUT_AMOUNT');
//IWETH(WETH).deposit{value: amounts[0]}();
//assert(IWETH(WETH).transfer(PancakeLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
//_swap(amounts, path, to);
//// refund dust eth, if any
//if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
//}

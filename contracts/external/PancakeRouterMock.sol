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

        uint[] memory amountsResult = new uint[](2);
        amountsResult[0] = msg.value;
        amountsResult[1] = amountOut;

        IERC20(path[1]).transfer(msg.sender, amountOut);

        return amountsResult;
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

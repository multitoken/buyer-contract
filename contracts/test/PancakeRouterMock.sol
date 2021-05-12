pragma solidity ^0.5.12;

import "@openzeppelin/contracts/math/SafeMath.sol";

import '../interfaces/IERC20.sol';
import '../interfaces/IWETH.sol';

contract PancakeRouterMock {
    using SafeMath for uint;

    address public factory;
    address public WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'PancakeRouter: EXPIRED');
        _;
    }

    constructor(address _WETH) public {
        WETH = _WETH;
    }

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'PancakeRouter: INVALID_PATH');
        uint[] memory amounts = new uint[](2);
        address(0x0).send(msg.value.mul(90).div(100));
        IERC20(path[1]).transfer(msg.sender, amountOut);
        address(msg.sender).send(address(this).balance);
        return amounts;
    }
}

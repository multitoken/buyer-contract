pragma solidity 0.6.12;

interface IPool {
    function totalSupply() external view returns (uint);

    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn) external;
}

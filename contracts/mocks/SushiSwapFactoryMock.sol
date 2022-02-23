// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../uniswapv2/UniswapV2Factory.sol";

contract SushiSwapFactoryMock is OracleSwapFactory {
    constructor(address _feeToSetter) public OracleSwapFactory(_feeToSetter) {}
}
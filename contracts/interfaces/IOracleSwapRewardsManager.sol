// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOracleSwapRewardsManager {
    function wnat() external returns (address);

    function ftsoManager() external returns (address);

    function ftsoRewardManager() external returns (address);

    function flareContractRegistry() external returns (address);

    function ftsoProvider() external returns (address);
}

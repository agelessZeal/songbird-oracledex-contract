// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OracleSwapRewardsManager is Ownable {
    address public wnat;
    address public ftsoManager;
    address public ftsoRewardManager;

    address public ftsoProvider;

    address public flareContractRegistry;

    constructor(
        address _wnat,
        address _ftsoManager,
        address _ftsoRewardManager,
        address _flareContractRegistry
    ) {
        wnat = _wnat;
        ftsoManager = _ftsoManager;
        ftsoRewardManager = _ftsoRewardManager;
        flareContractRegistry = _flareContractRegistry;
    }

    
}

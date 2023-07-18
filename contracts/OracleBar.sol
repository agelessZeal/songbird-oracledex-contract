// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// OracleBar is the coolest bar in town.
// You come in with some Oracle, and leave with more!
// The longer you stay, the more Oracle you get.
//
// This contract handles swapping to and from xORACLE, SushiSwap's staking token.
contract OracleBar is ERC20("OracleBar", "xORACLE") {
    using SafeMath for uint256;
    IERC20 public oracle;

    // Define the Oracle token contract
    constructor(IERC20 _oracle) {
        oracle = _oracle;
    }

    // Enter the bar. Pay some ORACLEs. Earn some shares.
    // Locks Oracle and mints xORACLE
    function enter(uint256 _amount) public {
        // Gets the amount of Oracle locked in the contract
        uint256 totalSushi = oracle.balanceOf(address(this));
        // Gets the amount of xORACLE in existence
        uint256 totalShares = totalSupply();
        // If no xORACLE exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalSushi == 0) {
            _mint(msg.sender, _amount);
        }
        // Calculate and mint the amount of xORACLE the Oracle is worth. 
        //The ratio will change overtime, as xORACLE is burned/minted and
        // Oracle deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount.mul(totalShares).div(totalSushi);
            _mint(msg.sender, what);
        }
        // Lock the Oracle in the contract
        oracle.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the bar. Claim back your ORACLEs.
    // Unlocks the staked + gained Oracle and burns xORACLE
    function leave(uint256 _share) public {
        // Gets the amount of xORACLE in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Oracle the xORACLE is worth
        uint256 what = _share.mul(oracle.balanceOf(address(this))).div(
            totalShares
        );
        _burn(msg.sender, _share);
        oracle.transfer(msg.sender, what);
    }
}

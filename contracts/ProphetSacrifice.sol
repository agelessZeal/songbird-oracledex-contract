// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "./libraries/SafeERC20.sol";

import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./Ownable.sol";

contract ProphetSacrifice is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public immutable factory;

    address public immutable oracle;

    address public immutable prophet;

    address public immutable wsgb;

    address public prophetStaker;

    address public prophetStakerSetter;

    uint256 public proPercentage = 20;


    address public constant deadAddress =
        0x000000000000000000000000000000000000dEaD;

    event BurnPro(uint256 amount);

    event ProToStake(uint256 amount);

    uint256 public totalBurnPro = 0;

    uint256 public totalStakePro = 0;

    modifier onlyHolder() {
        require(IERC20(oracle).balanceOf(msg.sender) > 0, "should hold oracle");
        _;
    }

    constructor(
        address _factory,
        address _oracle,
        address _wsgb,
        address _prophet
    ) public {
        factory = IUniswapV2Factory(_factory);
        oracle = _oracle;
        wsgb = _wsgb;
        prophet = _prophet;

        prophetStakerSetter = address(msg.sender);
    }

    function setProPercetange(uint256 _percent) external onlyOwner {
        require(_percent <= 100 && _percent >= 0, "Wrong percent");
        proPercentage = _percent;
    }

    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "ProphetSacrifice: must use EOA");
        _;
    }

    function burnPro() external onlyEOA onlyHolder {
        uint256 oracleBalance = IERC20(oracle).balanceOf(address(this));

        uint256 amountSgb = _swap(oracle, wsgb, oracleBalance, address(this));

        uint256 _amount = _swap(wsgb, prophet, amountSgb, address(this));

        uint256 amountPro = _amount.div(100).mul(99);

        if (prophetStaker != address(0) && proPercentage != 0) {
            uint256 stakerAmount = amountPro.mul(proPercentage).div(100);

            IERC20(address(prophet)).safeTransfer(prophetStaker, stakerAmount);

            emit ProToStake(stakerAmount);

            totalStakePro = totalStakePro.add(stakerAmount);

            uint256 burnAmount = amountPro.sub(stakerAmount);

            IERC20(address(prophet)).safeTransfer(deadAddress, burnAmount);

            totalBurnPro = totalBurnPro.add(burnAmount);

            emit BurnPro(burnAmount);
        } else {
            IERC20(address(prophet)).safeTransfer(deadAddress, amountPro);

            emit BurnPro(amountPro);

            totalBurnPro = totalBurnPro.add(amountPro);
        }
    }


    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        // Checks
        IUniswapV2Pair pair = IUniswapV2Pair(
            factory.getPair(fromToken, toToken)
        );
        require(
            address(pair) != address(0),
            "ProphetSacrifice: Cannot convert"
        );

        // Interactions
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut =
                amountInWithFee.mul(reserve1) /
                reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);

            try pair.swap(0, amountOut, to, new bytes(0)) {} catch (
                bytes memory /** */
            ) {}

            // TODO: Add maximum slippage?
        } else {
            amountOut =
                amountInWithFee.mul(reserve0) /
                reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);

            try pair.swap(amountOut, 0, to, new bytes(0)) {} catch (
                bytes memory /** */
            ) {}

            // TODO: Add maximum slippage?
        }
    }

    function setProphetStaker(address _proStaker) external {
        require(
            msg.sender == prophetStakerSetter,
            "ProphetSacrifice: FORBIDDEN"
        );
        prophetStaker = _proStaker;
    }

    function setProphetStakerSetter(address _newSetter) external {
        require(
            msg.sender == prophetStakerSetter,
            "ProphetSacrifice: FORBIDDEN"
        );
        prophetStakerSetter = _newSetter;
    }
}

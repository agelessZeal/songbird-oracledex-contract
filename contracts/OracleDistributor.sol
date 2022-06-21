// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity 0.6.12;
import "./libraries/SafeERC20.sol";

import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./Ownable.sol";

// OracleDistributor is MasterChef's left hand and kinda a wizard. He can cook up Oracle from pretty much anything!
// This contract handles "serving up" rewards for xOracle holders by trading tokens collected from fees for Oracle.

// T1 - T4: OK
contract OracleDistributor is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public immutable factory;

    address public immutable xOracle;

    address private immutable oracle;
    //0x6B3595068778DD592e39A122f4f5a5cF09C90fE2
    // V1 - V5: OK
    address private immutable weth;
    //0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2


    address public  oracleTreasurySetter;

    uint256 public MIN_LP_AMOUNT = 0.03 * 10**18;

    // V1 - V5: OK
    mapping(address => address) internal _bridges;

    // E1: OK
    event LogBridgeSet(address indexed token, address indexed bridge);
    // E1: OK
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountORACLE
    );

    address public  oracleTreasury;
    address public  constant deadAddress = 0x000000000000000000000000000000000000dEaD;

    modifier onlyHolder() {
        require(IERC20(oracle).balanceOf(msg.sender) > 0,"should hold oracle");
        _;
    }

    constructor(
        address _factory,
        address _xOracle,
        address _oracle,
        address _weth,
        address _oracleFoundry
    ) public {
        factory = IUniswapV2Factory(_factory);
        xOracle = _xOracle;
        oracle = _oracle;
        weth = _weth;
        oracleFoundry = _oracleFoundry;
    }

    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    function setBridge(address token, address bridge) external onlyOwner {
        // Checks
        require(
            token != oracle && token != weth && token != bridge,
            "OracleDistributor: Invalid bridge"
        );

        // Effects
        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    function setMinLPAmount(uint256 _amount) external onlyOwner {
        MIN_LP_AMOUNT = _amount;
    }

    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "OracleDistributor: must use EOA");
        _;
    }

    function LPConvert() external onlyEOA() onlyHolder {
        uint256 len = factory.allPairsLength();

        for (uint256 i = 0; i < len; i++) {
            IUniswapV2Pair pair = IUniswapV2Pair(factory.allPairs(i));
            uint256 lpBalance = pair.balanceOf(address(this));
            if(lpBalance > MIN_LP_AMOUNT ){
                _convert(pair.token0(), pair.token1());
            }
        }
    }

    function LPEnalbe() external view returns (bool)  {
        uint256 len = factory.allPairsLength();
        for (uint256 i = 0; i < len; i++) {
            IUniswapV2Pair pair = IUniswapV2Pair(factory.allPairs(i));
            uint256 lpBalance = pair.balanceOf(address(this));
            if(lpBalance > MIN_LP_AMOUNT ){
                return true;
            }
        }
        return false;
    }

    // F1 - F10: OK
    // F3: _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    // F6: There is an exploit to add lots of ORACLE to the xOracle, run convert, then remove the ORACLE again.
    //     As the size of the xOracle has grown, this requires large amounts of funds and isn't super profitable anymore
    //     The onlyEOA modifier prevents this being done with a flash loan.
    // C1 - C24: OK
    function convert(address token0, address token1) external onlyEOA()  onlyHolder {
        _convert(token0, token1);
    }

    // F1 - F10: OK, see convert
    // C1 - C24: OK
    // C3: Loop is under control of the caller
    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1
    ) external onlyEOA()  onlyHolder {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    // F1 - F10: OK
    // C1- C24: OK
    function _convert(address token0, address token1) internal {
        // Interactions
        // S1 - S4: OK
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        require(address(pair) != address(0), "OracleDistributor: Invalid pair");
        // balanceOf: S1 - S4: OK
        // transfer: X1 - X5: OK
        IERC20(address(pair)).safeTransfer(
            address(pair),
            pair.balanceOf(address(this))
        );
        // X1 - X5: OK
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        if (token0 != pair.token0()) {
            (amount0, amount1) = (amount1, amount0);
        }
        emit LogConvert(
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            _convertStep(token0, token1, amount0, amount1)
        );
    }

    // F1 - F10: OK
    // C1 - C24: OK
    // All safeTransfer, _swap, _toORACLE, _convertStep: X1 - X5: OK
    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 oracleOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == oracle) {
                IERC20(oracle).safeTransfer(xOracle, amount);
                oracleOut = amount;
            } else if (token0 == weth) {
                oracleOut = _toORACLE(weth, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                oracleOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == oracle) {
            // eg. ORACLE - ETH
            IERC20(oracle).safeTransfer(xOracle, amount0);
            oracleOut = _toORACLE(token1, amount1).add(amount0);
        } else if (token1 == oracle) {
            // eg. USDT - ORACLE
            IERC20(oracle).safeTransfer(xOracle, amount1);
            oracleOut = _toORACLE(token0, amount0).add(amount1);
        } else if (token0 == weth) {
            // eg. ETH - USDC
            oracleOut = _toORACLE(
                weth,
                _swap(token1, weth, amount1, address(this)).add(amount0)
            );
        } else if (token1 == weth) {
            // eg. USDT - ETH
            oracleOut = _toORACLE(
                weth,
                _swap(token0, weth, amount0, address(this)).add(amount1)
            );
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                oracleOut = _convertStep(
                    bridge0,
                    token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                oracleOut = _convertStep(
                    token0,
                    bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                oracleOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    // All safeTransfer, swap: X1 - X5: OK
    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        // Checks
        // X1 - X5: OK
        IUniswapV2Pair pair =
            IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "OracleDistributor: Cannot convert");

        // Interactions
        // X1 - X5: OK
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut =
                amountInWithFee.mul(reserve1) /
                reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut =
                amountInWithFee.mul(reserve0) /
                reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
            // TODO: Add maximum slippage?
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function _toORACLE(address token, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        // X1 - X5: OK
        if(oracleTreasury  != address(0)){
            amountOut = _swap(token, oracle, amountIn.mul(7).div(10), xOracle);
            amountOut = _swap(token, oracle, amountIn.mul(2).div(10), oracleTreasury);
            amountOut = _swap(token, oracle, amountIn.div(10), deadAddress);
        }else{
            amountOut = _swap(token, oracle, amountIn.mul(8).div(10), xOracle);
            amountOut = _swap(token, oracle, amountIn.mul(2).div(10), deadAddress);
        }
        // amountOut = _swap(token, oracle, amountIn, xOracle);
    }

    function setOracleTreasury (address _treasury)  external  {
        require(msg.sender == oracleTreasurySetter, 'OracleDistributor: FORBIDDEN');
        oracleTreasury = _treasury;
    }



    function setOracleTreasurySetter (address _oracleTreasurySetter) external {
        require(msg.sender == oracleTreasurySetter, 'OracleDistributor: FORBIDDEN');
        oracleTreasurySetter = _oracleTreasurySetter;
    }
}

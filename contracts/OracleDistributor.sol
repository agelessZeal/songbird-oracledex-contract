// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity 0.6.12;
import "./libraries/SafeERC20.sol";

import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./Ownable.sol";


// T1 - T4: OK
contract OracleDistributor is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public immutable factory;

    address public immutable xOracle;

    address private immutable oracle;

    address private immutable weth;

    address public  oracleTreasurySetter;

    uint256 public MIN_LP_AMOUNT = 0.003 * 10**18;

    uint256 public limit_gas = 80000;

    uint256 public oracleFoundryTotalAmount = 0;
    uint256 public oracleTreasuryTotalAmount = 0;
    uint256 public oracleBurnTotalAmount = 0;
    uint256 public oracleTotalAmount = 0;

    bool private onlyOracleLp = true;

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

    event FoundryConvert(
        uint256 amountORACLE
    );

    event TreasuryConvert(
        uint256 amountORACLE
    );

    event BurnConvert(
        uint256 amountORACLE
    );

    event TotalConvert(
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
        address _weth
    ) public {
        factory = IUniswapV2Factory(_factory);
        xOracle = _xOracle;
        oracle = _oracle;
        weth = _weth;
        oracleTreasurySetter = address(msg.sender);
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

    function setGasLimit(uint256 _limit_gas) external onlyOwner {
        limit_gas = _limit_gas;
    }

    function setOracleLPEnable(bool _onlyOracleLp) external onlyOwner {
        onlyOracleLp = _onlyOracleLp;
    }

    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "OracleDistributor: must use EOA");
        _;
    }

    function LPConvert() external onlyEOA() onlyHolder {
        uint256 len = factory.allPairsLength();

        uint256 gasUsed = 0;

        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while (gasUsed < limit_gas && iterations < len) {

            IUniswapV2Pair pair = IUniswapV2Pair(factory.allPairs(iterations));
            uint256 lpBalance = pair.balanceOf(address(this));

            if(lpBalance > MIN_LP_AMOUNT ){
                if(onlyOracleLp){
                   if(pair.token0() == oracle || pair.token0() == weth || pair.token1()== oracle || pair.token1() == weth){
                      _convert(pair.token0(), pair.token1());
                   }
                }else{
                    _convert(pair.token0(), pair.token1());
                }
            }
            
            iterations++;

            uint256 newGasLeft = gasleft();

            if (gasLeft > newGasLeft) {
                gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
            }

            gasLeft = newGasLeft;
        }
    }

    function LPEnalbe() external view returns (bool)  {
        uint256 len = factory.allPairsLength();
        for (uint256 i = 0; i < len; i++) {
            IUniswapV2Pair pair = IUniswapV2Pair(factory.allPairs(i));
            uint256 lpBalance = pair.balanceOf(address(this));
            if(lpBalance > MIN_LP_AMOUNT ){
                if(onlyOracleLp){
                   if(pair.token0() == oracle || pair.token0() == weth || pair.token1()== oracle || pair.token1() == weth){
                      return true;
                   }
                }else{
                    return true;
                }
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

    function _convert(address token0, address token1) internal {
        // Interactions
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        require(address(pair) != address(0), "OracleDistributor: Invalid pair");
        IERC20(address(pair)).safeTransfer(
            address(pair),
            pair.balanceOf(address(this))
        );
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

    // All safeTransfer, _swap, _toORACLE, _convertStep
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

    // All safeTransfer, swap: X1 - X5: OK
    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        // Checks
        IUniswapV2Pair pair =
            IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "OracleDistributor: Cannot convert");

        // Interactions
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

    function _toORACLE(address token, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {

        if(oracleTreasury  != address(0)){
            uint256 foundryAmount = _swap(token, oracle, amountIn.mul(7).div(10), xOracle);
            oracleFoundryTotalAmount =  oracleFoundryTotalAmount.add(foundryAmount);
            uint256 treasuryAmount = _swap(token, oracle, amountIn.mul(2).div(10), oracleTreasury);
            oracleTreasuryTotalAmount =  oracleTreasuryTotalAmount.add(treasuryAmount);
            uint256 burnAmount = _swap(token, oracle, amountIn.div(10), deadAddress);
            oracleBurnTotalAmount =  oracleBurnTotalAmount.add(burnAmount);
            amountOut = foundryAmount.add(treasuryAmount).add(burnAmount);
            oracleTotalAmount = oracleTotalAmount.add(amountOut);

            emit FoundryConvert(foundryAmount);
            emit TreasuryConvert(treasuryAmount);
            emit BurnConvert(burnAmount);
            emit TotalConvert(amountOut);

        }else{
            uint256 foundryAmount = _swap(token, oracle, amountIn.mul(8).div(10), xOracle);
            oracleFoundryTotalAmount =  oracleFoundryTotalAmount.add(foundryAmount);
            uint256 burnAmount  = _swap(token, oracle, amountIn.mul(2).div(10), deadAddress);
            oracleBurnTotalAmount =  oracleBurnTotalAmount.add(burnAmount);
            amountOut = foundryAmount.add(burnAmount);
            oracleTotalAmount = oracleTotalAmount.add(amountOut);
            
            emit FoundryConvert(foundryAmount);
            emit BurnConvert(burnAmount);
            emit TotalConvert(amountOut);
        }
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

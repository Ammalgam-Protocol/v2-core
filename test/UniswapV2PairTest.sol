// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';

import '../contracts/UniswapV2Pair.sol';
import '../contracts/UniswapV2Factory.sol';
import '../contracts/interfaces/IERC20.sol';
import './shared/utilities.sol';

contract UniswapV2PairTest is Test {
    IUniswapV2Factory private factory;
    IUniswapV2Pair private pair;
    IERC20 private token0;
    IERC20 private token1;

    uint112 constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint112 constant MAXIMUM_SUPPLY = type(uint112).max ;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Sync(uint112 reserve0, uint112 reserve1);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    function setUp() public {
        vm.setNonce(address(this), 11); // used to order erc20's correctly in factory
        token0 = getStubToken(MAXIMUM_SUPPLY);
        token1 = getStubToken(MAXIMUM_SUPPLY);

        factory = new UniswapV2Factory(address(this));

        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = IUniswapV2Pair(pairAddress);
    }

    function testMint() public {
        uint256 token0Amount = expandTo18Decimals(1);
        uint256 token1Amount = expandTo18Decimals(4);

        token0.transfer(address(pair), token0Amount);
        token1.transfer(address(pair), token1Amount);

        uint256 expectedLiquidity = expandTo18Decimals(2);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(0), MINIMUM_LIQUIDITY);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), expectedLiquidity - MINIMUM_LIQUIDITY);

        vm.expectEmit(false, false, false, true);
        emit Sync(uint112(token0Amount), uint112(token1Amount));
        vm.expectEmit(true, false, false, true);
        emit Mint(address(this), token0Amount, token1Amount);

        pair.mint(address(this));

        assertEq(pair.totalSupply(), expectedLiquidity);
        assertEq(pair.balanceOf(address(this)), expectedLiquidity - MINIMUM_LIQUIDITY);
        assertEq(token0.balanceOf(address(pair)), token0Amount);
        assertEq(token1.balanceOf(address(pair)), token1Amount);

        (uint112 _reserve0, uint112 _reserve1, ) = pair.getReserves();

        assertEq(_reserve0, token0Amount);
        assertEq(_reserve1, token1Amount);
    }

    function testSwapTestCase1() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(5), expandTo18Decimals(10));
    }

    function testSwapTestCase2() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(10), expandTo18Decimals(5));
    }

    function testSwapTestCase3() public {
        runSwapTestCase(expandTo18Decimals(2), expandTo18Decimals(5), expandTo18Decimals(10));
    }

    function testSwapTestCase4() public {
        runSwapTestCase(expandTo18Decimals(2), expandTo18Decimals(10), expandTo18Decimals(5));
    }

    function testSwapTestCase5() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(10), expandTo18Decimals(10));
    }

    function testSwapTestCase6() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(100), expandTo18Decimals(100));
    }

    function testSwapTestCase7() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(1000), expandTo18Decimals(1000));
    }

    function testSwapFuzzTestCase(uint swapVal, uint token0Val, uint token1Val) public {
        (uint swapAmount, uint token0Amount, uint token1Amount) = generateSwapFuzzCase(swapVal, token0Val, token1Val);
        runSwapTestCase(swapAmount, token0Amount, token1Amount);
    }

    function generateSwapFuzzCase(uint swapSeed, uint token0AmountSeed, uint token1AmountSeed) private
            returns (uint _swapAmount, uint _token0Amount, uint _token1Amount) {

        // The swap amount cannot be zero, but others should be generally accepted:
        uint minSwapAmount = 1;
        // The swap amount cannot match/exceed token 0's amount (as it'd pull too much token 1 liquidity from the pool), so split max supply in half:
        uint maxSwapAmount = MAXIMUM_SUPPLY/2; // +1 should fail as the swap input tranfer would fail
        _swapAmount = mapSeedToRange(swapSeed, minSwapAmount, maxSwapAmount);

        // Token 0 needs to be at least one more than the swap amount (otherwise it'd drain all liquidity):
        uint minToken0Amount = _swapAmount + 1;
        // Token 0 needs to leave enough in the global supply for the client to transfer as part of the swap:
        uint maxToken0AmountSwapInclusive = MAXIMUM_SUPPLY - _swapAmount;
        // Token 0 also needs to ensure the required amount for token 1 does not exceed max supply:
        uint netSwapAmountAdjusted = _swapAmount * 997;
        uint maxToken0AmountSwapToken1 = (netSwapAmountAdjusted * (MAXIMUM_SUPPLY - 1) / 1000);
        _token0Amount = mapSeedToRange(token0AmountSeed, minToken0Amount, min(maxToken0AmountSwapInclusive, maxToken0AmountSwapToken1));

        // The liquidity between the token amounts needs to be 1001 or greater or else mint will fail:
        uint minToken1AmountLiquidity = divCeil((MINIMUM_LIQUIDITY + 1) ** 2, _token0Amount);
        // Make sure we will have enough output tokens for the output amount to be non-zero for the swap input:
        uint token0AmountAdjusted = _token0Amount * 1000;
        uint minToken1ForSwap = divCeil(token0AmountAdjusted + netSwapAmountAdjusted, netSwapAmountAdjusted);
        // Token 1 can take all of the global supply without constraints:
        uint maxToken1AmountInclusive = MAXIMUM_SUPPLY;
        _token1Amount = mapSeedToRange(token1AmountSeed, max(minToken1AmountLiquidity, minToken1ForSwap), maxToken1AmountInclusive);
    }

    function runSwapTestCase(uint swapAmount, uint token0Amount, uint token1Amount) private {
        addLiquidity(token0Amount, token1Amount);
        token0.transfer(address(pair), swapAmount);
        uint expected = computeExpectedSwapAmount(swapAmount, token0Amount, token1Amount);

        vm.expectRevert('UniswapV2: K');
        pair.swap(0, expected + 1, address(this), '');

        // Don't expect revert
        pair.swap(0, expected, address(this), '');
    }

    function computeExpectedSwapAmount(uint swapAmount, uint token0Amount, uint token1Amount) private returns (uint256) {
        // Compute new balance for token 0 with fees reduced (multiplied by 1000):
        uint newBalance0Adjusted = ((token0Amount + swapAmount) * 1000) - (swapAmount * 3);

        // Determine new target K value when the adjusted balances are multiplied (1000x what it should be to match previous units):
        uint kAdjusted = token0Amount * token1Amount * 1000;

        // Find the new target balance for token 1 and subtract it from the original amount to get expected output:
        return token1Amount - divCeil(kAdjusted, newBalance0Adjusted);
    }

    function testOptimisticTestCase1() public {
        runOptimisticSwapTestCase(
            997000000000000000,
            expandTo18Decimals(5),
            expandTo18Decimals(10)
        );
    }

    function testOptimisticTestCase2() public {
        runOptimisticSwapTestCase(
            997000000000000000,
            expandTo18Decimals(10),
            expandTo18Decimals(5)
        );
    }

    function testOptimisticTestCase3() public {
        runOptimisticSwapTestCase(
            997000000000000000,
            expandTo18Decimals(5),
            expandTo18Decimals(5)
        );
    }

    function testOptimisticTestCase4() public {
        runOptimisticSwapTestCase(
            expandTo18Decimals(1),
            expandTo18Decimals(5),
            expandTo18Decimals(5)
        );
    }

    function testOptimisticFuzzTestCase(uint outputVal, uint token0Val, uint token1Val) public {
        (uint outputAmount, uint token0Amount, uint token1Amount) = generateOptimisticFuzzCase(outputVal, token0Val, token1Val);
        runOptimisticSwapTestCase(outputAmount, token0Amount, token1Amount);
    }

    function generateOptimisticFuzzCase(uint outputAmountSeed, uint token0AmountSeed, uint token1AmountSeed) private
            returns (uint _outputAmount, uint _token0Amount, uint _token1Amount) {

        // Token 0 needs at least: A) one output amount to take out and B) one remaining, otherwise all removals will fail:
        uint minToken0Amount = 2;
        // Token 0 needs to leave at least 2 in the global supply for an input transfer that will be one or greater with fees (beyond one) taken out:
        uint maxToken0Amount = MAXIMUM_SUPPLY - 2;
        _token0Amount = mapSeedToRange(token0AmountSeed, minToken0Amount, maxToken0Amount);

        // The liquidity between the token amounts needs to be 1001 or greater or else mint will fail:
        uint minToken1Amount = divCeil((MINIMUM_LIQUIDITY + 1) ** 2, _token0Amount);
        _token1Amount = mapSeedToRange(token1AmountSeed, minToken1Amount, MAXIMUM_SUPPLY);

        // We need to make sure there is enough liquidity to have one remaining, so max liquidity-based output is always one less than token amount:
        uint maxOutputAmountLiquidity = _token0Amount - 1;
        // We must also ensure enough tokens remain in global supply to allow the input transfer (when incorporating the 0.03% fee, rounding down):
        uint maxOutputAmountTotalSupply = ((MAXIMUM_SUPPLY - _token0Amount) * 997) / 1000;
        _outputAmount = mapSeedToRange(outputAmountSeed, 1, min(maxOutputAmountLiquidity, maxOutputAmountTotalSupply));
    }

    function runOptimisticSwapTestCase(uint outputAmount, uint token0Amount, uint token1Amount) private {
        addLiquidity(token0Amount, token1Amount);
        uint inputAmount = computeOptimisticInputAmount(outputAmount);
        token0.transfer(address(pair), inputAmount);

        // The reason we revert may change depending on the relative values of the output amount and available liquidity:
        if (outputAmount + 1 < token0Amount) {
            vm.expectRevert("UniswapV2: K");
        } else {
            vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY");
        }
        pair.swap(outputAmount + 1, 0, address(this), '');

        // Don't expect revert
        pair.swap(outputAmount, 0, address(this), '');
    }

    function testSwapToken0() public {
        uint256 token0Amount = expandTo18Decimals(5);
        uint256 token1Amount = expandTo18Decimals(10);
        addLiquidity(token0Amount, token1Amount);

        uint256 swapAmount = expandTo18Decimals(1);
        uint256 expectedOutputAmount = 1662497915624478906;

        token0.transfer(address(pair), swapAmount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), address(this), expectedOutputAmount);
        vm.expectEmit(false, false, false, true);
        emit Sync(uint112(token0Amount + swapAmount), uint112(token1Amount - expectedOutputAmount));
        vm.expectEmit(true, true, false, true);
        emit Swap(address(this), swapAmount, 0, 0, expectedOutputAmount, address(this));

        pair.swap(0, expectedOutputAmount, address(this), '');

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, token0Amount + swapAmount);
        assertEq(reserve1, token1Amount - expectedOutputAmount);
        assertEq(token0.balanceOf(address(pair)), token0Amount + swapAmount);
        assertEq(token1.balanceOf(address(pair)), token1Amount - expectedOutputAmount);

        uint256 totalSupplyToken1 = token1.totalSupply();
        assertEq(token0.balanceOf(address(this)), totalSupplyToken1 - token0Amount - swapAmount);
        assertEq(token1.balanceOf(address(this)), totalSupplyToken1 - token1Amount + expectedOutputAmount);
    }

    function testSwapToken1() public {
        uint256 token0Amount = expandTo18Decimals(5);
        uint256 token1Amount = expandTo18Decimals(10);
        addLiquidity(token0Amount, token1Amount);

        uint256 swapAmount = expandTo18Decimals(1);
        uint256 expectedOutputAmount = 453305446940074565;

        token1.transfer(address(pair), swapAmount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), address(this), expectedOutputAmount);
        vm.expectEmit(false, false, false, true);
        emit Sync(uint112(token0Amount - expectedOutputAmount), uint112(token1Amount + swapAmount));
        vm.expectEmit(true, true, false, true);
        emit Swap(address(this), 0, swapAmount, expectedOutputAmount, 0, address(this));

        pair.swap(expectedOutputAmount, 0, address(this), '');

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, token0Amount - expectedOutputAmount);
        assertEq(reserve1, token1Amount + swapAmount);
        assertEq(token0.balanceOf(address(pair)), token0Amount - expectedOutputAmount);
        assertEq(token1.balanceOf(address(pair)), token1Amount + swapAmount);

        uint256 totalSupplyToken1 = token1.totalSupply();
        assertEq(token0.balanceOf(address(this)), totalSupplyToken1 - token0Amount + expectedOutputAmount);
        assertEq(token1.balanceOf(address(this)), totalSupplyToken1 - token1Amount - swapAmount);
    }

    function testSwapGas() public {
        uint256 token0Amount = expandTo18Decimals(5);
        uint256 token1Amount = expandTo18Decimals(10);
        addLiquidity(token0Amount, token1Amount);

        // ensure that setting price{0,1}CumulativeLast for the first time doesn't affect our gas math
        mineBlock(2, block.timestamp + 1);
        pair.sync();

        uint256 swapAmount = expandTo18Decimals(1);
        uint256 expectedOutputAmount = 453305446940074565;
        token1.transfer(address(pair), swapAmount);
        mineBlock(3, block.timestamp + 1);

        uint256 gasStart = gasleft();
        pair.swap(expectedOutputAmount, 0, address(this), '');
        uint256 gasEnd = gasleft();
        assertEq(gasStart - gasEnd, 20311, '<- yarn to forge <- 74721 <- update to 0.8.13 <- 73462');
    }

    function testBurn() public {
        uint256 token0Amount = expandTo18Decimals(3);
        uint256 token1Amount = expandTo18Decimals(3);
        addLiquidity(token0Amount, token1Amount);

        uint256 expectedLiquidity = expandTo18Decimals(3);
        pair.transfer(address(pair), expectedLiquidity - MINIMUM_LIQUIDITY);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), address(0), expectedLiquidity - MINIMUM_LIQUIDITY);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), address(this), token0Amount - 1000);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), address(this), token1Amount - 1000);
        vm.expectEmit(false, false, false, true);
        emit Sync(1000, 1000);
        vm.expectEmit(true, true, false, true);
        emit Burn(address(this), token0Amount - 1000, token1Amount - 1000, address(this));

        (uint256 outAmount0, uint256 outAmount1) = pair.burn(address(this));
        assertEq(outAmount0, token0Amount - 1000);
        assertEq(outAmount1, token1Amount - 1000);

        assertEq(pair.balanceOf(address(this)), 0);
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY);
        assertEq(token0.balanceOf(address(pair)), 1000);
        assertEq(token1.balanceOf(address(pair)), 1000);
        uint256 totalSupplyToken0 = token0.totalSupply();
        uint256 totalSupplyToken1 = token1.totalSupply();
        assertEq(token0.balanceOf(address(this)), totalSupplyToken0 - 1000);
        assertEq(token1.balanceOf(address(this)), totalSupplyToken1 - 1000);
    }

    function testPrice01CumulativeLast() public {
        uint256 token0Amount = expandTo18Decimals(3);
        uint256 token1Amount = expandTo18Decimals(3);
        addLiquidity(token0Amount, token1Amount);

        (, , uint32 blockTimestamp1) = pair.getReserves();
        mineBlock(2, blockTimestamp1 + 1);
        pair.sync();
        (uint256 initialPrice0, uint256 initialPrice1) = encodePrice(token0Amount, token1Amount);
        assertEq(pair.price0CumulativeLast(), initialPrice0);
        assertEq(pair.price1CumulativeLast(), initialPrice1);
        (, , uint32 blockTimestamp2) = pair.getReserves();
        assertEq(blockTimestamp2, blockTimestamp1 + 1);

        uint256 swapAmount = expandTo18Decimals(3);
        token0.transfer(address(pair), swapAmount);
        mineBlock(3, blockTimestamp1 + 10);
        // swap to a new price eagerly instead of syncing
        pair.swap(0, expandTo18Decimals(1), address(this), ''); // make the price nice

        assertEq(pair.price0CumulativeLast(), initialPrice0 * 10);
        assertEq(pair.price1CumulativeLast(), initialPrice1 * 10);
        (, , uint32 blockTimestamp3) = pair.getReserves();
        assertEq(blockTimestamp3, blockTimestamp1 + 10);

        mineBlock(4, blockTimestamp1 + 20);
        pair.sync();

        (uint256 newPrice0, uint256 newPrice1) = encodePrice(expandTo18Decimals(6), expandTo18Decimals(2));
        assertEq(pair.price0CumulativeLast(), initialPrice0 * 10 + newPrice0 * 10);
        assertEq(pair.price1CumulativeLast(), initialPrice1 * 10 + newPrice1 * 10);
        (, , uint32 blockTimestamp4) = pair.getReserves();
        assertEq(blockTimestamp4, blockTimestamp1 + 20);
    }

    function testFeeToOff() public {
        uint256 token0Amount = expandTo18Decimals(1000);
        uint256 token1Amount = expandTo18Decimals(1000);
        addLiquidity(token0Amount, token1Amount);

        uint256 swapAmount = expandTo18Decimals(1);
        uint256 expectedOutputAmount = 996006981039903216;
        token1.transfer(address(pair), swapAmount);
        pair.swap(expectedOutputAmount, 0, address(this), '');

        uint256 expectedLiquidity = expandTo18Decimals(1000);
        pair.transfer(address(pair), expectedLiquidity - MINIMUM_LIQUIDITY);
        pair.burn(address(this));
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY);
    }

    function testFeeToOn() public {
        address other = address(2);
        factory.setFeeTo(other);

        uint256 token0Amount = expandTo18Decimals(1000);
        uint256 token1Amount = expandTo18Decimals(1000);
        addLiquidity(token0Amount, token1Amount);

        uint256 swapAmount = expandTo18Decimals(1);
        uint256 expectedOutputAmount = 996006981039903216;
        token1.transfer(address(pair), swapAmount);
        pair.swap(expectedOutputAmount, 0, address(this), '');

        uint256 expectedLiquidity = expandTo18Decimals(1000);
        pair.transfer(address(pair), expectedLiquidity - MINIMUM_LIQUIDITY);
        pair.burn(address(this));
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY + 249750499251388);

        // using 1000 here instead of the symbolic MINIMUM_LIQUIDITY because the amounts only happen to be equal...
        // ...because the initial liquidity amounts were equal
        assertEq(token0.balanceOf(address(pair)), 1000 + 249501683697445);
        assertEq(token1.balanceOf(address(pair)), 1000 + 250000187312969);
    }

    function computeOptimisticInputAmount(uint outputAmount) private returns (uint256) {
        // The output amount is always 99.7% of the input amount, so simply reverse it out (and round up if needed):
        return divCeil(outputAmount * 1000, 997);
    }

    function addLiquidity(uint256 token0Amount, uint256 token1Amount) private {
        token0.transfer(address(pair), token0Amount);
        token1.transfer(address(pair), token1Amount);
        pair.mint(address(this));
    }

    function mineBlock(uint256 _block, uint256 timestamp) private {
        vm.roll(_block);
        vm.warp(timestamp);
    }

    function encodePrice(uint256 reserve0, uint256 reserve1) private pure returns (uint256 price0, uint256 price1) {
        price0 = (reserve1 * (2**112)) / reserve0;
        price1 = (reserve0 * (2**112)) / reserve1;
    }

    function getStubToken(uint256 mintAmount_) private returns (IERC20) {
        return new StubERC20(mintAmount_);
    }

    function divCeil(uint numerand, uint divisor) private returns (uint) {
        uint roundUpAmount = numerand % divisor == 0 ? 0 : 1;
        return (numerand / divisor) + roundUpAmount;
    }

    function min(uint a, uint b) private returns (uint) {
        return a < b ? a : b;
    }

    function max(uint a, uint b) private returns (uint) {
        return a > b ? a : b;
    }

    function mapSeedToRange(uint seed, uint minInclusive, uint maxInclusive) private returns (uint) {
        require(minInclusive <= maxInclusive, "minInclusive must not exceed maxInclusive");
        uint rangeWidth = maxInclusive - minInclusive + 1;
        return (seed % rangeWidth) + minInclusive;
    }
}

contract StubERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    constructor(uint256 initTotalSupply) {
        _mint(msg.sender, initTotalSupply);
    }

    function _mint(address account, uint256 amount) internal virtual {
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function name() public view virtual override returns (string memory) {
        revert('name not used for tests.');
    }

    function symbol() public view virtual override returns (string memory) {
        revert('symbol not used for tests.');
    }

    function decimals() public view virtual override returns (uint8) {
        revert('decimals not used for tests.');
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 fromBalance = _balances[msg.sender];
        require(fromBalance >= amount, 'ERC20: transfer amount exceeds balance');
        _balances[msg.sender] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(
        address, /* owner */
        address /* spender */
    ) public view virtual override returns (uint256) {
        revert('allowance not used for tests.');
    }

    function approve(
        address, /* spender */
        uint256 /* amount */
    ) public virtual override returns (bool) {
        revert('approve not used for tests.');
    }

    function transferFrom(
        address, /* from */
        address, /* to */
        uint256 /* amount */
    ) public virtual override returns (bool) {
        revert('transferFrom not used for tests.');
    }
}

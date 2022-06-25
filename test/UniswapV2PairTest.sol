// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';

import '../contracts/UniswapV2Pair.sol';
import '../contracts/UniswapV2Factory.sol';
import '../contracts/interfaces/IERC20.sol';

contract UniswapV2PairTest is Test {
    IUniswapV2Factory private factory;
    IUniswapV2Pair private pair;
    IERC20 private token0;
    IERC20 private token1;

    uint112 constant MINIMUM_LIQUIDITY = 10**3;
    uint256 constant MAX_TOKEN = uint256(type(uint112).max)**2;
    uint112 constant MAXIMUM_UNI_RESERVE = type(uint112).max;

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
        token0 = getStubToken(MAX_TOKEN);
        token1 = getStubToken(MAX_TOKEN);

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

        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = pair.getReserves();

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

    function testSwapFuzzTestCase(
        uint256 swapVal,
        uint256 token0Val,
        uint256 token1Val
    ) public {
        (uint256 swapAmount, uint256 token0Amount, uint256 token1Amount) = generateSwapFuzzCase(
            swapVal,
            token0Val,
            token1Val
        );
        runSwapTestCase(swapAmount, token0Amount, token1Amount);
    }

    /**
     * @notice The random seeds are mapped to acceptable bounds for the testSwapFuzzCase tests. Calculations
     * for these bounds are numbered with refrences that can be found at:
     * https://internal-hydrogen-adf.notion.site/Swap-test-case-fuzz-limits-9dc0e31ea47745879cdcca116275f28e
     */
    function generateSwapFuzzCase(
        uint256 swapSeed,
        uint256 token0AmountSeed,
        uint256 token1AmountSeed
    )
        private
        returns (
            uint256 _swapAmount,
            uint256 _token0Amount,
            uint256 _token1Amount
        )
    {
        // See (8) in @notice link, there must always be one unit in the reserves and enough room for a swap
        // of one without an overflow.
        _token0Amount = mapSeedToRange(token0AmountSeed, 1, MAXIMUM_UNI_RESERVE - 1);

        // See (19)
        // Must be at least 2 to allow for reserves after removing a swap of unit 1,
        // Must meet the minimum mint liquidity,
        // Must be large enough to ensure any swap size will not overflow reserve0.
        uint256 minToken1Amount = max(
            2,
            max(
                divCeil((MINIMUM_LIQUIDITY + 1)**2, _token0Amount),
                divCeil(1000 * _token0Amount, 997 * (MAXIMUM_UNI_RESERVE - _token0Amount)) + 1
            )
        );
        _token1Amount = mapSeedToRange(token1AmountSeed, minToken1Amount, MAXIMUM_UNI_RESERVE);

        // See (17)
        // The swap amount must be at least 1 and also large enough that the output is also at least 1.
        uint256 minSwapAmount = max(1, divCeil(1000 * _token0Amount, (997 * (_token1Amount - 1))));
        // The swap amount must not overflow the reserve veraible when added to it during the swap.
        uint256 maxSwapAmount = MAXIMUM_UNI_RESERVE - _token0Amount;
        _swapAmount = mapSeedToRange(swapSeed, minSwapAmount, maxSwapAmount);
    }

    function runSwapTestCase(
        uint256 swapAmount,
        uint256 token0Amount,
        uint256 token1Amount
    ) private {
        addLiquidity(token0Amount, token1Amount);
        token0.transfer(address(pair), swapAmount);
        uint256 expected = computeExpectedSwapAmount(swapAmount, token0Amount, token1Amount);
        if (expected + 1 < token1Amount) {
            vm.expectRevert('UniswapV2: K');
        } else {
            // swap will leave reserves at 0
            vm.expectRevert('UniswapV2: INSUFFICIENT_LIQUIDITY');
        }

        pair.swap(0, expected + 1, address(this), '');

        // Don't expect revert
        pair.swap(0, expected, address(this), '');
    }

    function computeExpectedSwapAmount(
        uint256 swapAmount,
        uint256 token0Amount,
        uint256 token1Amount
    ) private returns (uint256) {
        // Compute new balance for token 0 with fees reduced (multiplied by 1000):
        uint256 newBalance0Adjusted = ((token0Amount + swapAmount) * 1000) - (swapAmount * 3);

        // Determine new target K value when the adjusted balances are multiplied (1000x what it should be to match previous units):
        uint256 kAdjusted = token0Amount * token1Amount * 1000;

        // Find the new target balance for token 1 and subtract it from the original amount to get expected output:
        return token1Amount - divCeil(kAdjusted, newBalance0Adjusted);
    }

    function testOptimisticTestCase1() public {
        runOptimisticSwapTestCase(997000000000000000, expandTo18Decimals(5), expandTo18Decimals(10));
    }

    function testOptimisticTestCase2() public {
        runOptimisticSwapTestCase(997000000000000000, expandTo18Decimals(10), expandTo18Decimals(5));
    }

    function testOptimisticTestCase3() public {
        runOptimisticSwapTestCase(997000000000000000, expandTo18Decimals(5), expandTo18Decimals(5));
    }

    function testOptimisticTestCase4() public {
        runOptimisticSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(5), expandTo18Decimals(5));
    }

    function testOptimisticFuzzTestCase(
        uint256 outputVal,
        uint256 token0Val,
        uint256 token1Val
    ) public {
        (uint256 outputAmount, uint256 token0Amount, uint256 token1Amount) = generateOptimisticFuzzCase(
            outputVal,
            token0Val,
            token1Val
        );
        runOptimisticSwapTestCase(outputAmount, token0Amount, token1Amount);
    }

    function generateOptimisticFuzzCase(
        uint256 outputAmountSeed,
        uint256 token0AmountSeed,
        uint256 token1AmountSeed
    )
        private
        returns (
            uint256 _outputAmount,
            uint256 _token0Amount,
            uint256 _token1Amount
        )
    {
        // Token 0 needs at least: A) one output amount to take out and B) one remaining, otherwise all removals will fail:
        _token0Amount = mapSeedToRange(token0AmountSeed, 2, MAXIMUM_UNI_RESERVE);

        // The liquidity between the token amounts needs to be 1001 or greater or else mint will fail:
        uint256 minToken1Amount = divCeil((MINIMUM_LIQUIDITY + 1)**2, _token0Amount);
        _token1Amount = mapSeedToRange(token1AmountSeed, minToken1Amount, MAXIMUM_UNI_RESERVE);

        // We need to make sure there is enough liquidity to have one remaining, so max liquidity-based output is always one less than token amount:
        uint256 maxOutputAmountLiquidity = _token0Amount - 1;
        // We must also ensure enough tokens remain in global supply to allow the input transfer (when incorporating the 0.03% fee, rounding down):
        uint256 maxOutputAmountTotalSupply = ((MAXIMUM_UNI_RESERVE - _token0Amount) * 997) / 1000;
        _outputAmount = mapSeedToRange(outputAmountSeed, 1, min(maxOutputAmountLiquidity, maxOutputAmountTotalSupply));
    }

    function runOptimisticSwapTestCase(
        uint256 outputAmount,
        uint256 token0Amount,
        uint256 token1Amount
    ) private {
        addLiquidity(token0Amount, token1Amount);
        uint256 inputAmount = computeOptimisticInputAmount(outputAmount);
        token0.transfer(address(pair), inputAmount);

        // The reason we revert may change depending on the relative values of the output amount and available liquidity:
        if (outputAmount + 1 < token0Amount) {
            vm.expectRevert('UniswapV2: K');
        } else {
            vm.expectRevert('UniswapV2: INSUFFICIENT_LIQUIDITY');
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

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        assertEq(reserve0, token0Amount + swapAmount);
        assertEq(reserve1, token1Amount - expectedOutputAmount);
        assertEq(token0.balanceOf(address(pair)), token0Amount + swapAmount);
        assertEq(token1.balanceOf(address(pair)), token1Amount - expectedOutputAmount);

        uint256 totalSupplyToken0 = token0.totalSupply();
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

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        assertEq(reserve0, token0Amount - expectedOutputAmount);
        assertEq(reserve1, token1Amount + swapAmount);
        assertEq(token0.balanceOf(address(pair)), token0Amount - expectedOutputAmount);
        assertEq(token1.balanceOf(address(pair)), token1Amount + swapAmount);

        uint256 totalSupplyToken0 = token0.totalSupply();
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

    function computeOptimisticInputAmount(uint256 outputAmount) private returns (uint256) {
        // The output amount is always 99.7% of the input amount, so simply reverse it out (and round up if needed):
        return divCeil(outputAmount * 1000, 997);
    }

    function addLiquidity(uint256 token0Amount, uint256 token1Amount) private {
        token0.transfer(address(pair), token0Amount);
        token1.transfer(address(pair), token1Amount);
        pair.mint(address(this));
    }

    function mineBlock(uint256 block, uint256 timestamp) private {
        vm.roll(block);
        vm.warp(timestamp);
    }

    function expandTo18Decimals(uint256 x) private pure returns (uint256) {
        return x * (10**18);
    }

    function encodePrice(uint256 reserve0, uint256 reserve1) private pure returns (uint256 price0, uint256 price1) {
        price0 = (reserve1 * (2**112)) / reserve0;
        price1 = (reserve0 * (2**112)) / reserve1;
    }

    function getStubToken(uint256 mintAmount_) private returns (IERC20) {
        return new StubERC20(mintAmount_);
    }

    function divCeil(uint256 numerand, uint256 divisor) private returns (uint256) {
        uint256 roundUpAmount = numerand % divisor == 0 ? 0 : 1;
        return (numerand / divisor) + roundUpAmount;
    }

    function min(uint256 a, uint256 b) private returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) private returns (uint256) {
        return a > b ? a : b;
    }

    function mapSeedToRange(
        uint256 seed,
        uint256 minInclusive,
        uint256 maxInclusive
    ) private returns (uint256) {
        require(minInclusive <= maxInclusive, 'minInclusive must not exceed maxInclusive');
        uint256 rangeWidth = maxInclusive - minInclusive + 1;
        return (seed % rangeWidth) + minInclusive;
    }
}

contract StubERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    constructor(uint256 totalSupply) {
        _mint(msg.sender, totalSupply);
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

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        revert('allowance not used for tests.');
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        revert('approve not used for tests.');
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        revert('transferFrom not used for tests.');
        return true;
    }
}

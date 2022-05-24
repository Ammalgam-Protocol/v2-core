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

    uint112 constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint112 constant MAXIMUM_SUPPLY = 10 ** 4;
    // Todo - (MT): For #1, see if we can do away with this threshold:
    uint112 constant MINIMUM_SWAP_AMOUNT = 10 ** 2;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Sync(uint112 reserve0, uint112 reserve1);
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);


    function setUp() public {
        vm.setNonce(address(this), 11); // used to order erc20's correctly in factory
        token0 = getStubToken(expandTo18Decimals(MAXIMUM_SUPPLY));
        token1 = getStubToken(expandTo18Decimals(MAXIMUM_SUPPLY));

        factory = new UniswapV2Factory(address(this));
        factory.setFeeTo(address(this));

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
      emit Transfer(address(0),address(0),  MINIMUM_LIQUIDITY);
      vm.expectEmit(true, true, false, true);
      emit Transfer(address(0),address(this),  expectedLiquidity - MINIMUM_LIQUIDITY);

      vm.expectEmit(false, false, false, true);
      emit Sync(uint112(token0Amount), uint112(token1Amount));
      vm.expectEmit(true, false, false, true);
      emit Mint(address(this), token0Amount, token1Amount);

      pair.mint(address(this));

      assertEq(pair.totalSupply(), expectedLiquidity);
      assertEq(pair.balanceOf(address(this)),  expectedLiquidity - MINIMUM_LIQUIDITY);
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

    function testSwapFuzzTestCase(uint swapVal, uint token0Val, uint token1Val) public {
        (uint swapAmount, uint token0Amount, uint token1Amount) = generateSwapFuzzCase(swapVal, token0Val, token1Val);
        // Todo - (MT): For #1, drop this check once we avoid generating out amounts of 0 in swaps:
        vm.assume(computeExpectedSwapAmount(swapAmount, token0Amount, token1Amount) > 0);
        runSwapTestCase(swapAmount, token0Amount, token1Amount);
    }

    function generateSwapFuzzCase(uint swapSeed, uint token0AmountSeed, uint token1AmountSeed) private
            returns (uint _swapAmount, uint _token0Amount, uint _token1Amount) {

        // Todo - (MT): For #1, see if we can do away with halving the maximum supply.
        _token0Amount = mapSeedToRange(token0AmountSeed, MINIMUM_LIQUIDITY + 1, expandTo18Decimals(MAXIMUM_SUPPLY) / 2 + 1);
        _token1Amount = mapSeedToRange(token1AmountSeed, MINIMUM_LIQUIDITY + 1, expandTo18Decimals(MAXIMUM_SUPPLY) / 2 + 1);
        // Todo - (MT): For #1, do we need to better clamp this to cover the following two conditions?
        //  0 < computeExpectedSwapAmount(swapAmount, token0Amount, token1Amount)
        //  computeExpectedSwapAmount(swapAmount, token0Amount, token1Amount) + MINIMUM_LIQUIDITY < expandTo18Decimals(MAXIMUM_SUPPLY)
        _swapAmount = mapSeedToRange(swapSeed, MINIMUM_SWAP_AMOUNT, _token0Amount);
    }

    function runSwapTestCase(uint swapAmount, uint token0Amount, uint token1Amount) private {
        addLiquidity(token0Amount, token1Amount);
        token0.transfer(address(pair), swapAmount);
        uint expected = computeExpectedSwapAmount(swapAmount, token0Amount, token1Amount);

        vm.expectRevert("UniswapV2: K");
        pair.swap(0, expected + 1, address(this), '');

        // Don't expect revert
        pair.swap(0, expected, address(this), '');
    }

    function computeExpectedSwapAmount(uint swapAmount, uint token0Amount, uint token1Amount) private returns (uint256) {
        // Compute new balance for token 0 with fees reduced (multiplied by 1000):
        uint newBalance0Adjusted = ((token0Amount + swapAmount) * 1000) - (swapAmount * 3);

        // Determine new target K value when the adjusted balances are multiplied (1000x what it should be to match previous units):
        uint kAdjusted = token0Amount * token1Amount * 1000;

        // Find the new target balance for token 1:
        uint newBalance1 = kAdjusted / newBalance0Adjusted;

        // The expected amount of token1 needing to be taken out, subtracting to undo any rounding up if needed:
        uint roundDownAmount = kAdjusted % newBalance0Adjusted == 0 ? 0 : 1;
        return token1Amount - newBalance1 - roundDownAmount;
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

    function testOptimisticFuzzTestCase(uint outputVal, uint token0Val, uint token1Val) public {
        (uint outputAmount, uint token0Amount, uint token1Amount) = generateOptimisticFuzzCase(outputVal, token0Val, token1Val);
        runOptimisticSwapTestCase(outputAmount, token0Amount, token1Amount);
    }

    function generateOptimisticFuzzCase(uint swapSeed, uint token0AmountSeed, uint token1AmountSeed) private
            returns (uint _outputAmount, uint _token0Amount, uint _token1Amount) {

        // Todo - (MT): For #1, see if we can do away with halving the maximum supply.
        _token0Amount = mapSeedToRange(token0AmountSeed, MINIMUM_LIQUIDITY + 1, expandTo18Decimals(MAXIMUM_SUPPLY) / 2 + 1);
        _token1Amount = mapSeedToRange(token1AmountSeed, MINIMUM_LIQUIDITY + 1, expandTo18Decimals(MAXIMUM_SUPPLY) / 2 + 1);
        _outputAmount = mapSeedToRange(swapSeed, MINIMUM_SWAP_AMOUNT, _token0Amount);
    }

    function runOptimisticSwapTestCase(uint outputAmount, uint token0Amount, uint token1Amount) private {
        addLiquidity(token0Amount, token1Amount);
        uint inputAmount = computeOptimisticInputAmount(outputAmount);
        token0.transfer(address(pair), inputAmount);

        vm.expectRevert("UniswapV2: K");
        pair.swap(outputAmount + 1, 0, address(this), '');

        // Don't expect revert
        pair.swap(outputAmount, 0, address(this), '');
    }

    function computeOptimisticInputAmount(uint outputAmount) private returns (uint256) {
        // The output amount is always 99.7% of the input amount, so simply reverse it out (and round up if needed):
        uint roundUpAmount = (outputAmount * 1000) % 997 == 0 ? 0 : 1;
        return ((outputAmount * 1000) / 997) + roundUpAmount;
    }

    function addLiquidity(uint256 token0Amount, uint256 token1Amount) private {
        token0.transfer(address(pair), token0Amount);
        token1.transfer(address(pair), token1Amount);
        pair.mint(address(this));
    }

    function expandTo18Decimals(uint256 x) private pure returns (uint256) {
        return x * (10**18);
    }

    function getStubToken(uint256 mintAmount_) private returns (IERC20) {
        return new StubERC20(mintAmount_);
    }

    function mapSeedToRange(uint seed, uint minInclusive, uint maxExclusive) private returns (uint) {
        require(minInclusive < maxExclusive, "minInclusive must be strictly less than maxExclusive");
        uint rangeWidth = maxExclusive - minInclusive - 1;
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
        revert("name not used for tests.");
        return "";
    }

    function symbol() public view virtual override returns (string memory) {
        revert("symbol not used for tests.");
        return "";
    }

    function decimals() public view virtual override returns (uint8) {
        revert("decimals not used for tests.");
        return 0;
    }

    function totalSupply() public view virtual override returns (uint256) {
        revert("totalSupply not used for tests.");
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 fromBalance = _balances[msg.sender];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[msg.sender] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        revert("allowance not used for tests.");
        return 0;
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        revert("approve not used for tests.");
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        revert("transferFrom not used for tests.");
        return true;
    }
}

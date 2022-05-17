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

    uint112 constant  MINIMUM_LIQUIDITY = 10 ** 3;
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Sync(uint112 reserve0, uint112 reserve1);
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );


    function setUp() public {
        vm.setNonce(address(this), 11); // used to order erc20's correctly in factory
        token0 = getStubToken(expandTo18Decimals(10000));
        token1 = getStubToken(expandTo18Decimals(10000));

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
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(5), expandTo18Decimals(10), 1662497915624478906);
    }

    function testSwapTestCase2() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(10), expandTo18Decimals(5), 453305446940074565);
    }

    function testSwapTestCase3() public {
        runSwapTestCase(expandTo18Decimals(2), expandTo18Decimals(5), expandTo18Decimals(10), 2851015155847869602);
    }

    function testSwapTestCase4() public {
        runSwapTestCase(expandTo18Decimals(2), expandTo18Decimals(10), expandTo18Decimals(5), 831248957812239453);
    }

    function testSwapTestCase5() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(10), expandTo18Decimals(10), 906610893880149131);
    }

    function testSwapTestCase6() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(100), expandTo18Decimals(100), 987158034397061298);
    }

    function testSwapTestCase7() public {
        runSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(1000), expandTo18Decimals(1000), 996006981039903216);
    }

    function runSwapTestCase(uint swapAmount, uint token0Amount, uint token1Amount, uint expected) private {
        addLiquidity(token0Amount, token1Amount);
        token0.transfer(address(pair), swapAmount);

        vm.expectRevert("UniswapV2: K");
        pair.swap(0, expected + 1, address(this), '');

        // Don't expect revert
        pair.swap(0, expected, address(this), '');
    }

    function testOptimisticTestCase1() public {
        runOptimisticSwapTestCase(997000000000000000, expandTo18Decimals(5), expandTo18Decimals(10), expandTo18Decimals(1));
    }

    function testOptimisticTestCase2() public {
        runOptimisticSwapTestCase(997000000000000000, expandTo18Decimals(10), expandTo18Decimals(5), expandTo18Decimals(1));
    }

    function testOptimisticTestCase3() public {
        runOptimisticSwapTestCase(997000000000000000, expandTo18Decimals(5), expandTo18Decimals(5), expandTo18Decimals(1));
    }

    function testOptimisticTestCase4() public {
        runOptimisticSwapTestCase(expandTo18Decimals(1), expandTo18Decimals(5), expandTo18Decimals(5), 1003009027081243732);
    }

    function runOptimisticSwapTestCase(uint outputAmount, uint token0Amount, uint token1Amount, uint inputAmount) private {
        addLiquidity(token0Amount, token1Amount);
        token0.transfer(address(pair), inputAmount);

        vm.expectRevert("UniswapV2: K");
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
        pair.sync();

        uint256 swapAmount = expandTo18Decimals(1);
        uint256 expectedOutputAmount = 453305446940074565;
        token1.transfer(address(pair), swapAmount);

        uint256 gasStart = gasleft();
        pair.swap(expectedOutputAmount, 0, address(this), '');
        uint256 gasEnd = gasleft();

        assertEq(gasStart - gasEnd, 18671, "<- yarn to forge <- 74721 <- update to 0.8.13 <- 73462");
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

        pair.burn(address(this));
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
    }

    function symbol() public view virtual override returns (string memory) {
        revert("symbol not used for tests.");
    }

    function decimals() public view virtual override returns (uint8) {
        revert("decimals not used for tests.");
    }

    function totalSupply() public view virtual override returns (uint256) {
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
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        revert("approve not used for tests.");
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

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

    function setUp() public {
        vm.setNonce(address(this), 11); // used to order erc20's correctly in factory
        token0 = getStubToken(expandTo18Decimals(10000));
        token1 = getStubToken(expandTo18Decimals(10000));

        factory = new UniswapV2Factory(address(this));
        factory.setFeeTo(address(this));

        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = IUniswapV2Pair(pairAddress);
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

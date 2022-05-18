// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';

import '../contracts/UniswapV2Factory.sol';
import '../contracts/UniswapV2Pair.sol';
import '../contracts/interfaces/IERC20.sol';
import './shared/utilities.sol';

contract UniswapV2FactoryTest is Test {
    IUniswapV2Factory private factory;
    IUniswapV2Pair private pair;

    address private wallet;
    address private other;

    address[] TEST_ADDRESSES = [0x1000000000000000000000000000000000000000,
        0x2000000000000000000000000000000000000000];

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function setUp() public {
        wallet = vm.addr(1);
        other = vm.addr(2);
        factory = new UniswapV2Factory(wallet);
    }

    function testInitialStates() public {
        assertEq(factory.feeTo(), address(0x0));
        assertEq(factory.feeToSetter(), wallet);
        assertEq(factory.allPairsLength(), 0);
    }

    function testCreatePair() public {
        createPair(TEST_ADDRESSES[0], TEST_ADDRESSES[1]);
    }

    function testCreatePairReverse() public {
        createPair(TEST_ADDRESSES[1], TEST_ADDRESSES[0]);
    }

    function testCreatePairGas() public {
        uint256 gasStart = gasleft();
        factory.createPair(TEST_ADDRESSES[0], TEST_ADDRESSES[1]);

        uint256 gasEnd = gasleft();
        assertEq(gasStart - gasEnd, 2034171);
    }

    function testSetFeeTo() public {
        vm.startPrank(other);
        vm.expectRevert('UniswapV2: FORBIDDEN');
        factory.setFeeTo(other);
        vm.stopPrank();

        vm.startPrank(wallet);
        factory.setFeeTo(wallet);
        assertEq(factory.feeTo(), wallet);
    }

    function testSetFeeToSetter() public {
        vm.startPrank(other);
        vm.expectRevert('UniswapV2: FORBIDDEN');
        factory.setFeeToSetter(other);
        vm.stopPrank();

        vm.startPrank(wallet);
        factory.setFeeToSetter(other);
        assertEq(factory.feeToSetter(), other);
        vm.expectRevert('UniswapV2: FORBIDDEN');
        factory.setFeeToSetter(wallet);
    }

    function createPair(address token0, address token1) private {
        bytes memory creationCode = type(UniswapV2Pair).creationCode;

        //call func in utilities.sol
        address create2Address = getCreate2Address(address(factory), token0, token1, creationCode);

        vm.expectEmit(true, true, false, true);
        emit PairCreated(TEST_ADDRESSES[0], TEST_ADDRESSES[1], create2Address, 1);
        factory.createPair(token0, token1);

        assertEq(factory.getPair(token0, token1), create2Address, 'factory.getPair(...), create2Address');

        vm.expectRevert('UniswapV2: PAIR_EXISTS');
        factory.createPair(token0, token1);

        vm.expectRevert('UniswapV2: PAIR_EXISTS');
        factory.createPair(token1, token0);

        assertEq(factory.getPair(token0, token1), create2Address);
        assertEq(factory.getPair(token1, token0), create2Address);
        assertEq(factory.allPairs(0), create2Address);
        assertEq(factory.allPairsLength(), 1, 'allPairsLength');
        pair = IUniswapV2Pair(create2Address);
        assertEq(pair.factory(), address(factory));
        assertEq(pair.token0(), TEST_ADDRESSES[0]);
        assertEq(pair.token1(), TEST_ADDRESSES[1]);
    }
}

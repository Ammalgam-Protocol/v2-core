// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

import '../contracts/test/ERC20.sol';
import '../contracts/interfaces/IUniswapV2ERC20.sol';
import './shared/utilities.sol';

contract UniswapV2ERC20Test is Test {
    address private wallet;
    address private other;

    ERC20 token;

    uint256 TOTAL_SUPPLY = expandTo18Decimals(10000);
    uint256 TEST_AMOUNT = expandTo18Decimals(10);

    bytes32 PERMIT_TYPEHASH = keccak256(
                abi.encodePacked('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)')
            );


    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {

        // setup the chainid to 1 instead of 31337 (default)
        // set it up before ERC20 created.
        vm.chainId(1);

        wallet = address(this);
        other = vm.addr(2);
        token = new ERC20(TOTAL_SUPPLY);

    }

    function testTokenInfo() public {
        assertEq(token.name(), 'Uniswap V2');
        assertEq(token.symbol(), 'UNI-V2');
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(wallet), TOTAL_SUPPLY);

        bytes32 k_domain_separator = getDomainSeparator();

        assertEq(token.DOMAIN_SEPARATOR(), k_domain_separator);
        assertEq(token.PERMIT_TYPEHASH(), PERMIT_TYPEHASH);
    }

    function testApprove() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(wallet, other, TEST_AMOUNT);
        token.approve(other, TEST_AMOUNT);

        assertEq(token.allowance(wallet, other), TEST_AMOUNT);
    }

    function testTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(wallet, other, TEST_AMOUNT);
        token.transfer(other, TEST_AMOUNT);

        assertEq(token.balanceOf(wallet), TOTAL_SUPPLY - TEST_AMOUNT);
        assertEq(token.balanceOf(other), TEST_AMOUNT);
    }

    function testTransferFail() public {
        // vm.expectRevert() would raise an exception that fails the test: Arithmetic over/underflow
        vm.expectRevert(stdError.arithmeticError);
        token.transfer(other, TOTAL_SUPPLY + 1);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(other);
        token.transfer(wallet, 1);
    }

    function testTransferFrom() public {
        token.approve(other, TEST_AMOUNT);
        vm.expectEmit(true, true, false, true);
        emit Transfer(wallet, other, TEST_AMOUNT);

        vm.startPrank(other);

        token.transferFrom(wallet, other, TEST_AMOUNT);
        assertEq(token.allowance(wallet, other), 0);
        assertEq(token.balanceOf(wallet), TOTAL_SUPPLY - TEST_AMOUNT);
        assertEq(token.balanceOf(other), TEST_AMOUNT);
    }

    function testTransferFromMax() public {
        token.approve(other, type(uint256).max);

        vm.startPrank(other);

        vm.expectEmit(true, true, false, true);
        emit Transfer(wallet, other, TEST_AMOUNT);
        token.transferFrom(wallet, other, TEST_AMOUNT);

        assertEq(token.allowance(wallet, other), type(uint256).max);
        assertEq(token.balanceOf(wallet), TOTAL_SUPPLY - TEST_AMOUNT);
        assertEq(token.balanceOf(other), TEST_AMOUNT);
    }

    function testPermit() public {
        // 1227 is a ramdom privatekey set for a new wallet because cannot get privatekey from address(this) to sim the signer
        uint256 privatekey = 1227;
        wallet = vm.addr(privatekey);

        uint256 nonce = token.nonces(wallet);
        uint256 deadline = type(uint256).max;

        bytes32 digest = getApprovalDigest(
            wallet,
            other,
            TEST_AMOUNT,
            nonce,
            deadline
        );

        //Sign a digest digest with private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privatekey, digest);
        // formula the wallet address
        address signer = ecrecover(digest, v, r, s);
        //assert the signature is the new wallet
        assertEq(wallet, signer, 'wallet-signer');

        vm.expectEmit(true, true, false, true);
        emit Approval(wallet, other, TEST_AMOUNT);
        token.permit(wallet, other, TEST_AMOUNT, deadline, v, r, s);
        assertEq(token.allowance(wallet, other), TEST_AMOUNT);
        assertEq(token.nonces(wallet), 1);

    }


    function getDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                    keccak256(bytes(token.name())),
                    keccak256(bytes('1')),
                    1,  //chainId
                    address(token)
                )
            );
    }

    function getApprovalDigest(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {

        bytes32 DOMAIN_SEPARATOR = getDomainSeparator();

        return
            keccak256(
                abi.encodePacked(
                    '\x19', // js '0x19'
                    '\x01', // js '0x01'
                    DOMAIN_SEPARATOR,
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))
                )
            );
    }

}

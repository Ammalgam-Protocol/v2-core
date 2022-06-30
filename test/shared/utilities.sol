// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

function expandTo18Decimals(uint256 x) pure returns (uint256) {
    return x * (10**18);
}

function getCreate2Address(
    address factoryAddress,
    address tokenA,
    address tokenB,
    bytes memory creationCode
) pure returns (address) {
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

    address pair = address(
        uint160(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factoryAddress,
                        keccak256(abi.encodePacked(token0, token1)),
                        keccak256(creationCode)
                    )
                )
            )
        )
    );

    return pair;
}

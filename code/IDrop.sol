// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

interface IDrop {
    function calculateDropAmount(uint256 _tokenId) external returns(uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRegistry {

    function updateSpot(address token, uint256 spot) external;
}
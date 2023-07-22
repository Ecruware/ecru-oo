// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../utils/Guarded.sol";

contract MockRegistry is Guarded {
    mapping(address => uint256) public spots;
    mapping(uint256 => uint256) public activeRateIds;

    function updateDiscountRate(uint256 rateId, uint256 rate) public {
        activeRateIds[rateId] = rate;
    }

    function updateSpot(address token, uint256 spot) public {
        spots[token] = spot;
    }
}

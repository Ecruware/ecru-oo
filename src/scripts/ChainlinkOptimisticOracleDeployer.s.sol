// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MockRegistry} from "../test/utils/MockRegistry.sol";
import {MockERC20} from "../test/utils/MockERC20.sol";

import {OptimisticChainlinkOracle} from "../OptimisticChainlinkOracle.sol";

contract OptimisticChainlinkOracleDeployerScript is Script {
    function run() external {
        vm.startBroadcast();
        uint256 disputeWindow = 1 * 60;

        address daiAddress = address(
            0x0d79df66BE487753B02D015Fb622DED7f0E9798d
        );
        address daiChainlinkFeed = address(
            0x0d79df66BE487753B02D015Fb622DED7f0E9798d
        );
        address usdcAddress = address(
            0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7
        );
        address usdcChainlinkFeed = address(
            0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7
        );

        address[2] memory coins = [daiAddress, usdcAddress];

        // Deploy the mock registry and mock erc20 token
        MockRegistry mockRegistry = new MockRegistry();
        MockERC20 mockERC20 = new MockERC20("Mock ERC20", "MOCK");

        // Mint some tokens for the deployer
        uint256 tokens = 1000 * 1e18;
        mockERC20.mint(msg.sender, tokens);
        OptimisticChainlinkOracle oracle = new OptimisticChainlinkOracle(
            address(mockRegistry),
            bytes32(uint256(1)),
            ERC20(mockERC20),
            1e18,
            disputeWindow
        );
        // Give permissions to the caller in order to add new activeRateIds
        oracle.allowCaller(oracle.ANY_SIG(), msg.sender);

        // Set the allowance for the oracle in order to register the deployer as a proposer
        mockERC20.approve(address(oracle), tokens);

        oracle.setFeed(daiAddress, daiChainlinkFeed);
        oracle.setFeed(usdcAddress, usdcChainlinkFeed);

        for (uint256 idx = 0; idx < coins.length; ++idx) {
            // Define and register a rate with the oracle
            bytes32 rateId = bytes32(uint256(uint160(coins[idx])));
            oracle.activateRateId(rateId);

            // Register the deployer as a proposer
            bytes32[] memory rateIds = new bytes32[](1);
            // Add one rateId for which we will generate a proposerKey
            rateIds[0] = rateId;
            oracle.bond(rateIds);

            // Create the init shift
            (uint256 value, bytes memory data) = oracle.value(coins[idx]);

            // Change the value retrieved from the validator so we can test a valid dispute
            oracle.shift(rateId, address(0), 0, 0, value, data);
        }
        vm.stopBroadcast();
    }
}

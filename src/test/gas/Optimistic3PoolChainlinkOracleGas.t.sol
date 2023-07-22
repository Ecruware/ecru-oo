// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IGuarded} from "../../interfaces/IGuarded.sol";
import {AggregatorV3Interface} from "../../interfaces/AggregatorV3Interface.sol";

import {min} from "../../utils/Math.sol";
import {Optimistic3PoolChainlinkOracle} from "../../Optimistic3PoolChainlinkOracle.sol";

import {MockRegistry} from "../utils/MockRegistry.sol";

contract Optimistic3PoolChainlinkOracleGas is Test {
    address public chainlinkUsdcFeed = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public chainlinkDaiFeed = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public chainlinkUsdtFeed = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    IERC20 public usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public registry = 0xD503383fFABbec8Eb85eAED448fE1fFEc0a8148A;

    Optimistic3PoolChainlinkOracle public oracle;

    uint256 public bondSize = 1000e18;
    uint256 public disputeTimeWindow = 26 * 3600;
    address public tokenAddress =
        address(0x7B50775383d3D6f0215A8F290f2C9e2eEBBEceb2);
    bytes32 public rateId = bytes32(uint256(uint160(tokenAddress)));
    bytes32 public nonce;

    function _computeNonce() internal view returns (bytes32 nonce_) {
        // fetch the latest value from the Chainlink Aggregators
        (, , , uint256 usdcTimestamp, ) = AggregatorV3Interface(
            chainlinkUsdcFeed
        ).latestRoundData();
        (, , , uint256 daiTimestamp, ) = AggregatorV3Interface(chainlinkDaiFeed)
            .latestRoundData();
        (, , , uint256 usdtTimestamp, ) = AggregatorV3Interface(
            chainlinkUsdtFeed
        ).latestRoundData();

        uint256 minTimestamp = min(
            usdcTimestamp,
            min(daiTimestamp, usdtTimestamp)
        );

        nonce_ = bytes32(minTimestamp << 64);
    }

    function _mintUSDC(address to, uint256 amount) internal {
        // USDC minters
        vm.store(
            address(usdc),
            keccak256(abi.encode(address(this), uint256(12))),
            bytes32(uint256(1))
        );
        // USDC minterAllowed
        vm.store(
            address(usdc),
            keccak256(abi.encode(address(this), uint256(13))),
            bytes32(uint256(type(uint256).max))
        );
        string memory sig = "mint(address,uint256)";
        (bool ok, ) = address(usdc).call(
            abi.encodeWithSignature(sig, to, amount)
        );
        assert(ok);
    }

    function setUp() public {
        registry = address(new MockRegistry());

        oracle = new Optimistic3PoolChainlinkOracle(
            address(registry),
            bytes32(0),
            usdc,
            bondSize,
            disputeTimeWindow,
            chainlinkUsdcFeed,
            chainlinkDaiFeed,
            chainlinkUsdtFeed
        );

        IGuarded(registry).allowCaller(
            IGuarded(registry).ANY_SIG(),
            address(oracle)
        );

        _mintUSDC(address(this), bondSize * 10);
        usdc.approve(address(oracle), type(uint256).max);

        nonce = _computeNonce();
        oracle.activateRateId(rateId);

        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = rateId;
        oracle.bond(rateIds);
    }

    function test_gas_activateRateId() public {
        oracle.activateRateId(bytes32(uint256(2)));
    }

    function test_gas_bond() public {
        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = bytes32(uint256(2));
        oracle.activateRateId(rateIds[0]);
        oracle.bond(rateIds);
    }

    function test_gas_push() public {
        console2.logAddress(address(oracle));
        oracle.push(rateId);
    }

    function test_gas_push_multiple() public {
        console2.logAddress(address(oracle));
        for (uint256 i = 1; i < 50; i++) {
            oracle.push(rateId);
        }
    }

    function test_gas_shift() public {
        console2.logAddress(address(oracle));
        vm.record();
        oracle.shift(
            rateId,
            address(0),
            0,
            nonce,
            1e18,
            abi.encode(
                1,
                uint64(block.timestamp),
                2,
                uint64(block.timestamp),
                3,
                uint64(block.timestamp)
            )
        );
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(
            address(oracle)
        );

        assertLe(reads.length, 3);
        assertLe(writes.length, 1);
    }

    function test_gas_shift_multiple() public {
        uint256 prevValue = 0;
        bytes32 prevNonce = nonce;
        bytes memory data = abi.encode(
            1,
            uint64(block.timestamp),
            2,
            uint64(block.timestamp),
            3,
            uint64(block.timestamp)
        );

        oracle.shift(rateId, address(0), prevValue, prevNonce, 1e18, data);

        (prevValue, prevNonce) = (1e18, oracle.encodeNonce(prevNonce, data));

        vm.warp(block.timestamp + disputeTimeWindow + 1);

        for (uint256 i = 2; i < 50; i++) {
            data = abi.encode(
                1,
                uint64(block.timestamp) + i,
                2,
                uint64(block.timestamp) + i,
                3,
                uint64(block.timestamp) + i
            );
            oracle.shift(
                rateId,
                address(this),
                prevValue,
                prevNonce,
                i * 1e18,
                data
            );

            (prevValue, prevNonce) = (
                i * 1e18,
                oracle.encodeNonce(prevNonce, data)
            );

            vm.warp(block.timestamp + disputeTimeWindow + 1);
        }
    }
}

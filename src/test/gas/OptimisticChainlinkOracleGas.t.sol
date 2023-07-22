// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IGuarded} from "../../interfaces/IGuarded.sol";
import {AggregatorV3Interface} from "../../interfaces/AggregatorV3Interface.sol";

import {OptimisticChainlinkOracle} from "../../OptimisticChainlinkOracle.sol";

import {MockRegistry} from "../utils/MockRegistry.sol";

contract OptimisticChainlinkOracleGas is Test {
    address public chainlinkUsdcFeed = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    IERC20 public usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public registry = 0xD503383fFABbec8Eb85eAED448fE1fFEc0a8148A;

    OptimisticChainlinkOracle public oracle;

    uint256 public bondSize = 1000e18;
    uint256 public disputeTimeWindow = 26 * 3600;
    bytes32 public defaultRateId = bytes32(uint256(uint160(address(usdc))));

    bytes32 public nonce;

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

    function _computeNonce() internal view returns (bytes32 nonce_) {
        // fetch the latest value from the Chainlink Aggregators
        (, , , uint256 usdcTimestamp, ) = AggregatorV3Interface(
            chainlinkUsdcFeed
        ).latestRoundData();

        nonce_ = bytes32(usdcTimestamp << 64);
    }

    function setUp() public {
        registry = address(new MockRegistry());

        oracle = new OptimisticChainlinkOracle(
            address(registry),
            bytes32(0),
            usdc,
            bondSize,
            disputeTimeWindow
        );

        IGuarded(registry).allowCaller(
            IGuarded(registry).ANY_SIG(),
            address(oracle)
        );

        _mintUSDC(address(this), bondSize * 10);
        usdc.approve(address(oracle), type(uint256).max);

        oracle.setFeed(address(usdc), chainlinkUsdcFeed);
        oracle.activateRateId(defaultRateId);
        nonce = _computeNonce();

        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = defaultRateId;
        oracle.bond(rateIds);
    }

    function test_gas_activateRateId() public {
        oracle.setFeed(address(uint160(2)), chainlinkUsdcFeed);
        oracle.activateRateId(bytes32(uint256(2)));
    }

    function test_gas_bond() public {
        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = bytes32(uint256(2));
        oracle.setFeed(address(uint160(2)), chainlinkUsdcFeed);
        oracle.activateRateId(rateIds[0]);
        oracle.bond(rateIds);
    }

    function test_gas_push() public {
        console2.logAddress(address(oracle));
        oracle.push(defaultRateId);
    }

    function test_gas_push_multiple() public {
        console2.logAddress(address(oracle));
        for (uint256 i = 1; i < 50; i++) {
            oracle.push(defaultRateId);
        }
    }

    function test_gas_shift() public {
        console2.logAddress(address(oracle));
        vm.record();
        oracle.shift(
            defaultRateId,
            address(0),
            0,
            nonce,
            1e18,
            abi.encode(1, uint64(block.timestamp))
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
        bytes memory data = abi.encode(0, uint64(block.timestamp));

        oracle.shift(
            defaultRateId,
            address(0),
            prevValue,
            prevNonce,
            1e18,
            data
        );

        (prevValue, prevNonce) = (1e18, oracle.encodeNonce(prevNonce, data));

        vm.warp(block.timestamp + disputeTimeWindow + 1);

        for (uint256 i = 2; i < 50; i++) {
            data = abi.encode(uint80(i), uint64(block.timestamp));
            oracle.shift(
                defaultRateId,
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

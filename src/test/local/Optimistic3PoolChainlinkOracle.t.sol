// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {min} from "../../utils/Math.sol";

import {IRegistry} from "../../interfaces/IRegistry.sol";
import {AggregatorV3Interface} from "../../interfaces/AggregatorV3Interface.sol";

import {Optimistic3PoolChainlinkOracle} from "../../Optimistic3PoolChainlinkOracle.sol";

contract MockRegistry {
    error Mocktarget__updateSpot();

    function updateSpot(
        address, /*token*/
        uint256 /*spot*/
    ) public pure {
        revert Mocktarget__updateSpot();
    }
}

contract MockChainlinkFeed {
    error MockChainlinkFeed__getRoundData();

    uint80 public roundId;
    int256 public value;
    uint256 public timestamp;

    function setMockResponse(
        uint80 roundId_,
        int256 value_,
        uint256 timestamp_
    ) public {
        roundId = roundId_;
        value = value_;
        timestamp = timestamp_;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function getRoundData(
        uint80 /*_roundId*/
    )
        external
        pure
        returns (
            uint80, /*roundId_*/
            int256, /*answer*/
            uint256, /*startedAt*/
            uint256, /*updatedAt*/
            uint80 /*answeredInRound*/
        )
    {
        revert MockChainlinkFeed__getRoundData();
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (roundId, value, timestamp, timestamp, roundId);
    }
}

contract Optimistic3PoolChainlinkOracleTest is Test {
    address public registryMock = address(0xc0115005);
    address public mockERC20 = address(0x110cC20);

    address public chainlinkUsdcFeed = address(0xf33dfe3d1);
    address public chainlinkDaiFeed = address(0xf33dfe3d2);
    address public chainlinkUsdtFeed = address(0xf33dfe3d3);

    Optimistic3PoolChainlinkOracle public oracle;

    uint256 public disputeTimeWindow = 6 * 3600;
    uint256 public bondSize = 10;

    function _setMockRegistry() private {
        vm.mockCall(
            registryMock,
            abi.encodeWithSelector(IRegistry.updateSpot.selector),
            abi.encode(true)
        );
    }

    function _setMockERC20() private {
        vm.mockCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(true)
        );
        vm.mockCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            abi.encode(true)
        );
    }

    function _setMockFeedDecimals(address feed, uint256 decimals_) private {
        vm.mockCall(
            feed,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(decimals_)
        );
    }

    function _setMockFeedLatestValue(
        address feed,
        int256 value,
        uint80 roundId,
        uint256 timestamp
    ) private {
        vm.mockCall(
            feed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                roundId,
                value,
                uint256(timestamp),
                uint256(timestamp),
                roundId
            )
        );
    }

    function _setMockFeedRoundValue(
        address feed,
        int256 value,
        uint80 roundId,
        uint256 timestamp
    ) private {
        vm.mockCall(
            feed,
            abi.encodeWithSelector(
                AggregatorV3Interface.getRoundData.selector,
                roundId
            ),
            abi.encode(
                roundId,
                value,
                uint256(timestamp),
                uint256(timestamp),
                roundId
            )
        );
    }

    function _bond(address proposer, bytes32 rateId) internal {
        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = rateId;
        vm.startPrank(proposer);
        oracle.bond(rateIds);
        vm.stopPrank();
    }

    function setUp() public {
        _setMockERC20();
        _setMockFeedDecimals(chainlinkUsdcFeed, 8);
        _setMockFeedDecimals(chainlinkDaiFeed, 8);
        _setMockFeedDecimals(chainlinkUsdtFeed, 8);
        _setMockRegistry();

        oracle = new Optimistic3PoolChainlinkOracle(
            registryMock,
            bytes32(0),
            IERC20(address(mockERC20)),
            bondSize,
            disputeTimeWindow,
            chainlinkUsdcFeed,
            chainlinkDaiFeed,
            chainlinkUsdtFeed
        );

        // Move to a time that's bigger than the disputeTimeWindow in order for the time delta's to work
        vm.warp(disputeTimeWindow * 100);
    }

    function test_deploy() public {
        assertTrue(
            address(oracle) != address(0),
            "The Optimistic Chainlink Oracle should be deployed"
        );
    }

    function test_chainlinkFeeds() public {
        assertEq(oracle.aggregatorFeed1(), chainlinkUsdcFeed);
        assertEq(oracle.aggregatorFeed2(), chainlinkDaiFeed);
        assertEq(oracle.aggregatorFeed3(), chainlinkUsdtFeed);
    }

    function test_canDispute() public {
        assertTrue(
            oracle.canDispute(bytes32(block.timestamp - disputeTimeWindow))
        );
    }

    function test_canDispute_failsAfterWindow() public {
        assertFalse(
            oracle.canDispute(bytes32(block.timestamp - disputeTimeWindow - 1))
        );
    }

    function test_value_returnsMin(
        uint128 feedValue1,
        uint128 feedValue2,
        uint128 feedValue3,
        uint80 roundId
    ) public {
        _setMockFeedLatestValue(
            chainlinkUsdcFeed,
            int256(uint256(feedValue1)),
            roundId,
            0
        );
        _setMockFeedLatestValue(
            chainlinkDaiFeed,
            int256(uint256(feedValue2)),
            roundId,
            0
        );
        _setMockFeedLatestValue(
            chainlinkUsdtFeed,
            int256(uint256(feedValue3)),
            roundId,
            0
        );

        (uint256 value_, ) = oracle.value();

        assertTrue(
            value_ ==
                min(
                    uint256(feedValue1),
                    min(uint256(feedValue2), uint256(feedValue3))
                ) *
                    1e10,
            "Incorrect value() returned value"
        );
    }

    function test_value_data(
        uint80 roundId1,
        uint80 roundId2,
        uint80 roundId3,
        uint64 timestamp1,
        uint64 timestamp2,
        uint64 timestamp3
    ) public {
        _setMockFeedLatestValue(
            chainlinkUsdcFeed,
            int256(1e8),
            roundId1,
            timestamp1
        );
        _setMockFeedLatestValue(
            chainlinkDaiFeed,
            int256(2e8),
            roundId2,
            timestamp2
        );
        _setMockFeedLatestValue(
            chainlinkUsdtFeed,
            int256(3e8),
            roundId3,
            timestamp3
        );

        (, bytes memory data) = oracle.value();

        bytes memory computedData = abi.encode(
            roundId1,
            timestamp1,
            roundId2,
            timestamp2,
            roundId3,
            timestamp3
        );

        assertTrue(
            keccak256(data) == keccak256(computedData),
            "Incorrect validator data"
        );
    }

    function test_push(bytes32 rateId) public {
        _setMockFeedLatestValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedLatestValue(chainlinkDaiFeed, int256(1e8), 2, 2);

        _setMockFeedLatestValue(chainlinkUsdtFeed, int256(1e8), 3, 3);

        oracle.activateRateId(rateId);

        oracle.push(rateId);
    }

    function test_push_updatesRegistry(address token) public {
        bytes32 rateId = bytes32(uint256(uint160(token)));

        _setMockFeedLatestValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedLatestValue(chainlinkDaiFeed, int256(2e8), 2, 2);

        _setMockFeedLatestValue(chainlinkUsdtFeed, int256(3e8), 3, 3);

        oracle.activateRateId(rateId);

        vm.expectCall(
            registryMock,
            abi.encodeWithSelector(IRegistry.updateSpot.selector, token, 1e18)
        );

        oracle.push(rateId);
    }

    function test_push_revertOnInactiveRateId(address feed) public {
        bytes32 rateId = bytes32(uint256(uint160(feed)));
        vm.expectRevert(
            abi.encodeWithSelector(
                Optimistic3PoolChainlinkOracle
                    .Optimistic3PoolChainlinkOracle__push_inactiveRateId
                    .selector
            )
        );
        oracle.push(rateId);
    }

    function test_encodeNonce(
        uint80 usdcRoundId,
        uint64 usdcTimestamp,
        uint80 daiRoundId,
        uint64 daiTimestamp,
        uint80 usdtRoundId,
        uint64 usdtTimestamp,
        uint64 proposeTimestamp
    ) public {
        bytes memory data = abi.encode(
            usdcRoundId,
            usdcTimestamp,
            daiRoundId,
            daiTimestamp,
            usdtRoundId,
            usdtTimestamp
        );
        uint256 hashPreimage = uint256(keccak256(data)) << 128;
        uint256 minTimestamp = min(
            usdcTimestamp,
            min(daiTimestamp, usdtTimestamp)
        ) << 64;

        vm.warp(proposeTimestamp);
        bytes32 computedNonce = bytes32(
            hashPreimage + minTimestamp + proposeTimestamp
        );

        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        assertEq(nonce, computedNonce);
    }

    function test_encodeNonce_multiple() public {
        _setMockFeedLatestValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedLatestValue(chainlinkDaiFeed, int256(1e8), 2, 2);

        _setMockFeedLatestValue(chainlinkUsdtFeed, int256(1e8), 3, 3);

        (, bytes memory data1) = oracle.value();
        // Use 0 for the previous nonce to skip the dispute window check
        bytes32 firstNonce = oracle.encodeNonce(bytes32(0), data1);
        // Move after the dispute window
        vm.warp(block.timestamp + disputeTimeWindow + 1);

        _setMockFeedLatestValue(
            chainlinkUsdcFeed,
            int256(2e18),
            4,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkDaiFeed,
            int256(3e18),
            5,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkUsdtFeed,
            int256(1e8),
            6,
            block.timestamp
        );

        (, bytes memory data2) = oracle.value();

        bytes32 secondNonce = oracle.encodeNonce(firstNonce, data2);

        assertTrue(secondNonce != bytes32(0));
    }

    function test_encodeNonce_reverts_staleProposal() public {
        // setup the feeds
        _setMockFeedLatestValue(
            chainlinkUsdcFeed,
            int256(1e8),
            1,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkDaiFeed,
            int256(1e8),
            2,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkUsdtFeed,
            int256(1e8),
            3,
            block.timestamp
        );

        (, bytes memory data) = oracle.value();
        // use 0 for the previous nonce to skip the dispute window check
        bytes32 firstNonce = oracle.encodeNonce(bytes32(0), data);
        // move after the dispute window
        vm.warp(block.timestamp + disputeTimeWindow + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Optimistic3PoolChainlinkOracle
                    .Optimistic3PoolChainlinkOracle__encodeNonce_staleProposal
                    .selector
            )
        );
        // attempt to use the same data
        oracle.encodeNonce(firstNonce, data);
    }

    function test_encodeNonce_reverts_activeDisputeWindow() public {
        // setup the feeds
        _setMockFeedLatestValue(
            chainlinkUsdcFeed,
            int256(1e8),
            1,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkDaiFeed,
            int256(2e8),
            2,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkUsdtFeed,
            int256(3e8),
            3,
            block.timestamp
        );

        (, bytes memory data1) = oracle.value();
        // use 0 for the previous nonce to skip the dispute window check
        bytes32 firstNonce = oracle.encodeNonce(bytes32(0), data1);

        // move to the last second of the dispute window
        vm.warp(block.timestamp + disputeTimeWindow);

        _setMockFeedLatestValue(
            chainlinkUsdcFeed,
            int256(2e8),
            4,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkDaiFeed,
            int256(3e8),
            5,
            block.timestamp
        );

        _setMockFeedLatestValue(
            chainlinkUsdtFeed,
            int256(1e8),
            6,
            block.timestamp
        );

        (, bytes memory data2) = oracle.value();

        vm.expectRevert(
            abi.encodeWithSelector(
                Optimistic3PoolChainlinkOracle
                    .Optimistic3PoolChainlinkOracle__encodeNonce_activeDisputeWindow
                    .selector
            )
        );

        oracle.encodeNonce(firstNonce, data2);
    }

    function test_encodeNonce_reverts_invalidData(bytes memory data) public {
        if (data.length == 192) {
            return;
        }

        vm.expectRevert();
        // encode should revert because data can`t be decoded
        oracle.encodeNonce(bytes32(0), data);
    }

    function test_decodeNonce(
        uint80 usdcRoundId,
        uint64 usdcTimestamp,
        uint80 daiRoundId,
        uint64 daiTimestamp,
        uint80 usdtRoundId,
        uint64 usdtTimestamp,
        uint64 proposeTimestamp
    ) public {
        bytes memory data = abi.encode(
            usdcRoundId,
            usdcTimestamp,
            daiRoundId,
            daiTimestamp,
            usdtRoundId,
            usdtTimestamp
        );
        vm.warp(proposeTimestamp);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        uint256 minTimestamp = min(
            usdcTimestamp,
            min(daiTimestamp, usdtTimestamp)
        );

        (bytes32 decodedPrefix, uint64 decodedProposeTimestamp) = oracle
            .decodeNonce(nonce);

        bytes32 noncePrefix = bytes32(
            (uint256(keccak256(data) << 128) + minTimestamp) << 64
        );
        assertEq(decodedProposeTimestamp, proposeTimestamp);
        assertEq(decodedPrefix, noncePrefix);
    }

    function test_validate(
        uint80 usdcRoundId,
        uint64 usdcTimestamp,
        uint80 daiRoundId,
        uint64 daiTimestamp,
        uint80 usdtRoundId,
        uint64 usdtTimestamp,
        uint64 proposeTimestamp
    ) public {
        _setMockFeedRoundValue(
            chainlinkUsdcFeed,
            int256(2e8),
            usdcRoundId,
            usdcTimestamp
        );

        _setMockFeedRoundValue(
            chainlinkDaiFeed,
            int256(3e8),
            daiRoundId,
            daiTimestamp
        );

        _setMockFeedRoundValue(
            chainlinkUsdtFeed,
            int256(1e8),
            usdtRoundId,
            usdtTimestamp
        );

        vm.warp(proposeTimestamp);

        bytes memory data = abi.encode(
            usdcRoundId,
            usdcTimestamp,
            daiRoundId,
            daiTimestamp,
            usdtRoundId,
            usdtTimestamp
        );

        // Generate the nonce for the validation process
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        (uint256 result, uint256 validatedValue, ) = oracle.validate(
            1e18,
            bytes32(0),
            nonce,
            data
        );

        bool isValid = result ==
            uint256(Optimistic3PoolChainlinkOracle.ValidateResult.Success);
        assertTrue(isValid, "Incorrect validate() returned outcome");

        assertTrue(
            validatedValue == 1e18,
            "Incorrect validate() returned value"
        );
    }

    function test_validate_invalidNonce(bytes32 invalidNonce) public {
        // set the latest feed rounds
        _setMockFeedLatestValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedLatestValue(chainlinkDaiFeed, int256(2e8), 2, 2);

        _setMockFeedLatestValue(chainlinkUsdtFeed, int256(3e8), 3, 3);

        // set data for each roundId
        _setMockFeedRoundValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedRoundValue(chainlinkDaiFeed, int256(2e8), 2, 2);

        _setMockFeedRoundValue(chainlinkUsdtFeed, int256(3e8), 3, 3);

        bytes memory data = abi.encode(1, 1, 2, 2, 3, 3);

        // Generate the nonce for the validation process
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        if (nonce == invalidNonce) return;

        (uint256 result, , ) = oracle.validate(
            1e18,
            bytes32(0),
            invalidNonce,
            data
        );

        assertTrue(
            result ==
                uint256(
                    Optimistic3PoolChainlinkOracle
                        .ValidateResult
                        .InvalidDataOrNonce
                )
        );
    }

    function test_validate_invalidData() public {
        // set the latest feed rounds
        _setMockFeedLatestValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedLatestValue(chainlinkDaiFeed, int256(2e8), 2, 2);

        _setMockFeedLatestValue(chainlinkUsdtFeed, int256(3e8), 3, 3);

        // set data for each roundId
        _setMockFeedRoundValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedRoundValue(chainlinkDaiFeed, int256(2e8), 2, 2);

        _setMockFeedRoundValue(chainlinkUsdtFeed, int256(3e8), 3, 3);

        // add a mock round that will be used to try and trick validate
        _setMockFeedRoundValue(chainlinkUsdcFeed, int256(1e6), 0, 0);

        bytes memory data = abi.encode(1, 1, 2, 2, 3, 3);

        // Generate the nonce for the validation process
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        (uint256 result, uint256 validatedValue, ) = oracle.validate(
            1e18,
            bytes32(0),
            nonce,
            // data is different that what is encoded in nonce but the round exists
            abi.encode(0, 0, 2, 2, 3, 3)
        );

        assertTrue(
            result ==
                uint256(
                    Optimistic3PoolChainlinkOracle
                        .ValidateResult
                        .InvalidDataOrNonce
                )
        );

        assertTrue(validatedValue == 1e18);
    }

    function test_validate_revertsOninvalidDataLength(bytes memory data)
        public
    {
        if (data.length == 192) return;

        // set mocked feeds for the latest values
        _setMockFeedLatestValue(chainlinkUsdcFeed, int256(1e8), 1, 1);

        _setMockFeedLatestValue(chainlinkDaiFeed, int256(2e8), 2, 2);

        _setMockFeedLatestValue(chainlinkUsdtFeed, int256(3e8), 3, 3);

        // all params besides `data` are irrelevant if data is broken

        vm.expectRevert(
            abi.encodeWithSelector(
                Optimistic3PoolChainlinkOracle
                    .Optimistic3PoolChainlinkOracle__validate_invalidData
                    .selector
            )
        );

        oracle.validate(1e18, bytes32(0), bytes32(0), data);
    }

    function test_validate_invalidRoundId(
        uint80 usdcRoundId,
        uint64 usdcTimestamp,
        uint80 daiRoundId,
        uint64 daiTimestamp,
        uint80 usdtRoundId,
        uint64 usdtTimestamp
    ) public {
        bytes memory data = abi.encode(
            usdcRoundId,
            usdcTimestamp,
            daiRoundId,
            daiTimestamp,
            usdtRoundId,
            usdtTimestamp
        );

        MockChainlinkFeed revertingFeed = new MockChainlinkFeed();
        Optimistic3PoolChainlinkOracle revertingOracle = new Optimistic3PoolChainlinkOracle(
                registryMock,
                bytes32(0),
                IERC20(address(mockERC20)),
                bondSize,
                disputeTimeWindow,
                chainlinkUsdcFeed,
                chainlinkDaiFeed,
                address(revertingFeed)
            );

        // set the mocked feeds
        _setMockFeedRoundValue(
            chainlinkUsdcFeed,
            int256(1e8),
            usdcRoundId,
            usdcTimestamp
        );

        _setMockFeedRoundValue(
            chainlinkDaiFeed,
            int256(2e8),
            daiRoundId,
            daiTimestamp
        );

        // set mocked feeds for the latest values
        _setMockFeedLatestValue(
            chainlinkUsdcFeed,
            int256(1e8),
            usdcRoundId,
            usdcTimestamp
        );

        _setMockFeedLatestValue(
            chainlinkDaiFeed,
            int256(2e8),
            daiRoundId,
            daiTimestamp
        );

        revertingFeed.setMockResponse(usdtRoundId, int256(3e18), usdtTimestamp);

        // all params besides `result` are irrelevant if data is broken
        (uint256 result, , ) = revertingOracle.validate(
            1e18,
            bytes32(0),
            bytes32(0),
            data
        );

        assertTrue(
            result ==
                uint256(
                    Optimistic3PoolChainlinkOracle.ValidateResult.InvalidRoundId
                )
        );
    }

    function test_validate_invalidValue(
        uint80 usdcRoundId,
        uint64 usdcTimestamp,
        uint80 daiRoundId,
        uint64 daiTimestamp,
        uint80 usdtRoundId,
        uint64 usdtTimestamp,
        uint64 proposeTimestamp
    ) public {
        int256 chainlinkValue = 1e8;
        _setMockFeedRoundValue(
            chainlinkUsdcFeed,
            chainlinkValue,
            usdcRoundId,
            usdcTimestamp
        );

        _setMockFeedRoundValue(
            chainlinkDaiFeed,
            chainlinkValue + 1,
            daiRoundId,
            daiTimestamp
        );

        _setMockFeedRoundValue(
            chainlinkUsdtFeed,
            chainlinkValue + 2,
            usdtRoundId,
            usdtTimestamp
        );

        _setMockFeedLatestValue(chainlinkUsdcFeed, chainlinkValue, 1, 1);
        _setMockFeedLatestValue(chainlinkDaiFeed, chainlinkValue + 1, 2, 2);
        _setMockFeedLatestValue(chainlinkUsdtFeed, chainlinkValue + 2, 3, 3);

        vm.warp(proposeTimestamp);

        bytes memory data = abi.encode(
            usdcRoundId,
            usdcTimestamp,
            daiRoundId,
            daiTimestamp,
            usdtRoundId,
            usdtTimestamp
        );

        uint256 correctValue = uint256(chainlinkValue) * 1e10;
        // Generate the nonce for the validation process
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);
        (uint256 result, uint256 validatedValue, ) = oracle.validate(
            correctValue + 1,
            bytes32(0),
            nonce,
            data
        );

        bool isValid = result ==
            uint256(Optimistic3PoolChainlinkOracle.ValidateResult.InvalidValue);
        assertTrue(isValid, "Incorrect validate() returned outcome");

        assertTrue(
            validatedValue == correctValue,
            "Incorrect validate() returned value"
        );
    }

    function test_shift_afterDispute(address token) public {
        if (token == address(0)) return;

        _setMockFeedLatestValue(chainlinkUsdcFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkDaiFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkUsdtFeed, 1e18, 0, 0);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);

        _bond(address(this), rateId);

        address secondProposer = address(0x1234);
        oracle.allowProposer(secondProposer);
        _bond(secondProposer, rateId);

        int256 chainlinkValue = 1e8;
        int256 value = chainlinkValue * 1e10;

        _setMockFeedRoundValue(chainlinkUsdcFeed, chainlinkValue, 1, 1);
        _setMockFeedRoundValue(chainlinkDaiFeed, chainlinkValue + 1, 2, 2);
        _setMockFeedRoundValue(chainlinkUsdtFeed, chainlinkValue + 2, 3, 3);

        _setMockFeedLatestValue(chainlinkUsdcFeed, chainlinkValue, 1, 1);
        _setMockFeedLatestValue(chainlinkDaiFeed, chainlinkValue + 1, 2, 2);
        _setMockFeedLatestValue(chainlinkUsdtFeed, chainlinkValue + 2, 3, 3);
        bytes memory data = abi.encode(1, 1, 2, 2, 3, 3);

        oracle.shift(rateId, address(0), 0, 0, uint256(value + 1), data);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);
        oracle.dispute(
            rateId,
            address(this),
            address(0),
            uint256(value + 1),
            nonce,
            data
        );

        // compute the dispute proposal id and check it`s the current one
        bytes32 proposalId = oracle.computeProposalId(
            rateId,
            address(oracle),
            uint256(value),
            nonce
        );
        assertTrue(oracle.proposals(rateId) == proposalId);

        // Impersonate the second proposer
        vm.prank(secondProposer);
        vm.warp(block.timestamp + disputeTimeWindow + 1);
        oracle.shift(
            rateId,
            address(oracle),
            uint256(value),
            nonce,
            2e18,
            abi.encode(1, 3, 2, 3, 3, 3) //increase the timestamp so we don`t revert on shift
        );
    }

    function test_shift_invalidDataDecode(address token, bytes memory data)
        public
    {
        if (data.length == 192) return;

        if (token == address(0)) return;

        _setMockFeedLatestValue(chainlinkUsdcFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkDaiFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkUsdtFeed, 1e18, 0, 0);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        address secondProposer = address(0x1234);
        oracle.allowProposer(secondProposer);
        _bond(secondProposer, rateId);

        uint256 value = 1e18;
        vm.expectRevert();
        oracle.shift(rateId, address(0), 0, 0, value + 1, data);
    }

    function test_shift_dataOverflow(address token) public {
        if (token == address(0)) return;

        _setMockFeedLatestValue(chainlinkUsdcFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkDaiFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkUsdtFeed, 1e18, 0, 0);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        address secondProposer = address(0x1234);
        oracle.allowProposer(secondProposer);
        _bond(secondProposer, rateId);

        // usdc round id overflow
        bytes memory data = abi.encode(
            uint256(type(uint80).max) + 1,
            type(uint64).max,
            type(uint80).max,
            type(uint64).max,
            type(uint80).max,
            type(uint64).max
        );

        vm.expectRevert();
        oracle.shift(rateId, address(0), 0, 0, 1e18, data);

        // usdc timestamp overflow
        data = abi.encode(
            type(uint80).max,
            uint256(type(uint64).max) + 1,
            type(uint80).max,
            type(uint64).max,
            type(uint80).max,
            type(uint64).max
        );

        vm.expectRevert();
        oracle.shift(rateId, address(0), 0, 0, 1e18, data);

        // upper limit test
        data = abi.encode(
            type(uint80).max,
            type(uint64).max,
            type(uint80).max,
            type(uint64).max,
            type(uint80).max,
            type(uint64).max
        );

        oracle.shift(rateId, address(0), 0, 0, 1e18, data);
    }

    // Testing the internal push method
    function test__push_updatesRegistry(address token, uint256 value) public {
        if (token == address(0)) return;

        if (value == 0) return;

        _setMockFeedLatestValue(chainlinkUsdcFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkDaiFeed, 1e18, 0, 0);
        _setMockFeedLatestValue(chainlinkUsdtFeed, 1e18, 0, 0);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        bytes memory data = abi.encode(1, 1, 2, 2, 3, 3);
        oracle.shift(rateId, address(0), 0, 0, value, data);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        vm.warp(block.timestamp + disputeTimeWindow + 1);

        vm.expectCall(
            registryMock,
            abi.encodeWithSelector(IRegistry.updateSpot.selector)
        );

        oracle.shift(
            rateId,
            address(this),
            value,
            nonce,
            1e18 + 1,
            abi.encode(1, 2, 2, 2, 3, 3) // update round timestamp so we don`t revert on stale data
        );
    }

    function test_encode_decode(
        uint64 usdcTimestamp,
        uint64 daiTimestamp,
        uint64 usdtTimestamp,
        uint64 proposeTimestamp
    ) public {
        bytes memory data = abi.encode(
            0,
            usdcTimestamp,
            1,
            daiTimestamp,
            2,
            usdtTimestamp
        );
        uint256 minTime = min(usdcTimestamp, min(daiTimestamp, usdtTimestamp));
        bytes32 hashPrefix = bytes32(
            ((uint256(keccak256(data) << 128)) + minTime) << 64
        );

        vm.warp(proposeTimestamp);

        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        (bytes32 decodedPrefix, uint64 decodedProposeTimestamp) = oracle
            .decodeNonce(nonce);

        assertEq(decodedPrefix, hashPrefix);
        assertEq(decodedProposeTimestamp, proposeTimestamp);
    }
}

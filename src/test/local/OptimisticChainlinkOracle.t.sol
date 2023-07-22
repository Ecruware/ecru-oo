// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {wdiv} from "../../utils/Math.sol";
import {Guarded} from "../../utils/Guarded.sol";

import {IRegistry} from "../../interfaces/IRegistry.sol";
import {AggregatorV3Interface} from "../../interfaces/AggregatorV3Interface.sol";
import {OptimisticChainlinkOracle} from "../../OptimisticChainlinkOracle.sol";
import {OptimisticOracle} from "../../OptimisticOracle.sol";

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
        return 18;
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

contract OptimisticChainlinkOracleTest is Test {
    Vm public cheatCodes = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address public registryMock = address(0xc0115005);
    address public mockERC20 = address(0x110cC20);
    address public chainlinkFeed = address(0xf33dfe3d);
    OptimisticChainlinkOracle public oracle;

    uint256 public disputeTimeWindow = 6 * 3600;
    uint256 public bondSize = 10;

    function _setMockRegistry() private {
        cheatCodes.mockCall(
            registryMock,
            abi.encodeWithSelector(IRegistry.updateSpot.selector),
            abi.encode(true)
        );
    }

    function _setMockERC20() private {
        cheatCodes.mockCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(true)
        );
        cheatCodes.mockCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            abi.encode(true)
        );
    }

    function _setMockFeedDecimals(uint256 decimals_) private {
        cheatCodes.mockCall(
            chainlinkFeed,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(decimals_)
        );
    }

    function _setMockFeedLatestValue(
        int256 value,
        uint80 roundId,
        uint256 timestamp
    ) private {
        cheatCodes.mockCall(
            chainlinkFeed,
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
        int256 value,
        uint80 roundId,
        uint256 timestamp
    ) private {
        cheatCodes.mockCall(
            chainlinkFeed,
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
        _setMockFeedDecimals(18);
        _setMockRegistry();

        oracle = new OptimisticChainlinkOracle(
            registryMock,
            bytes32(0),
            IERC20(address(mockERC20)),
            bondSize,
            disputeTimeWindow
        );

        // Move to a time that's bigger than the disputeTimeWindow in order for the time delta's to work
        cheatCodes.warp(disputeTimeWindow * 100);
    }

    function test_deploy() public {
        assertTrue(
            address(oracle) != address(0),
            "The Optimistic Chainlink Oracle should be deployed"
        );
    }

    function test_setFeed(address token, address feed) public {
        oracle.setFeed(token, feed);
    }

    function test_setFeed_checkIfTheFeedWasSet(address token, address feed)
        public
    {
        oracle.setFeed(token, feed);

        assertTrue(oracle.feeds(token) == feed, "Incorrect token feed");
    }

    function test_setFeed_onlyAuthorizedUserCanCall(address token, address feed)
        public
    {
        cheatCodes.prank(address(0x1234));

        cheatCodes.expectRevert(
            abi.encodeWithSelector(Guarded.Guarded__notGranted.selector)
        );

        oracle.setFeed(token, feed);
    }

    function test_unsetFeed(address token) public {
        oracle.unsetFeed(token);
    }

    function test_unsetFeed_checkIfTheFeedWasRemoved(
        address token,
        address feed
    ) public {
        oracle.setFeed(token, feed);
        oracle.unsetFeed(token);
        assertTrue(
            oracle.feeds(token) == address(0),
            "Token feed was not removed"
        );
    }

    function test_unsetFeed_onlyAuthorizedUserCanCall(address token) public {
        cheatCodes.prank(address(0x12345));

        cheatCodes.expectRevert(
            abi.encodeWithSelector(Guarded.Guarded__notGranted.selector)
        );

        oracle.unsetFeed(token);
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

    function test_value(
        address token,
        uint128 feedValue,
        uint80 roundId
    ) public {
        // The validator converts values to 18 digit precision so we set the same for the mock feed
        // to skip the scaling step
        _setMockFeedDecimals(18);
        _setMockFeedLatestValue(
            int256(uint256(feedValue)),
            roundId,
            block.timestamp
        );
        oracle.setFeed(token, chainlinkFeed);

        (uint256 value_, ) = oracle.value(token);
        // The mock feed will return 18 digit precision so no scaling will take place
        // so it's ok to compare with the feed unscaled output
        assertTrue(
            value_ == uint256(feedValue),
            "Incorrect value() returned value"
        );
    }

    function test_value_data(
        address token,
        uint128 feedValue,
        uint80 roundId
    ) public {
        // The validator converts values to 18 digit precision so we set the same for the mock feed
        // to skip the scaling step
        _setMockFeedDecimals(18);
        _setMockFeedLatestValue(
            int256(uint256(feedValue)),
            roundId,
            block.timestamp
        );
        oracle.setFeed(token, chainlinkFeed);

        (, bytes memory data) = oracle.value(token);

        bytes memory computedData = abi.encode(
            roundId,
            uint64(block.timestamp)
        );

        assertTrue(
            keccak256(data) == keccak256(computedData),
            "Incorrect validator data"
        );
    }

    function test_value_feedValueScaleUp() public {
        address token = address(0x1234);
        // Set the value returned by the feed to need scaling
        uint256 decimals = 8;
        uint256 feedValue = 10**decimals;
        _setMockFeedLatestValue(int256(feedValue), 0, block.timestamp);
        _setMockFeedDecimals(decimals);

        oracle.setFeed(token, chainlinkFeed);

        uint256 scaledValue = wdiv(feedValue, 10**decimals);
        (uint256 value, ) = oracle.value(token);
        assertTrue(value == scaledValue, "Incorrect value() returned value");
    }

    function test_value_feedValueScaleDown() public {
        address token = address(0x1234);
        // Set the value returned by the feed to need scaling
        uint256 decimals = 32;
        uint256 feedValue = 10**decimals;
        _setMockFeedLatestValue(int256(feedValue), 0, block.timestamp);
        _setMockFeedDecimals(decimals);

        oracle.setFeed(token, chainlinkFeed);

        uint256 scaledValue = wdiv(feedValue, 10**decimals);
        (uint256 value, ) = oracle.value(token);
        assertTrue(value == scaledValue, "Incorrect value() returned value");
    }

    function test_value_reverts_invalidTimestamp(
        address token,
        uint128 feedValue,
        uint80 roundId
    ) public {
        uint256 timestamp = type(uint176).max + uint256(1);

        // The validator converts values to 18 digit precision so we set the same for the mock feed
        // to skip the scaling step
        _setMockFeedDecimals(18);
        _setMockFeedLatestValue(int256(uint256(feedValue)), roundId, timestamp);
        oracle.setFeed(token, chainlinkFeed);

        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                OptimisticChainlinkOracle
                    .OptimisticChainlinkOracle__value_invalidTimestamp
                    .selector
            )
        );

        oracle.value(token);
    }

    function test_value_reverts_feedNotFound(address token) public {
        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                OptimisticChainlinkOracle
                    .OptimisticChainlinkOracle__value_feedNotFound
                    .selector,
                token
            )
        );

        oracle.value(token);
    }

    function test_push(address token, uint80 roundId) public {
        uint256 feedValue = 1e18;
        bytes32 rateId = bytes32(uint256(uint160(token)));
        _setMockFeedLatestValue(int256(uint256(1e18)), 1, block.timestamp);
        oracle.setFeed(token, chainlinkFeed);

        oracle.activateRateId(rateId);

        _setMockFeedDecimals(18);
        _setMockFeedLatestValue(
            int256(uint256(feedValue)),
            roundId,
            block.timestamp
        );

        oracle.push(rateId);
    }

    function test_push_updatesRegistry(address token, uint80 roundId) public {
        bytes32 rateId = bytes32(uint256(uint160(token)));
        _setMockFeedLatestValue(int256(uint256(1e18)), 1, block.timestamp);
        oracle.setFeed(token, chainlinkFeed);

        oracle.activateRateId(rateId);

        uint256 decimals = 8;
        uint256 feedValue = 10**decimals;
        _setMockFeedDecimals(decimals);
        _setMockFeedLatestValue(
            int256(uint256(feedValue)),
            roundId,
            block.timestamp
        );

        cheatCodes.expectCall(
            registryMock,
            abi.encodeWithSelector(
                IRegistry.updateSpot.selector,
                address(uint160(uint256(rateId))),
                wdiv(uint256(feedValue), 10**decimals)
            )
        );

        oracle.push(rateId);
    }

    function test_push_revertOnInactiveRateId(address feed) public {
        bytes32 rateId = bytes32(uint256(uint160(feed)));
        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                OptimisticChainlinkOracle
                    .OptimisticChainlinkOracle__push_inactiveRateId
                    .selector
            )
        );
        oracle.push(rateId);
    }

    function test_encodeNonce(uint80 roundId, uint64 roundTimestamp) public {
        // Use 0 for the previous nonce to skip the dispute window check
        bytes32 nonce = oracle.encodeNonce(
            bytes32(0),
            abi.encode(roundId, roundTimestamp)
        );
        assertTrue(nonce != bytes32(0), "Invalid nonce");
    }

    function test_encodeNonce_multiple(
        uint80 roundId1,
        uint64 roundTimestamp1,
        uint80 roundId2
    ) public {
        if (roundTimestamp1 == type(uint64).max) return;
        // Use 0 for the previous nonce to skip the dispute window check
        bytes32 firstNonce = oracle.encodeNonce(
            bytes32(0),
            abi.encode(roundId1, roundTimestamp1)
        );
        // Move after the dispute window
        cheatCodes.warp(block.timestamp + disputeTimeWindow + 1);
        uint64 roundTimestamp2 = roundTimestamp1 + 1;

        bytes32 secondNonce = oracle.encodeNonce(
            firstNonce,
            abi.encode(roundId2, roundTimestamp2)
        );
        assertTrue(secondNonce != bytes32(0));
    }

    function test_encodeNonce_reverts_staleProposal(
        uint80 roundId1,
        uint64 roundTimestamp1,
        uint80 roundId2
    ) public {
        if (roundTimestamp1 == 0) return;
        // Use 0 for the previous nonce to skip the dispute window check
        bytes32 firstNonce = oracle.encodeNonce(
            bytes32(0),
            abi.encode(roundId1, roundTimestamp1)
        );

        // Set the second round to be older than the first
        uint64 roundTimestamp2 = roundTimestamp1 - 1;

        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                OptimisticChainlinkOracle
                    .OptimisticChainlinkOracle__encodeNonce_staleProposal
                    .selector
            )
        );

        oracle.encodeNonce(firstNonce, abi.encode(roundId2, roundTimestamp2));
    }

    function test_encodeNonce_reverts_activeDisputeWindow(
        uint80 roundId1,
        uint64 roundTimestamp1,
        uint80 roundId2
    ) public {
        if (roundTimestamp1 == type(uint64).max) return;
        // Use 0 for the previous nonce to skip the dispute window check
        bytes32 firstNonce = oracle.encodeNonce(
            bytes32(0),
            abi.encode(roundId1, roundTimestamp1)
        );
        uint64 roundTimestamp2 = roundTimestamp1 + 1;

        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                OptimisticChainlinkOracle
                    .OptimisticChainlinkOracle__encodeNonce_activeDisputeWindow
                    .selector
            )
        );

        oracle.encodeNonce(firstNonce, abi.encode(roundId2, roundTimestamp2));
    }

    function test_decodeNonce(
        uint64 timestamp,
        uint80 roundId,
        uint64 roundTimestamp
    ) public {
        cheatCodes.warp(timestamp);
        bytes32 nonce = oracle.encodeNonce(
            bytes32(0),
            abi.encode(roundId, roundTimestamp)
        );
        bytes32 expectedHash = bytes32(
            (uint256(roundId) << 64) + (uint256(roundTimestamp))
        );

        (bytes32 nonceDataHash, uint64 nonceTimestamp) = oracle.decodeNonce(
            nonce
        );

        assertEq(nonceDataHash, expectedHash);
        assertTrue(timestamp == nonceTimestamp, "Invalid decoded timestamp");
    }

    function test_validate(
        address token,
        uint128 feedValue,
        uint80 roundId
    ) public {
        if (token == address(0)) return;

        // The validator converts values to 18 digit precision so we set the same for the mock feed
        // to skip the scaling step
        _setMockFeedLatestValue(
            int256(uint256(feedValue)),
            uint80(roundId),
            block.timestamp
        );

        _setMockFeedRoundValue(
            int256(uint256(feedValue)),
            uint80(roundId),
            block.timestamp
        );

        oracle.setFeed(token, chainlinkFeed);

        // Retrieve value and data from the oracle
        (uint256 value_, bytes memory data) = oracle.value(token);

        // Generate the nonce for the validation process
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        (uint256 result, uint256 validatedValue, ) = oracle.validate(
            value_,
            bytes32(uint256(uint160(token))),
            nonce,
            data
        );

        bool isValid = result ==
            uint256(OptimisticChainlinkOracle.ValidateResult.Success);
        assertTrue(isValid, "Incorrect validate() returned outcome");

        assertTrue(
            value_ == validatedValue,
            "Incorrect validate() returned value"
        );
    }

    function test_validate_invalidNonce(address token) public {
        if (token == address(0)) return;

        uint256 feedValue = 1e18;
        uint80 roundId = 1;
        // The validator converts values to 18 digit precision so we set the same for the mock feed
        // to skip the scaling step
        _setMockFeedLatestValue(int256(feedValue), roundId, block.timestamp);
        _setMockFeedRoundValue(int256(feedValue), roundId, block.timestamp);

        oracle.setFeed(token, chainlinkFeed);

        // Generate the nonce for the validation process
        // The round timestamp will not match the chainlink data
        bytes memory data = abi.encode(roundId, block.timestamp - 1);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        (uint256 result, , ) = oracle.validate(
            feedValue,
            bytes32(uint256(uint160(token))),
            nonce,
            data
        );

        assertTrue(
            result ==
                uint256(OptimisticChainlinkOracle.ValidateResult.InvalidNonce)
        );
    }

    function test_validate_invalidRound(address token) public {
        if (token == address(0)) return;

        uint256 feedValue = 1e18;
        uint80 roundId = 1;

        // Use a mock feed that reverts on getRoundData
        MockChainlinkFeed revertingFeed = new MockChainlinkFeed();
        revertingFeed.setMockResponse(
            roundId,
            int256(feedValue),
            block.timestamp
        );

        oracle.setFeed(token, address(revertingFeed));

        // Generate the nonce for the validation process
        // The round timestamp will not match the chainlink data
        bytes memory data = abi.encode(roundId + 1, block.timestamp);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        (uint256 result, , ) = oracle.validate(
            feedValue,
            bytes32(uint256(uint160(token))),
            nonce,
            data
        );

        assertTrue(
            result ==
                uint256(OptimisticChainlinkOracle.ValidateResult.InvalidRound)
        );
    }

    function test_validate_invalidValue(
        address token,
        uint128 feedValue,
        uint80 roundId
    ) public {
        if (token == address(0)) return;

        // The validator converts values to 18 digit precision so we set the same for the mock feed
        // to skip the scaling step
        _setMockFeedLatestValue(
            int256(uint256(feedValue)),
            uint80(roundId),
            block.timestamp
        );

        _setMockFeedRoundValue(
            int256(uint256(feedValue)),
            uint80(roundId),
            block.timestamp
        );

        oracle.setFeed(token, chainlinkFeed);

        // Retrieve value and data from the oracle
        (uint256 value_, bytes memory data) = oracle.value(token);

        // Generate the nonce for the validation process
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        (uint256 result, uint256 validatedValue, ) = oracle.validate(
            value_ + 1,
            bytes32(uint256(uint160(token))),
            nonce,
            data
        );

        assertEq(
            result,
            uint256(OptimisticChainlinkOracle.ValidateResult.InvalidValue)
        );

        assertEq(validatedValue, uint256(feedValue));
    }

    function test_validate_reverts_feedNotFound(address token, uint80 roundId)
        public
    {
        // Generate the nonce for the validation process
        bytes memory data = abi.encode(roundId, block.timestamp);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                OptimisticChainlinkOracle
                    .OptimisticChainlinkOracle__validate_feedNotFound
                    .selector,
                token
            )
        );
        oracle.validate(0, bytes32(uint256(uint160(token))), nonce, data);
    }

    function test_shift_afterDispute(address token) public {
        if (token == address(0)) return;

        _setMockFeedLatestValue(int256(uint256(1e18)), 1, block.timestamp);
        oracle.setFeed(token, chainlinkFeed);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        bytes32 initNonce = bytes32((uint256(block.timestamp) << 64));
        _bond(address(this), rateId);

        vm.warp(block.timestamp + 1);

        address secondProposer = address(0x1234);
        oracle.allowProposer(secondProposer);
        _bond(secondProposer, rateId);

        uint256 value = 1e18;
        _setMockFeedLatestValue(int256(value), 1, block.timestamp);
        _setMockFeedRoundValue(int256(value), 1, block.timestamp);

        bytes memory data = abi.encode(1, block.timestamp);
        oracle.shift(rateId, address(0), 0, initNonce, value + 1, data);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        oracle.dispute(
            rateId,
            address(this),
            address(0),
            value + 1,
            nonce,
            data
        );

        bytes32 proposalId = oracle.computeProposalId(
            rateId,
            address(oracle),
            uint256(value),
            nonce
        );

        assertTrue(oracle.proposals(rateId) == proposalId);

        // Impersonate the second proposer
        cheatCodes.prank(secondProposer);

        cheatCodes.warp(block.timestamp + disputeTimeWindow + 1);

        oracle.shift(
            rateId,
            address(oracle),
            value,
            nonce,
            2e18,
            abi.encode(1, block.timestamp)
        );
    }

    function test_shift_invalidDataDecode(address token, bytes memory data)
        public
    {
        if (data.length == 64) return;

        if (token == address(0)) return;

        _setMockFeedLatestValue(int256(uint256(1e18)), 1, block.timestamp);
        oracle.setFeed(token, chainlinkFeed);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        address secondProposer = address(0x1234);
        oracle.allowProposer(secondProposer);
        _bond(secondProposer, rateId);

        uint256 value = 1e18;
        _setMockFeedLatestValue(int256(value), 1, block.timestamp);
        _setMockFeedRoundValue(int256(value), 1, block.timestamp);

        cheatCodes.expectRevert();
        oracle.shift(rateId, address(0), 0, 0, value + 1, data);
    }

    function test_shift_dataOverflow(address token) public {
        if (token == address(0)) return;

        _setMockFeedLatestValue(int256(uint256(1e18)), 1, block.timestamp);
        oracle.setFeed(token, chainlinkFeed);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        bytes32 initNonce = bytes32((uint256(block.timestamp) << 64));
        _bond(address(this), rateId);

        vm.warp(block.timestamp + 1);

        address secondProposer = address(0x1234);
        oracle.allowProposer(secondProposer);
        _bond(secondProposer, rateId);

        uint256 value = 1e18;
        _setMockFeedLatestValue(int256(value), 1, block.timestamp);
        _setMockFeedRoundValue(int256(value), 1, block.timestamp);

        bytes memory data = abi.encode(
            uint256(type(uint80).max) + 1,
            type(uint64).max
        );
        cheatCodes.expectRevert();
        oracle.shift(rateId, address(0), 0, initNonce, value + 1, data);

        data = abi.encode(type(uint80).max, uint256(type(uint64).max) + 1);
        cheatCodes.expectRevert();
        oracle.shift(rateId, address(0), 0, initNonce, value + 1, data);

        data = abi.encode(type(uint80).max, type(uint64).max);
        oracle.shift(rateId, address(0), 0, initNonce, value + 1, data);
    }

    // Testing the internal push method
    function test__push_updatesRegistry(
        address token,
        uint256 value,
        uint80 roundId
    ) public {
        if (token == address(0)) return;

        if (value == 0) return;

        uint80 initialRoundId = uint80(1);
        _setMockFeedLatestValue(
            int256(uint256(1e18)),
            initialRoundId,
            block.timestamp
        );
        oracle.setFeed(token, chainlinkFeed);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // compute the initial nonce
        bytes32 initNonce = bytes32((uint256(block.timestamp) << 64));

        cheatCodes.warp(block.timestamp + 1);
        bytes memory data = abi.encode(roundId, block.timestamp);

        oracle.shift(rateId, address(0), 0, initNonce, value, data);
        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        cheatCodes.warp(block.timestamp + disputeTimeWindow + 1);

        cheatCodes.expectCall(
            registryMock,
            abi.encodeWithSelector(IRegistry.updateSpot.selector)
        );

        oracle.shift(
            rateId,
            address(this),
            value,
            nonce,
            1e18 + 1,
            abi.encode(roundId, block.timestamp)
        );
    }

    // Testing the internal push method
    function test__push_doesNotRevertOnRegistryRevert(
        address token,
        uint256 value,
        uint80 roundId
    ) public {
        if (token == address(0)) return;

        if (value == 0) return;

        MockRegistry revertRegistry = new MockRegistry();

        cheatCodes.expectRevert(
            abi.encodeWithSelector(MockRegistry.Mocktarget__updateSpot.selector)
        );
        // The mock registry reverts when update spot is called
        revertRegistry.updateSpot(address(0), 0);

        OptimisticChainlinkOracle oracleRevert = new OptimisticChainlinkOracle(
            address(revertRegistry),
            bytes32(0),
            IERC20(address(mockERC20)),
            bondSize,
            disputeTimeWindow
        );

        bytes32 rateId = bytes32(uint256(uint160(token)));

        // set the feed and activate the rate
        _setMockFeedLatestValue(int256(uint256(1e18)), 1, block.timestamp);
        oracleRevert.setFeed(token, chainlinkFeed);
        oracleRevert.activateRateId(rateId);

        // bond as a proposer
        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = rateId;
        oracleRevert.bond(rateIds);

        bytes32 initNonce = bytes32((uint256(block.timestamp) << 64));

        // need to wait for a new round to be able to shift (avoid stale revert)
        cheatCodes.warp(block.timestamp + 1);

        bytes memory data = abi.encode(roundId, block.timestamp);
        oracleRevert.shift(rateId, address(0), 0, initNonce, value, data);
        bytes32 nonce = oracleRevert.encodeNonce(bytes32(0), data);

        cheatCodes.warp(block.timestamp + disputeTimeWindow + 1);

        // Call should not revert even if Registry.updateSpot will revert
        oracleRevert.shift(
            rateId,
            address(this),
            value,
            nonce,
            1e18 + 1,
            abi.encode(roundId, block.timestamp)
        );
    }

    function test_encode_decode(
        uint80 roundId,
        uint64 roundTimestamp,
        uint64 proposeTimestamp
    ) public {
        cheatCodes.warp(proposeTimestamp);

        bytes32 nonce = oracle.encodeNonce(
            bytes32(0),
            abi.encode(roundId, roundTimestamp)
        );

        (bytes32 dataHash, uint64 decodedProposeTimestamp) = oracle.decodeNonce(
            nonce
        );

        assertEq(roundId, uint80(uint256(dataHash >> 64)));
        assertEq(roundTimestamp, uint64(uint256(dataHash)));
        assertEq(proposeTimestamp, decodedProposeTimestamp);
    }

    function test_lock_disputeReverts(address token) public {
        _setMockFeedLatestValue(int256(uint256(1e18)), 1, block.timestamp);
        oracle.setFeed(token, chainlinkFeed);

        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        bytes32 initNonce = bytes32((uint256(block.timestamp) << 64));
        _bond(address(this), rateId);

        vm.warp(block.timestamp + 1);

        // Trick the oracle by returning a different value when calling getRoundData compared to latestRoundData
        // for the same roundId
        int256 correctValue = 1e18;
        int256 wrongValue = correctValue + 1;

        _setMockFeedLatestValue(wrongValue, 1, block.timestamp);
        _setMockFeedRoundValue(correctValue, 1, block.timestamp);

        (uint256 value, bytes memory data) = oracle.value(token);

        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        oracle.shift(rateId, address(0), 0, initNonce, value, data);

        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = rateId;

        oracle.lock(rateIds);

        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__dispute_inactiveRateId
                    .selector
            )
        );

        oracle.dispute(rateId, address(this), address(0), value, nonce, data);
    }
}

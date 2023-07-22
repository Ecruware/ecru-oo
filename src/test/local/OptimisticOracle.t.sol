// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Guarded} from "../../utils/Guarded.sol";

import {OptimisticOracle} from "../../OptimisticOracle.sol";

contract OptimisticOracleImplementation is OptimisticOracle {
    bytes32 public mockNonce;
    bool public mockCanDispute;

    bool public pushCalled;

    uint256 public validateResult;
    uint256 public validValue;
    bytes public data;

    constructor(
        address target_,
        bytes32 oracleType_,
        IERC20 bondToken_,
        uint256 bondSize_,
        uint256 disputeWindow_
    )
        OptimisticOracle(
            target_,
            oracleType_,
            bondToken_,
            bondSize_,
            disputeWindow_
        )
    {
        pushCalled = false;
    }

    function encodeNonce(
        bytes32, /*prevNonce*/
        bytes memory /*data*/
    ) public view override(OptimisticOracle) returns (bytes32) {
        return mockNonce;
    }

    function decodeNonce(
        bytes32 /*nonce*/
    )
        public
        view
        virtual
        override(OptimisticOracle)
        returns (bytes32 dataHash, uint64 proposeTimestamp)
    {
        return (bytes32(0), uint64(block.timestamp));
    }

    function canDispute(
        bytes32 /*nonce*/
    ) public view override(OptimisticOracle) returns (bool) {
        return mockCanDispute;
    }

    function _push(
        bytes32, /*rateId*/
        uint256 /*value*/
    ) internal override(OptimisticOracle) {
        pushCalled = true;
    }

    function push(bytes32 rateId) public override(OptimisticOracle) {
        proposals[rateId] = computeProposalId(
            rateId,
            address(0),
            0,
            bytes32(0)
        );
    }

    function setMockNonce(bytes32 nonce) public {
        mockNonce = nonce;
    }

    function setCanDispute(bool canDispute_) public {
        mockCanDispute = canDispute_;
    }

    function setValidateResponse(
        uint256 validateResult_,
        uint256 validValue_,
        bytes memory data_
    ) public {
        validateResult = validateResult_;
        validValue = validValue_;
        data = data_;
    }

    function validate(
        uint256, /*proposedValue*/
        bytes32, /*rateId*/
        bytes32, /*nonce*/
        bytes memory /*data*/
    )
        public
        view
        override(OptimisticOracle)
        returns (
            uint256,
            uint256,
            bytes memory
        )
    {
        return (validateResult, validValue, data);
    }

    function claimBond(
        address proposer,
        bytes32 rateId,
        address receiver
    ) public {
        _claimBond(proposer, rateId, receiver);
    }
}

contract OptimisticOracleTest is Test {
    address public registryMock = address(0xc0115005);
    address public mockERC20 = address(0x110cC20);
    OptimisticOracleImplementation public oracle;

    bytes32 public encodedRate = bytes32(uint256(1337));

    uint256 public bondSize = 10;

    uint256 public disputeWindow = 10;

    bytes32 public oracleType = bytes32(uint256(1));

    uint256 internal _mockTokenBalance = 0;

    function setUp() public {
        // Create a mock erc20 that can be used by the bond manager
        _createMockERC20();

        oracle = new OptimisticOracleImplementation(
            registryMock,
            oracleType,
            IERC20(mockERC20),
            bondSize,
            disputeWindow
        );

        vm.roll(10000);
    }

    function _createMockERC20() private {
        _setMockERC20TransferFrom(true);
        _setMockERC20Transfer(true);
    }

    function _setMockERC20Transfer(bool success) private {
        vm.mockCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(success)
        );
    }

    function _setMockERC20TransferFrom(bool success) private {
        vm.mockCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            abi.encode(success)
        );
    }

    function _setMockERC20balanceOf(uint256 balance) private {
        vm.mockCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.balanceOf.selector),
            abi.encode(balance)
        );
    }

    function _bond(address proposer, bytes32 rateId) internal {
        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = rateId;
        vm.startPrank(proposer);
        oracle.bond(rateIds);
        vm.stopPrank();
    }

    function test_deploy() public {
        assertTrue(
            address(oracle) != address(0),
            "The Oracle should be deployed"
        );
    }

    function test_check_registry() public {
        assertEq(oracle.target(), address(registryMock));
    }

    function test_check_oracleType() public {
        assertEq(oracle.oracleType(), oracleType);
    }

    function test_computeProposalId() public view {
        oracle.computeProposalId(0, address(this), 1, bytes32(block.number));
    }

    function test_bond(bytes32 rateId) public {
        bool isBonded = oracle.isBonded(address(this), encodedRate);
        assertFalse(isBonded);
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);
        isBonded = oracle.isBonded(address(this), rateId);
        assertTrue(isBonded);
    }

    function test_activateRateId() public {
        oracle.activateRateId(bytes32(uint256(1)));
    }

    function test_activateRateId_reverts_alreadySet() public {
        bytes32 rateId = bytes32(uint256(1));

        oracle.activateRateId(rateId);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__activateRateId_activeRateId
                    .selector,
                rateId
            )
        );

        oracle.activateRateId(rateId);
    }

    function test_activateRateId_reverts_notGranted() public {
        oracle.blockCaller(oracle.ANY_SIG(), address(this));

        vm.expectRevert(
            abi.encodeWithSelector(Guarded.Guarded__notGranted.selector)
        );

        oracle.activateRateId(bytes32(uint256(1)));
    }

    function test_deactivateRateId() public {
        bytes32 rateId = bytes32(uint256(1));
        oracle.activateRateId(rateId);
        oracle.deactivateRateId(rateId);
    }

    function test_deactivateRateId_reverts_noRateConfig() public {
        bytes32 rateId = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__deactivateRateId_inactiveRateId
                    .selector,
                rateId
            )
        );

        oracle.deactivateRateId(rateId);
    }

    function test_shift(
        bytes32 rateId,
        uint256 value,
        bytes32 nonce
    ) public {
        if (nonce == 0) return;

        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Set the mock validator response
        oracle.setMockNonce(nonce);

        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        oracle.shift(rateId, address(0), 0, 0, value, "");
    }

    function test_shift_pushed(
        bytes32 rateId,
        uint256 value,
        bytes32 nonce,
        uint256 nextValue,
        bytes32 nextNonce
    ) public {
        if (nonce == 0 || nextNonce == 0 || value == 0 || nextValue == 0)
            return;

        oracle.activateRateId(rateId);

        // Set the mock validator response and register as a proposer
        oracle.setMockNonce(nonce);
        _bond(address(this), rateId);

        // Make the initial shift, this will not trigger a Registry update.
        oracle.shift(rateId, address(0), 0, 0, value, "");

        oracle.setMockNonce(nextNonce);
        // Make the second shift that will push the initial proposed value to Registry
        oracle.shift(rateId, address(this), value, nonce, nextValue, "");

        assertTrue(oracle.pushCalled(), "Push not called");
    }

    function test_shift_reverts_unbondedProposer(
        bytes32 rateId,
        uint256 value,
        bytes32 nonce
    ) public {
        // Register the rate
        oracle.activateRateId(rateId);

        oracle.setMockNonce(nonce);

        address proposer = address(0x123456);

        vm.startPrank(proposer);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__shift_unbondedProposer
                    .selector
            )
        );

        oracle.shift(rateId, address(0), 0, 0, value, "");

        vm.stopPrank();

        // Register the user as a proposer and attempt to run the shift again
        oracle.allowProposer(proposer);
        _bond(proposer, rateId);

        vm.prank(proposer);
        oracle.shift(rateId, address(0), 0, 0, value, "");
    }

    function test_shift_reverts_invalidPreviousProposal(
        bytes32 rateId,
        bytes32 nonce,
        uint256 value
    ) public {
        oracle.activateRateId(rateId);
        oracle.setMockNonce(nonce);
        _bond(address(this), rateId);

        // Set the mock validator to deny the shift operation
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__shift_invalidPreviousProposal
                    .selector
            )
        );

        // We change the previous value which will result in a different proposalId
        oracle.shift(rateId, address(0), 1, 0, value, "");
    }

    function test_shift_reverts_invalidPreviousProposal_InvalidProposer(
        bytes32 rateId,
        uint256 value,
        bytes32 nonce
    ) public {
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        oracle.setMockNonce(nonce);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__shift_invalidPreviousProposal
                    .selector
            )
        );

        // Prev proposer address is address(0)
        oracle.shift(rateId, address(1), 0, 0, value, "");
    }

    function test_dispute(
        address token,
        uint256 proposedValue,
        bytes memory data
    ) public {
        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        oracle.shift(rateId, address(0), 0, 0, uint256(proposedValue), data);

        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        // Set the return code to a nonzero value for a successful dispute
        uint256 returnCode = 1;
        uint256 validValue = 1e18;
        oracle.setValidateResponse(returnCode, validValue, data);
        oracle.dispute(
            rateId,
            address(this),
            address(0),
            proposedValue,
            nonce,
            data
        );

        bytes32 proposalId = oracle.computeProposalId(
            rateId,
            address(oracle),
            validValue,
            nonce
        );

        assertTrue(
            oracle.proposals(rateId) == proposalId,
            "Invalid dispute proposal id"
        );
    }

    function test_dispute_reverts_invalidDispute(
        address token,
        uint256 proposedValue,
        bytes memory data
    ) public {
        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        oracle.shift(rateId, address(0), 0, 0, uint256(proposedValue), data);

        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        // Set the return code to zero for a non valid dispute
        uint256 returnCode = 0;
        oracle.setValidateResponse(returnCode, proposedValue, data);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__dispute_invalidDispute
                    .selector
            )
        );

        oracle.dispute(
            rateId,
            address(this),
            address(0),
            proposedValue,
            nonce,
            data
        );
    }

    function test_dispute_reverts_rateConfigNotSet(
        bytes32 rateId,
        uint256 value,
        bytes32 nonce,
        bytes memory data
    ) public {
        oracle.setValidateResponse(1, value, data);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__dispute_inactiveRateId
                    .selector
            )
        );
        oracle.dispute(rateId, address(this), address(0), value, nonce, data);
    }

    function test_dispute_reverts_unknownProposal(
        address token,
        uint256 value,
        bytes32 nonce,
        bytes memory data
    ) public {
        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);
        oracle.setValidateResponse(1, value, data);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__settleDispute_unknownProposal
                    .selector
            )
        );
        oracle.dispute(rateId, address(this), address(0), value, nonce, data);
    }

    function test_dispute_reverts_alreadyDisputed(
        address token,
        uint256 proposedValue,
        bytes memory data
    ) public {
        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        oracle.shift(rateId, address(0), 0, 0, uint256(proposedValue), data);

        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        // Set the return code to a nonzero value for a successful dispute
        uint256 returnCode = 1;
        uint256 validValue = 1e18;
        oracle.setValidateResponse(returnCode, validValue, data);
        oracle.dispute(
            rateId,
            address(this),
            address(0),
            proposedValue,
            nonce,
            data
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__settleDispute_alreadyDisputed
                    .selector
            )
        );

        oracle.dispute(
            rateId,
            address(oracle),
            address(0),
            validValue,
            nonce,
            data
        );
    }

    function test_dispute_proposerIsBlocked(
        address token,
        uint256 proposedValue,
        bytes memory data
    ) public {
        bytes32 rateId = bytes32(uint256(uint160(token)));
        oracle.activateRateId(rateId);

        address proposer = address(0x123456);
        oracle.allowProposer(proposer);
        _bond(proposer, rateId);

        vm.startPrank(proposer);
        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        oracle.shift(rateId, address(0), 0, 0, uint256(proposedValue), data);
        vm.stopPrank();

        //oracle.allowCaller(oracle.bond.selector, address(this));

        bytes32 nonce = oracle.encodeNonce(bytes32(0), data);

        // Set the return code to a nonzero value for a successful dispute
        uint256 returnCode = 1;
        uint256 validValue = 1e18;
        oracle.setValidateResponse(returnCode, validValue, data);
        oracle.dispute(
            rateId,
            proposer,
            address(0),
            proposedValue,
            nonce,
            data
        );

        vm.expectRevert(
            abi.encodeWithSelector(Guarded.Guarded__notGranted.selector)
        );

        _bond(proposer, rateId);
    }

    function test_bondToken() public {
        assertTrue(oracle.bondToken() == IERC20(address(mockERC20)));
    }

    function test_bondSize() public {
        assertTrue(oracle.bondSize() == bondSize);
    }

    function test_bond() public {
        bytes32 rateId = bytes32(uint256(1));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);
    }

    function test_bond_callsTransferFrom() public {
        bytes32[] memory rateIds = new bytes32[](1);
        rateIds[0] = bytes32(uint256(1));
        oracle.activateRateId(rateIds[0]);

        vm.expectCall(
            mockERC20,
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                address(this),
                address(oracle),
                bondSize
            )
        );
        oracle.bond(rateIds);
    }

    function test_bond_multipleRateIds(
        bytes32 rateId1,
        bytes32 rateId2,
        bytes32 rateId3
    ) public {
        // Using the same rateId twice will lead to a revert, we will check that in a different test
        if (rateId1 == rateId2 || rateId1 == rateId3 || rateId2 == rateId3)
            return;

        bytes32[] memory rateIds = new bytes32[](3);
        rateIds[0] = rateId1;
        rateIds[1] = rateId2;
        rateIds[2] = rateId3;

        oracle.activateRateId(rateIds[0]);
        oracle.activateRateId(rateIds[1]);
        oracle.activateRateId(rateIds[2]);

        oracle.bond(rateIds);
        for (uint256 i = 0; i < rateIds.length; ++i) {
            assertTrue(oracle.bonds(address(this), bytes32(rateIds[i])));
        }
    }

    function test_bond_revertsIfNotAuthorized(address proposer) public {
        if (proposer == address(this)) return;

        bytes32 rateId = bytes32(uint256(1));

        oracle.activateRateId(rateId);

        vm.expectRevert(
            abi.encodeWithSelector(Guarded.Guarded__notGranted.selector)
        );

        _bond(proposer, rateId);
    }

    function test_bond_revertsIfBlocked() public {
        bytes32 rateId = bytes32(uint256(1));

        oracle.activateRateId(rateId);

        // Need to block ANY_SIG() because address(this) is the owner
        oracle.blockCaller(oracle.ANY_SIG(), address(this));

        vm.expectRevert(
            abi.encodeWithSelector(Guarded.Guarded__notGranted.selector)
        );

        _bond(address(this), rateId);
    }

    function test_bond_reverts_transferFailed(address proposer, bytes32 rateId)
        public
    {
        if (proposer == address(0)) return;

        oracle.activateRateId(rateId);

        // Set the mockERC20 to return fail on transferFrom
        _setMockERC20TransferFrom(false);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        _bond(address(this), rateId);
    }

    function test_bond_reverts_noRateConfig(address proposer, bytes32 rateId)
        public
    {
        if (proposer == address(0)) return;

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle.OptimisticOracle__bond_inactiveRateId.selector,
                rateId
            )
        );

        _bond(address(this), rateId);
    }

    function test_bond_reverts_bondedProposer(address proposer, bytes32 rateId)
        public
    {
        if (proposer == address(0)) return;

        oracle.activateRateId(rateId);

        oracle.allowProposer(proposer);
        _bond(proposer, rateId);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle.OptimisticOracle__bond_bondedProposer.selector,
                rateId
            )
        );

        _bond(proposer, rateId);
    }

    function test_unbond() public {
        bytes32 rateId = bytes32(uint256(1));
        // Create default proposal where proposer is not address(this)
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        oracle.unbond(rateId, address(0), 0, 0, address(this));
    }

    function test_unbond_deletesBond() public {
        bytes32 rateId = bytes32(uint256(1));
        // Create default proposal where proposer is not address(this)
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        oracle.unbond(rateId, address(0), 0, 0, address(this));

        assertFalse(oracle.isBonded(address(this), rateId));
    }

    function test_unbond_claimsBond(bytes32 rateId) public {
        oracle.activateRateId(rateId);

        _bond(address(this), rateId);

        vm.expectCall(
            mockERC20,
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                address(this),
                bondSize
            )
        );
        oracle.unbond(rateId, address(0), 0, 0, address(this));
    }

    function test_unbond_reverts_invalidCurrentProposal_proposer(
        bytes32 rateId,
        bytes32 nonce
    ) public {
        oracle.activateRateId(rateId);

        _bond(address(this), rateId);
        oracle.setMockNonce(nonce);
        oracle.shift(rateId, address(0), 0, 0, 1e18, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__unbond_invalidProposal
                    .selector
            )
        );

        // Send a different address for the current proposal
        oracle.unbond(rateId, address(0), 1e18, nonce, address(this));
    }

    function test_unbond_reverts_invalidCurrentProposal_value(
        bytes32 rateId,
        bytes32 nonce
    ) public {
        oracle.activateRateId(rateId);

        _bond(address(this), rateId);
        oracle.setMockNonce(nonce);
        oracle.shift(rateId, address(0), 0, 0, 1e18, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__unbond_invalidProposal
                    .selector
            )
        );

        // Send a different value for the current proposal
        oracle.unbond(rateId, address(this), 1e18 + 1, nonce, address(this));
    }

    function test_unbond_reverts_invalidCurrentProposal_nonce(
        bytes32 rateId,
        bytes32 nonce,
        bytes32 unboundNonce
    ) public {
        if (nonce == unboundNonce) return;

        oracle.activateRateId(rateId);

        _bond(address(this), rateId);
        oracle.setMockNonce(nonce);
        oracle.shift(rateId, address(0), 0, 0, 1e18, "");

        // Set a different nonce
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__unbond_invalidProposal
                    .selector
            )
        );

        // Send a different nonce for the current proposal
        oracle.unbond(rateId, address(this), 1e18, unboundNonce, address(this));
    }

    function test_unbond_reverts_isProposing(bytes32 rateId, bytes32 nonce)
        public
    {
        oracle.activateRateId(rateId);

        _bond(address(this), rateId);
        oracle.setMockNonce(nonce);
        oracle.shift(rateId, address(0), 0, 0, 1e18, "");

        oracle.setCanDispute(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle.OptimisticOracle__unbond_isProposing.selector
            )
        );

        oracle.unbond(rateId, address(this), 1e18, nonce, address(this));
    }

    function test_unbond_reverts_unbondedProposer(bytes32 rateId) public {
        oracle.activateRateId(rateId);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__unbond_unbondedProposer
                    .selector
            )
        );

        oracle.unbond(rateId, address(0), 0, 0, address(this));
    }

    function test_unbond_reverts_transferFailed(bytes32 rateId) public {
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Set the mockERC20 transfer to fail
        _setMockERC20Transfer(false);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        oracle.unbond(rateId, address(0), 0, 0, address(this));
    }

    function test_isBonded(bytes32 rateId) public {
        oracle.activateRateId(rateId);

        _bond(address(this), rateId);
        assertTrue(oracle.isBonded(address(this), rateId));

        oracle.unbond(rateId, address(0), 0, 0, address(this));
        assertTrue(!oracle.isBonded(address(this), rateId));
    }

    function test_isBonded_returnsFalse(bytes32 rateId) public {
        oracle.activateRateId(rateId);
        assertTrue(!oracle.isBonded(address(this), rateId));
    }

    function test_claimBond() public {
        bytes32 rateId = bytes32(uint256(1));
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        vm.expectCall(
            mockERC20,
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                address(this),
                bondSize
            )
        );
        oracle.claimBond(address(this), rateId, address(this));
    }

    function test_lock() public {
        bytes32[] memory rateIds = new bytes32[](1);
        bytes32 rateId = bytes32(uint256(1));
        rateIds[0] = rateId;

        oracle.activateRateId(rateId);
        oracle.bond(rateIds);

        oracle.lock(rateIds);
    }

    function test_lock_unregistersRates() public {
        bytes32[] memory rateIds = new bytes32[](3);
        for (uint256 idx = 0; idx < rateIds.length; ++idx) {
            rateIds[idx] = bytes32(uint256(idx + 1));
            oracle.activateRateId(rateIds[idx]);
        }

        _setMockERC20balanceOf(bondSize);

        oracle.bond(rateIds);

        oracle.lock(rateIds);

        for (uint256 idx = 0; idx < rateIds.length; ++idx) {
            assertTrue(
                oracle.activeRateIds(rateIds[idx]) == false,
                "RateId should be removed"
            );
        }
    }

    function test_lock_shiftReverts(uint256 value, bytes32 nonce) public {
        bytes32[] memory rateIds = new bytes32[](1);
        bytes32 rateId = bytes32(uint256(1));
        rateIds[0] = rateId;

        oracle.activateRateId(rateId);
        oracle.bond(rateIds);

        oracle.lock(rateIds);

        // Set the mock validator response
        oracle.setMockNonce(nonce);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle
                    .OptimisticOracle__shift_invalidPreviousProposal
                    .selector
            )
        );

        // Run the initial shift where we need to pass 0 as prevValue and prevNonce
        oracle.shift(rateId, address(0), 0, 0, value, "");
    }

    function test_recover() public {
        bytes32 rateId = bytes32(uint256(1));
        // Create default proposal where proposer is not address(this)
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Unregister the rate
        oracle.deactivateRateId(rateId);

        oracle.recover(rateId, address(this));
    }

    function test_recover_transfersBondToReceiver() public {
        bytes32 rateId = bytes32(uint256(1));
        // Create default proposal where proposer is not address(this)
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        // Unregister the rate
        oracle.deactivateRateId(rateId);

        address receiver = address(0x1234);
        vm.expectCall(
            mockERC20,
            abi.encodeWithSelector(IERC20.transfer.selector, receiver, bondSize)
        );
        oracle.recover(rateId, receiver);
    }

    function test_recover_revertsOnRegisteredRate() public {
        bytes32 rateId = bytes32(uint256(1));
        // Create default proposal where proposer is not address(this)
        oracle.activateRateId(rateId);
        _bond(address(this), rateId);

        address receiver = address(0x1234);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticOracle.OptimisticOracle__recover_notLocked.selector
            )
        );
        oracle.recover(rateId, receiver);
    }

    function test_allowProposer(address proposer) public {
        if (proposer == address(this)) return;

        assertTrue(
            oracle.canCall(bytes4(keccak256("bond(bytes32[])")), proposer) ==
                false
        );

        oracle.allowProposer(proposer);

        assertTrue(
            oracle.canCall(bytes4(keccak256("bond(bytes32[])")), proposer)
        );
    }
}

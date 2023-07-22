// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StorageHelper {
    event Debug(uint256, bytes32);
    event SlotFound(address who, string sig, uint256 slot);
    event DebugSlot(uint256 slotIndex, bytes32 slot, bytes32 value);
    event Logger(uint256, bytes);

    Vm public cheatCodes = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function find(
        address contractAddress,
        bytes32[] memory slots,
        bytes32 value
    ) public returns (bool, bytes32) {
        for (uint256 i = 0; i < slots.length; ++i) {
            bytes32 prev = cheatCodes.load(contractAddress, slots[i]);
            if (prev == value) return (true, slots[i]);
        }

        return (false, bytes32(0));
    }

    function find(
        address contractAddress,
        uint256 searchSize,
        bytes32 value
    ) public returns (bool, bytes32) {
        for (uint256 i = 0; i < searchSize; ++i) {
            bytes32 slotKey = bytes32(i);
            bytes32 prev = cheatCodes.load(contractAddress, slotKey);
            if (prev == value) return (true, slotKey);
        }

        return (false, bytes32(0));
    }

    function findMapToStruct(
        address contractAddress,
        uint256 searchSize,
        bytes32[] memory mapkeys,
        uint256 propertySlot,
        bytes32 value
    )
        public
        returns (
            bool,
            bytes32,
            uint256
        )
    {
        for (
            uint256 storageSlotIdx = 0;
            storageSlotIdx < searchSize;
            ++storageSlotIdx
        ) {
            bytes32 slotKey = bytes32(storageSlotIdx);
            bytes32 prev = cheatCodes.load(contractAddress, slotKey);
            if (prev == value) return (true, slotKey, storageSlotIdx);

            for (uint256 mapIndex = 0; mapIndex < mapkeys.length; ++mapIndex) {
                slotKey = bytes32(
                    uint256(
                        keccak256(
                            abi.encode(
                                uint256(mapkeys[mapIndex]),
                                uint256(storageSlotIdx)
                            )
                        )
                    ) + propertySlot
                );
                prev = cheatCodes.load(contractAddress, slotKey);
                if (prev == value) return (true, slotKey, storageSlotIdx);
            }
        }

        return (false, bytes32(0), 0);
    }

    function findNestedMapsToStruct(
        address contractAddress,
        uint256 searchSize,
        bytes32 mapKey1,
        bytes32 mapKey2,
        uint256 propertySlot,
        bytes32 value
    )
        public
        returns (
            bool,
            bytes32,
            uint256
        )
    {
        for (
            uint256 storageSlotIdx = 0;
            storageSlotIdx < searchSize;
            ++storageSlotIdx
        ) {
            bytes32 slotKey = keccak256(
                abi.encode(
                    uint256(mapKey2),
                    uint256(
                        keccak256(
                            abi.encode(
                                uint256(mapKey1),
                                uint256(storageSlotIdx)
                            )
                        )
                    ) + propertySlot
                )
            );
            bytes32 storageValue = bytes32(
                cheatCodes.load(contractAddress, slotKey)
            );
            emit DebugSlot(storageSlotIdx, slotKey, storageValue);
            if (storageValue == value) return (true, slotKey, storageSlotIdx);
        }

        return (false, bytes32(0), 0);
    }

    function findMapToStruct(
        address contractAddress,
        uint256 searchSize,
        bytes32[] memory mapkeys,
        bytes32 value
    ) public returns (bool, bytes32) {
        for (
            uint256 storageSlotIdx = 0;
            storageSlotIdx < searchSize;
            ++storageSlotIdx
        ) {
            bytes32 slotKey = bytes32(storageSlotIdx);
            bytes32 prev = cheatCodes.load(contractAddress, slotKey);
            if (prev == value) return (true, slotKey);

            for (uint256 mapIndex = 0; mapIndex < mapkeys.length; ++mapIndex) {
                slotKey = keccak256(
                    abi.encode(
                        uint256(mapkeys[mapIndex]),
                        uint256(storageSlotIdx)
                    )
                );
                prev = cheatCodes.load(contractAddress, slotKey);
                if (prev == value) return (true, slotKey);
            }
        }

        return (false, bytes32(0));
    }
}

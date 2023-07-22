// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @notice Copied from:
/// https://github.com/hamdiallam/Solidity-RLP/blob/master/contracts/RLPReader.sol
/// at commit ba24e1213f720b1e6ab7b44848c38b40222b049f
/// Changes from original:
/// - Upgraded to Solidity ^0.8.0
/// - Added custom errors
/// - Updated inline docs
library RLPReader {
    error RLPReader__next_noNext();
    error RLPReader__iterator_notList();
    error RLPReader__toList_notList();
    error RLPReader__toBoolean_invalidLen();
    error RLPReader__toAddress_invalidLen();
    error RLPReader__toUint_invalidLen();
    error RLPReader__toUintStrict_invalidLen();
    error RLPReader__toBytes_invalidLen();

    uint8 internal constant STRING_SHORT_START = 0x80;
    uint8 internal constant STRING_LONG_START = 0xb8;
    uint8 internal constant LIST_SHORT_START = 0xc0;
    uint8 internal constant LIST_LONG_START = 0xf8;
    uint8 internal constant WORD_SIZE = 32;

    struct RLPItem {
        uint256 len;
        uint256 memPtr;
    }

    struct Iterator {
        RLPItem item; // Item that's being iterated over
        uint256 nextPtr; // Position of the next item in the list
    }

    /// @notice Returns the next element in the iteration. Reverts if it has not next element
    /// @param self The iterator
    function next(Iterator memory self) internal pure returns (RLPItem memory) {
        if (!hasNext(self)) revert RLPReader__next_noNext();

        uint256 ptr = self.nextPtr;
        uint256 itemLength = _itemLength(ptr);
        unchecked {
            self.nextPtr = ptr + itemLength;
        }
        return RLPItem(itemLength, ptr);
    }

    /// @notice Returns true if the iteration has more elements
    /// @param self The iterator
    /// @return has true if the iteration has more elements
    function hasNext(Iterator memory self) internal pure returns (bool) {
        unchecked {
            RLPItem memory item = self.item;
            return self.nextPtr < item.memPtr + item.len;
        }
    }

    /// @notice Casts an rlp encoded bytes string to `RLPItem`
    /// @param item RLP encoded bytes string
    /// @return item RLPItem
    function toRlpItem(bytes memory item)
        internal
        pure
        returns (RLPItem memory)
    {
        uint256 memPtr;
        assembly {
            memPtr := add(item, 0x20)
        }

        return RLPItem(item.length, memPtr);
    }

    /// @notice Create an iterator. Reverts if item is not a list.
    /// @param self The RLP item
    /// @return iterator An 'Iterator' over the item
    function iterator(RLPItem memory self)
        internal
        pure
        returns (Iterator memory)
    {
        if (!isList(self)) revert RLPReader__iterator_notList();

        unchecked {
            uint256 ptr = self.memPtr + _payloadOffset(self.memPtr);
            return Iterator(self, ptr);
        }
    }

    /// @param item RLP encoded bytes
    function rlpLen(RLPItem memory item) internal pure returns (uint256) {
        return item.len;
    }

    /// @param item RLP encoded bytes
    function payloadLen(RLPItem memory item) internal pure returns (uint256) {
        return item.len - _payloadOffset(item.memPtr);
    }

    /// @param item RLP encoded list in bytes
    function toList(RLPItem memory item)
        internal
        pure
        returns (RLPItem[] memory)
    {
        if (!isList(item)) revert RLPReader__toList_notList();

        uint256 items = numItems(item);
        RLPItem[] memory result = new RLPItem[](items);

        unchecked {
            uint256 memPtr = item.memPtr + _payloadOffset(item.memPtr);
            uint256 dataLen;
            for (uint256 i = 0; i < items; i++) {
                dataLen = _itemLength(memPtr);
                result[i] = RLPItem(dataLen, memPtr);
                memPtr = memPtr + dataLen;
            }

            return result;
        }
    }

    /// @return isList Indicator whether encoded payload is a list. negate this function call for isData.
    function isList(RLPItem memory item) internal pure returns (bool) {
        if (item.len == 0) return false;

        uint8 byte0;
        uint256 memPtr = item.memPtr;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        if (byte0 < LIST_SHORT_START) return false;
        return true;
    }

    /// @notice A cheaper version of keccak256(toRlpBytes(item)) that avoids copying memory.
    /// @return hash keccak256 hash of RLP encoded bytes.
    function rlpBytesKeccak256(RLPItem memory item)
        internal
        pure
        returns (bytes32)
    {
        uint256 ptr = item.memPtr;
        uint256 len = item.len;
        bytes32 result;
        assembly {
            result := keccak256(ptr, len)
        }
        return result;
    }

    /// @notice A cheaper version of keccak256(toBytes(item)) that avoids copying memory.
    /// @return hash keccak256 hash of the unerlying data.
    function dataKeccak256(RLPItem memory item)
        internal
        pure
        returns (bytes32)
    {
        uint256 offset = _payloadOffset(item.memPtr);
        uint256 ptr;
        uint256 len;
        unchecked {
            ptr = item.memPtr + offset;
            len = item.len - offset;
        }

        bytes32 result;
        assembly {
            result := keccak256(ptr, len)
        }
        return result;
    }

    /// ======== RLPItem conversions ======== ///

    /// @return rlpBytes raw rlp encoding in bytes
    function toRlpBytes(RLPItem memory item)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory result = new bytes(item.len);
        if (result.length == 0) return result;

        uint256 ptr;
        assembly {
            ptr := add(0x20, result)
        }

        copy(item.memPtr, ptr, item.len);
        return result;
    }

    // any non-zero byte except "0x80" is considered true
    function toBoolean(RLPItem memory item) internal pure returns (bool) {
        if (item.len != 1) revert RLPReader__toBoolean_invalidLen();

        uint256 result;
        uint256 memPtr = item.memPtr;
        assembly {
            result := byte(0, mload(memPtr))
        }

        // SEE Github Issue #5.
        // Summary: Most commonly used RLP libraries (i.e Geth) will encode
        // "0" as "0x80" instead of as "0". We handle this edge case explicitly
        // here.
        if (result == 0 || result == STRING_SHORT_START) {
            return false;
        } else {
            return true;
        }
    }

    function toAddress(RLPItem memory item) internal pure returns (address) {
        // 1 byte for the length prefix
        if (item.len != 21) revert RLPReader__toAddress_invalidLen();

        return address(uint160(toUint(item)));
    }

    function toUint(RLPItem memory item) internal pure returns (uint256) {
        if (item.len == 0 || item.len > 33)
            revert RLPReader__toUint_invalidLen();

        uint256 offset = _payloadOffset(item.memPtr);
        uint256 len;
        uint256 result;
        uint256 memPtr;
        unchecked {
            len = item.len - offset;
            memPtr = item.memPtr + offset;
        }

        assembly {
            result := mload(memPtr)

            // shift to the correct location if necessary
            if lt(len, 32) {
                result := div(result, exp(256, sub(32, len)))
            }
        }

        return result;
    }

    // enforces 32 byte length
    function toUintStrict(RLPItem memory item) internal pure returns (uint256) {
        // one byte prefix
        if (item.len != 33) revert RLPReader__toUintStrict_invalidLen();

        uint256 result;
        uint256 memPtr;
        unchecked {
            memPtr = item.memPtr + 1;
        }
        assembly {
            result := mload(memPtr)
        }

        return result;
    }

    function toBytes(RLPItem memory item) internal pure returns (bytes memory) {
        if (item.len == 0) revert RLPReader__toBytes_invalidLen();

        uint256 offset = _payloadOffset(item.memPtr);
        uint256 len;
        unchecked {
            len = item.len - offset; // data length
        }
        bytes memory result = new bytes(len);

        uint256 destPtr;
        assembly {
            destPtr := add(0x20, result)
        }

        unchecked {
            copy(item.memPtr + offset, destPtr, len);
        }

        return result;
    }

    /// ======== Private Helpers ======== ///

    /// @return number of payload items inside an encoded list.
    function numItems(RLPItem memory item) private pure returns (uint256) {
        if (item.len == 0) return 0;

        uint256 count = 0;
        unchecked {
            uint256 currPtr = item.memPtr + _payloadOffset(item.memPtr);
            uint256 endPtr = item.memPtr + item.len;
            while (currPtr < endPtr) {
                currPtr = currPtr + _itemLength(currPtr); // skip over an item
                count++;
            }
        }

        return count;
    }

    /// @return length entire rlp item byte length
    function _itemLength(uint256 memPtr) private pure returns (uint256) {
        uint256 itemLen;
        uint256 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        unchecked {
            if (byte0 < STRING_SHORT_START) itemLen = 1;
            else if (byte0 < STRING_LONG_START)
                itemLen = byte0 - STRING_SHORT_START + 1;
            else if (byte0 < LIST_SHORT_START) {
                assembly {
                    let byteLen := sub(byte0, 0xb7) // # of bytes the actual length is
                    memPtr := add(memPtr, 1) // skip over the first byte

                    /* 32 byte word size */
                    let dataLen := div(
                        mload(memPtr),
                        exp(256, sub(32, byteLen))
                    ) // right shifting to get the len
                    itemLen := add(dataLen, add(byteLen, 1))
                }
            } else if (byte0 < LIST_LONG_START) {
                itemLen = byte0 - LIST_SHORT_START + 1;
            } else {
                assembly {
                    let byteLen := sub(byte0, 0xf7)
                    memPtr := add(memPtr, 1)

                    let dataLen := div(
                        mload(memPtr),
                        exp(256, sub(32, byteLen))
                    ) // right shifting to the correct length
                    itemLen := add(dataLen, add(byteLen, 1))
                }
            }
        }

        return itemLen;
    }

    /// @return offset number of bytes until the data
    function _payloadOffset(uint256 memPtr) private pure returns (uint256) {
        uint256 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        unchecked {
            if (byte0 < STRING_SHORT_START) return 0;
            else if (
                byte0 < STRING_LONG_START ||
                (byte0 >= LIST_SHORT_START && byte0 < LIST_LONG_START)
            ) return 1;
            else if (byte0 < LIST_SHORT_START)
                // being explicit
                return byte0 - (STRING_LONG_START - 1) + 1;
            else return byte0 - (LIST_LONG_START - 1) + 1;
        }
    }

    /// @param src Pointer to source
    /// @param dest Pointer to destination
    /// @param len Amount of memory to copy from the source
    function copy(
        uint256 src,
        uint256 dest,
        uint256 len
    ) private pure {
        if (len == 0) return;

        // copy as many word sizes as possible
        for (; len >= WORD_SIZE; len -= WORD_SIZE) {
            assembly {
                mstore(dest, mload(src))
            }

            unchecked {
                src += WORD_SIZE;
                dest += WORD_SIZE;
            }
        }

        // left over bytes. Mask is used to remove unwanted bytes from the word
        uint256 mask;
        unchecked {
            mask = 256**(WORD_SIZE - len) - 1;
        }

        assembly {
            let srcpart := and(mload(src), not(mask)) // zero out src
            let destpart := and(mload(dest), mask) // retrieve the bytes
            mstore(dest, or(destpart, srcpart))
        }
    }
}

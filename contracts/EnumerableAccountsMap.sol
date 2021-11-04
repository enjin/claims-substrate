// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

/**
 * @dev Library for managing an enumerable accounts map
 *
 * Maps have the following properties:
 *
 * - Entries are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Entries are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableAccountsMap for EnumerableAccountsMap.Map;
 *
 *     // Declare a set state variable
 *     EnumerableAccountsMap.Map private accounts;
 * }
 * ```
 */
library EnumerableAccountsMap {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    struct Account {
        uint256 balance; // current balance
        bytes32 pubkey;  // x25519 public key.
        uint256[10] __gap;
    }

    // Maps an Address to Account
    struct Map {
        // Storage of keys
        EnumerableSetUpgradeable.AddressSet _keys;
        mapping(address => Account) _values;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    function set(
        Map storage map,
        address key,
        Account memory value
    ) internal returns (bool) {
        map._values[key] = value;
        return map._keys.add(key);
    }

    /**
     * @dev Removes a key-value pair from a map. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function remove(Map storage map, address key) internal returns (bool) {
        delete map._values[key];
        return map._keys.remove(key);
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function contains(Map storage map, address key) internal view returns (bool) {
        return map._keys.contains(key);
    }

    /**
     * @dev Returns the number of key-value pairs in the map. O(1).
     */
    function length(Map storage map) internal view returns (uint256) {
        return map._keys.length();
    }

    /**
     * @dev Returns the key-value pair stored at position `index` in the map. O(1).
     *
     * Note that there are no guarantees on the ordering of entries inside the
     * array, and it may change when more entries are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Map storage map, uint256 index) internal view returns (address, Account storage) {
        address key = map._keys.at(index);
        return (key, map._values[key]);
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     *
     * Requirements:
     *
     * - `key` must be in the map.
     */
    function get(Map storage map, address key) internal view returns (Account storage) {
        require(contains(map, key), "EnumerableAccountsMap: account doesn't exists");
        return map._values[key];
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     */
    function getUnchecked(Map storage map, address key) internal view returns (Account storage) {
        return map._values[key];
    }
}

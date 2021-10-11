// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @author Web3 Foundation
/// @title  Claims
///         Allows allocations to be claimed to Polkadot public keys.
contract Claims is Ownable {
    // The maximum number contained by the type `uint`. Used to freeze the contract from claims.
    uint256 public constant UINT_MAX = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    struct Claim {
        uint256 index; // Index for short address.
        bytes32 pubKey; // x25519 public key.
        bool hasIndex; // Has the index been set?
        uint256 vested; // Amount of allocation that is vested.
    }

    // The address of the allocation indicator contract.
    IERC20 public allocationIndicator;

    // The next index to be assigned.
    uint256 public nextIndex;

    // Maps allocations to `Claim` data.
    mapping(address => Claim) public claims;

    // A mapping from pubkey to the sale amount from second sale.
    mapping(bytes32 => uint256) public saleAmounts;

    // A mapping of pubkeys => an array of ethereum addresses that have made a claim for this pubkey.
    // - Used for getting the balance.
    mapping(bytes32 => address[]) public claimsForPubkey;

    // Addresses that already claimed so we can easily grab them from state.
    address[] public claimed;

    // Amended keys, old address => new address. New address is allowed to claim for old address.
    mapping(address => address) public amended;

    // Block number that the set up delay ends.
    uint256 public endSetUpDelay;

    // Event for when an allocation address amendment is made.
    event Amended(address indexed original, address indexed amendedTo);
    // Event for when an allocation is claimed to a Polkadot address.
    event Claimed(address indexed eth, bytes32 indexed dot, uint256 indexed idx);
    // Event for when an index is assigned to an allocation.
    event IndexAssigned(address indexed eth, uint256 indexed idx);
    // Event for when vesting is set on an allocation.
    event Vested(address indexed eth, uint256 amount);
    // Event for when vesting is increased on an account.
    event VestedIncreased(address indexed eth, uint256 newTotal);
    // Event that triggers when a new sale injection is made.
    event InjectedSaleAmount(bytes32 indexed pubkey, uint256 newTotal);

    constructor(
        address _owner,
        address payable _allocations,
        uint256 _setUpDelay
    ) {
        require(_owner != address(0x0), "Must provide an owner address.");
        require(_allocations != address(0x0), "Must provide an allocations address.");
        require(_setUpDelay > 0, "Must provide a non-zero argument to _setUpDelay.");

        transferOwnership(_owner);
        allocationIndicator = IERC20(_allocations);

        endSetUpDelay = block.number + _setUpDelay;
    }

    /// Allows owner to manually amend allocations to a new address that can claim.
    /// @dev The given arrays must be same length and index must map directly.
    /// @param _origs An array of original (allocation) addresses.
    /// @param _amends An array of the new addresses which can claim those allocations.
    function amend(address[] calldata _origs, address[] calldata _amends) external onlyOwner {
        require(_origs.length == _amends.length, "Must submit arrays of equal length.");

        for (uint256 i = 0; i < _amends.length; i++) {
            require(!hasClaimed(_origs[i]), "Address has already claimed.");
            require(hasAllocation(_origs[i]), "Ethereum address has no DOT allocation.");
            amended[_origs[i]] = _amends[i];
            emit Amended(_origs[i], _amends[i]);
        }
    }

    /// Allows owner to manually toggle vesting onto allocations.
    /// @param _eths The addresses for which to set vesting.
    /// @param _vestingAmts The amounts that the accounts are vested.
    function setVesting(address[] calldata _eths, uint256[] calldata _vestingAmts) external onlyOwner {
        require(_eths.length == _vestingAmts.length, "Must submit arrays of equal length.");

        for (uint256 i = 0; i < _eths.length; i++) {
            Claim storage claimData = claims[_eths[i]];
            require(!hasClaimed(_eths[i]), "Account must not be claimed.");
            require(claimData.vested == 0, "Account must not be vested already.");
            require(_vestingAmts[i] != 0, "Vesting amount must be greater than zero.");
            claimData.vested = _vestingAmts[i];
            emit Vested(_eths[i], _vestingAmts[i]);
        }
    }

    /// Allows owner to increase the vesting on an allocation, whether it is claimed or not.
    /// @param _eths The addresses for which to increase vesting.
    /// @param _vestingAmts The amounts to increase the vesting for each account.
    function increaseVesting(address[] calldata _eths, uint256[] calldata _vestingAmts) external onlyOwner {
        require(_eths.length == _vestingAmts.length, "Must submit arrays of equal length.");

        for (uint256 i = 0; i < _eths.length; i++) {
            Claim storage claimData = claims[_eths[i]];
            // Does not require that the allocation is unclaimed.
            // Does not require that vesting has already been set or not.
            require(_vestingAmts[i] > 0, "Vesting amount must be greater than zero.");
            uint256 oldVesting = claimData.vested;
            uint256 newVesting;
            newVesting = oldVesting + _vestingAmts[i];
            claimData.vested = newVesting;
            emit VestedIncreased(_eths[i], newVesting);
        }
    }

    /// Allows owner to increase the `saleAmount` for a pubkey by the injected amount.
    /// @param _pubkeys The public keys that will have their balances increased.
    /// @param _amounts The amounts to increase the balance of pubkeys.
    function injectSaleAmount(bytes32[] calldata _pubkeys, uint256[] calldata _amounts) external onlyOwner {
        require(_pubkeys.length == _amounts.length);

        for (uint256 i = 0; i < _pubkeys.length; i++) {
            bytes32 pubkey = _pubkeys[i];
            uint256 amount = _amounts[i];

            // Checks that input is not zero.
            require(amount > 0, "Must inject a sale amount greater than zero.");

            uint256 oldValue = saleAmounts[pubkey];
            uint256 newValue = oldValue + amount;
            saleAmounts[pubkey] = newValue;

            emit InjectedSaleAmount(pubkey, newValue);
        }
    }

    /// A helper function that allows anyone to check the balances of public keys.
    /// @param _who The public key to check the balance of.
    function balanceOfPubkey(bytes32 _who) public view returns (uint256) {
        address[] storage frozenTokenHolders = claimsForPubkey[_who];
        if (frozenTokenHolders.length > 0) {
            uint256 total;
            for (uint256 i = 0; i < frozenTokenHolders.length; i++) {
                total += allocationIndicator.balanceOf(frozenTokenHolders[i]);
            }
            return total + saleAmounts[_who];
        }
        return saleAmounts[_who];
    }

    /// Freezes the contract from any further claims.
    /// @dev Protected by the `onlyOwner` modifier.
    function freeze() external onlyOwner {
        endSetUpDelay = UINT_MAX;
    }

    /// Allows anyone to assign a batch of indices onto unassigned and unclaimed allocations.
    /// @dev This function is safe because all the necessary checks are made on `assignNextIndex`.
    /// @param _eths An array of allocation addresses to assign indices for.
    function assignIndices(address[] calldata _eths) external onlyDuringSetUpDelay {
        for (uint256 i = 0; i < _eths.length; i++) {
            require(_assignNextIndex(_eths[i]), "Assigning the next index failed.");
        }
    }

    /// Claims an allocation associated with an `_eth` address to a `_pubKey` public key.
    /// @dev Can only be called by the `_eth` address or the amended address for the allocation.
    /// @param _eth The allocation address to claim.
    /// @param _pubKey The Polkadot public key to claim.
    function claim(address _eth, bytes32 _pubKey)
        external
        onlyAfterSetUpDelay
        checkHasAllocation(_eth)
        checkNotClaimed(_eth)
    {
        require(_pubKey != bytes32(0), "Failed to provide an Ed25519 or SR25519 public key.");

        if (amended[_eth] != address(0x0)) {
            require(amended[_eth] == msg.sender, "Address is amended and sender is not the amendment.");
        } else {
            require(_eth == msg.sender, "Sender is not the allocation address.");
        }

        if (claims[_eth].index == 0 && !claims[_eth].hasIndex) {
            require(_assignNextIndex(_eth), "Assigning the next index failed.");
        }

        claims[_eth].pubKey = _pubKey;
        claimed.push(_eth);
        claimsForPubkey[_pubKey].push(_eth);

        emit Claimed(_eth, _pubKey, claims[_eth].index);
    }

    /// Get the length of `claimed`.
    /// @return uint The number of accounts that have claimed.
    function claimedLength() external view returns (uint256) {
        return claimed.length;
    }

    /// Get whether an allocation has been claimed.
    /// @return bool True if claimed.
    function hasClaimed(address _eth) public view returns (bool) {
        return claims[_eth].pubKey != bytes32(0);
    }

    /// Get whether an address has an allocation.
    /// @return bool True if has a balance of FrozenToken.
    function hasAllocation(address _eth) public view returns (bool) {
        uint256 bal = allocationIndicator.balanceOf(_eth);
        return bal > 0;
    }

    /// Assings an index to an allocation address.
    /// @dev Public function.
    /// @param _eth The allocation address.
    function _assignNextIndex(address _eth) internal checkHasAllocation(_eth) checkNotClaimed(_eth) returns (bool) {
        require(claims[_eth].index == 0, "Cannot reassign an index.");
        require(!claims[_eth].hasIndex, "Address has already been assigned an index.");
        uint256 idx = nextIndex;
        nextIndex++;
        claims[_eth].index = idx;
        claims[_eth].hasIndex = true;
        emit IndexAssigned(_eth, idx);
        return true;
    }

    /// @dev Requires that `_eth` address has DOT allocation.
    modifier checkHasAllocation(address _eth) {
        require(hasAllocation(_eth), "Ethereum address has no DOT allocation.");
        _;
    }

    /// @dev Requires that `_eth` address has not claimed.
    modifier checkNotClaimed(address _eth) {
        require(claims[_eth].pubKey == bytes32(0), "Account has already claimed.");
        _;
    }

    /// @dev Requires that the function with this modifier is evoked after `endSetUpDelay`.
    modifier onlyAfterSetUpDelay() {
        require(block.number >= endSetUpDelay, "This function is only evocable after the setUpDelay has elapsed.");
        _;
    }

    /// @dev Requires that the function with this modifier is evoked only by owner before `endSetUpDelay`.
    modifier onlyDuringSetUpDelay() {
        if (block.number < endSetUpDelay) {
            require(
                msg.sender == owner(),
                "Only owner is allowed to call this function before the end of the set up delay."
            );
        }
        _;
    }
}

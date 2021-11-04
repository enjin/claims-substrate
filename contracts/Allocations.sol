// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./EnumerableAccountsMap.sol";

/// @author Enjin
/// @title  Claims
/// Allows allocations to be claimed to Substrate public keys.
contract Allocations is Initializable, OwnableUpgradeable {
    using AddressUpgradeable for address;
    using EnumerableAccountsMap for EnumerableAccountsMap.Map;
    using EnumerableAccountsMap for EnumerableAccountsMap.Account;

    // The address of the ERC20 contract.
    IERC20Upgradeable private _token;

    // Storage and mapping of all balances & pubkeys
    EnumerableAccountsMap.Map private _accounts;

    // Block number that the deposit period ends.
    uint256 private _freezeDelay;

    // Event for when an allocation address received a deposit
    event Deposited(address indexed from, address indexed to, uint256 amount, uint256 newTotal);
    // Event for when an allocation address withdraws.
    event Withdrew(address indexed from, address indexed to, uint256 amount, uint256 newTotal);

    function Allocations_init(address token, uint256 freezeDelay_) external initializer {
        __Allocations_init(token, freezeDelay_);
    }

    function __Allocations_init(address token, uint256 freezeDelay_) internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Allocations_init_unchained(token, freezeDelay_);
    }

    function __Allocations_init_unchained(address token, uint256 freezeDelay_) internal initializer {
        require(token.isContract(), "Allocations: Must be an ERC20 contract");
        require(freezeDelay_ > block.number, "Allocations: freezeDelay must be greater than the current block.number");
        _token = IERC20Upgradeable(token);
        _freezeDelay = freezeDelay_;
    }

    /// @dev Returns the set up delay
    function freezeDelay() public view returns (uint256) {
        return _freezeDelay;
    }

    /// Allows owner to manually amend allocations to a new address that can claim.
    /// @dev The given arrays must be same length and index must map directly.
    /// @param recipient An array of original (allocation) addresses.
    /// @param amount An array of the new addresses which can claim those allocations.
    function deposit(address recipient, uint256 amount) external ifNotFreeze {
        require(amount > 0, "Allocations: deposit amount must be greater than zero");

        address sender = _msgSender();
        _token.transferFrom(sender, address(this), amount);

        if (_accounts.contains(recipient)) {
            // Update account balance
            EnumerableAccountsMap.Account storage account = _accounts.getUnchecked(recipient);
            uint256 newBalance = account.balance + amount;
            account.balance = newBalance;
            emit Deposited(sender, recipient, amount, newBalance);
        } else {
            // Only EOA are allowed to be recipients, contracts cannot use "personal_sign" to claims the tokens
            require(!recipient.isContract(), "Allocations: the recipient must be an EOA account");

            // Create a new account
            uint256[10] memory gap;
            EnumerableAccountsMap.Account memory newAccount = EnumerableAccountsMap.Account({
                balance: amount,
                pubkey: 0x0,
                __gap: gap
            });
            _accounts.set(recipient, newAccount);
            emit Deposited(sender, recipient, amount, amount);
        }
    }

    /// Allows owner to withdraw its funds before freeze
    /// @param to recipient account
    /// @param amount amount of tokens to transfer
    function withdraw(address to, uint256 amount) external ifNotFreeze {
        address from = _msgSender();

        EnumerableAccountsMap.Account storage account = _accounts.getUnchecked(from);
        require(
            _accounts.contains(from) && account.balance >= amount,
            "Allocations: withdraw amount exceeds sender's allocated balance"
        );

        uint256 newBalance = account.balance - amount;
        account.balance = newBalance;

        if (newBalance == 0) {
            // Delete account
            _accounts.remove(from);
        }

        _token.transfer(to, amount);
        emit Withdrew(from, to, amount, newBalance);
    }

    // balance of a specific address
    function balanceOf(address who) public view returns (uint256) {
        if (_accounts.contains(who)) {
            EnumerableAccountsMap.Account storage account = _accounts.getUnchecked(who);
            return account.balance;
        }
        return 0;
    }

    function accountsCount() public view returns (uint256) {
        return _accounts.length();
    }

    function accountAt(uint256 index) public view returns (address, uint256) {
        (address eth, EnumerableAccountsMap.Account storage account) = _accounts.at(index);
        return (eth, account.balance);
    }

    /// Freezes the contract from any further deposits or withdraws.
    /// @dev Protected by the `onlyOwner` modifier.
    function freeze() external onlyOwner {
        _freezeDelay = block.number;
    }

    /// @dev Requires that the function with this modifier is evoked only before `_freezeDelay`.
    modifier ifNotFreeze() {
        require(block.number < _freezeDelay, "Allocations: this contract is frozen, method not allowed");
        _;
    }

    uint256[46] private __gap;
}

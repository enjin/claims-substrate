// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @author Enjin
/// @title  Claims
/// Allows allocations to be claimed to Substrate public keys.
contract Allocations is Ownable {
    using Address for address;

    // The address of the ERC20 contract.
    IERC20 private _token;

    // Storage and mapping of all balances & allowances
    mapping(address => uint256) private _balances;

    // Block number that the deposit period ends.
    uint256 private _freezeDelay;

    // Event for when an allocation address amendment is made.
    event Allocated(address indexed operator, address indexed to, uint256 amount, uint256 newTotal);

    // Event for when an allocation address amendment is made.
    event Withdraw(address indexed from, address indexed to, uint256 amount, uint256 newTotal);

    constructor(address token, uint256 freezeDelay_) {
        require(token.isContract(), "Allocations: Must be an ERC20 contract");
        require(freezeDelay_ > block.number, "Allocations: freezeDelay must be greater than the current block.number");
        _token = IERC20(token);
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
    function allocate(address recipient, uint256 amount) external ifNotFreeze {
        address sender = _msgSender();
        _token.transferFrom(sender, address(this), amount);
        uint256 newBalance = _balances[recipient] + amount;
        _balances[recipient] = newBalance;
        emit Allocated(sender, recipient, amount, newBalance);
    }

    /// Allows owner to withdraw its funds before freeze
    /// @param to recipient account
    /// @param amount amount of tokens to transfer
    function withdraw(address to, uint256 amount) external ifNotFreeze {
        address sender = _msgSender();
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "Allocations: withdraw amount exceeds sender's allocated balance");
        senderBalance -= amount;
        _balances[sender] = senderBalance;
        _token.transfer(to, amount);
        emit Withdraw(sender, to, amount, senderBalance);
    }

    // balance of a specific address
    function balanceOf(address _who) public view returns (uint256) {
        return _balances[_who];
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
}

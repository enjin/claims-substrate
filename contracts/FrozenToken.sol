// SPDX-License-Identifier: GPL-3.0

/**
 * Source Code first verified at https://etherscan.io on Wednesday, October 11, 2017
 (UTC) */

//! FrozenToken ECR20-compliant token contract
//! By Parity Technologies, 2017.
//! Released under the Apache Licence 2.

pragma solidity ^0.8.3;

// Owned contract.
contract Owned {
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    event NewOwner(address indexed old, address indexed current);

    function setOwner(address _new) public onlyOwner {
        emit NewOwner(owner, _new);
        owner = _new;
    }

    address public owner;
}

// FrozenToken, a bit like an ECR20 token (though not - as it doesn't
// implement most of the API).
// All token balances are generally non-transferable.
// All "tokens" belong to the owner (who is uniquely liquid) at construction.
// Liquid accounts can make other accounts liquid and send their tokens
// to other axccounts.
contract FrozenToken is Owned {
    event Transfer(address indexed from, address indexed to, uint256 value);

    // this is as basic as can be, only the associated balance & allowances
    struct Account {
        uint256 balance;
        bool liquid;
    }

    // constructor sets the parameters of execution, _totalSupply is all units
    constructor(uint256 _totalSupply, address _owner) whenNonZero(_totalSupply) {
        totalSupply = _totalSupply;
        owner = _owner;
        _accounts[_owner].balance = totalSupply;
        _accounts[_owner].liquid = true;
    }

    // balance of a specific address
    function balanceOf(address _who) public view returns (uint256) {
        return _accounts[_who].balance;
    }

    // make an account liquid: only liquid accounts can do this.
    function makeLiquid(address _to) public whenLiquid(msg.sender) returns (bool) {
        _accounts[_to].liquid = true;
        return true;
    }

    // transfer
    function transfer(address _to, uint256 _value)
        public
        whenOwns(msg.sender, _value)
        whenLiquid(msg.sender)
        returns (bool)
    {
        emit Transfer(msg.sender, _to, _value);
        _accounts[msg.sender].balance -= _value;
        _accounts[_to].balance += _value;

        return true;
    }

    // no default function, simple contract only, entry-level users
    fallback() external payable {
        assert(false);
    }

    receive() external payable {
        assert(false);
    }

    // the balance should be available
    modifier whenOwns(address _owner, uint256 _amount) {
        require(_accounts[_owner].balance >= _amount);
        _;
    }

    modifier whenLiquid(address who) {
        require(_accounts[who].liquid);
        _;
    }

    // a value should be > 0
    modifier whenNonZero(uint256 _value) {
        require(_value > 0);
        _;
    }

    // Available token supply
    uint256 public totalSupply;

    // Storage and mapping of all balances & allowances
    mapping(address => Account) _accounts;

    /**
     * @dev Returns the name of the token.
     */
    function name() external pure returns (string memory) {
        return "DOT Allocation Indicator";
    }

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external pure returns (string memory) {
        return "DOT";
    }

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external pure returns (uint8) {
        return 3;
    }
}

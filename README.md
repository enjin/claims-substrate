# Allocations

The Substrate Allocation contract is used as the on-chain document that contains relevant information for the generation of the initial state of the blockchain balance distribuition. The Allocation contract holds the mapping of Ethereum addresses to a token amount, this contract accepts ERC20 tokens deposits.

## Functionality

- Allows deposit of an ERC20 token to claim their allocation to a Substrate address.

## Run the tests

Clone the repository locally and run the following commands.

```sh
npm install
npm run test
npm run coverage
npm run lint
```

# <h1 align="center">Ecru - Optimistic Oracle</h1>

The Optimistic Oracle allows for gas-efficient oracle value updates.
Bonded proposers can optimistically propose a value for the next spot price and discount rate for a given `RateId` which
can be disputed by other proposers within `disputeWindow` by computing the value on-chain.
Each Optimistic Oracle implementation handles the data validation process.
Proposers are not rewarded for proposing new values and instead are only compensated in the event that they call the `dispute` function, 
as `dispute` is a gas intensive operation due to its computation of the expected value on-chain. 
Compensation is sourced from the bond put up by the malicious proposer. 

## Components
- **OptimisticOracle**: Base contract that handles the core lifecycle of proposals and manages proposers' bonds
- **Implementations**:
  - **OptimisticChainlinkOracle**: An Optimistic Oracle that manages values fetched from Chainlink data feeds. The validation process retrieves the values on chain and overwrites malicious proposals.

## Guides

**Becoming a proposer**:

Whitelisted proposers have to bond an amount of `bondSize` of `bondToken` for each `RateId` they want to propose values for.
If a malicious proposer proposes an incorrect value the bond is transferred to the disputer who calls `dispute` within `disputeWindow`.
This ensures that griefing becomes costly for a malicious proposer and that keepers who watch incoming proposals and dispute incorrect proposals in time are compensated.

Proposer can deposit a bond for a given `RateId` by calling [`bond`](./src/OptimisticOracle.sol#L339)
```sol
function bond(bytes32[] calldata rateIds) public
```

Proposers can retrieve their bond if one of the following conditions are true:
  - the last proposal was made by another proposer,
  - `disputeWindow` for the last proposal has elapsed,
  -  the `RateId` was unregistered from the Oracle

by calling [`unbond`](./src/OptimisticOracle.sol#L380).

```sol
function unbond(bytes32 rateId, address lastProposerForRateId, uint256 value, bytes32 nonce, address receiver) public
```

**Submitting a new proposal**:

1. Compute the value and the nonce for the next proposal off-chain by calling [`value`](./src/OptimisticChainlinkOracle.sol#L88)

```sol
function value(address token) external view returns (uint256 value_, bytes memory data)
```

2. Call [`shift`](./src/OptimisticOracle.sol#L142) referencing `prevProposer`, `prevValue`, `prevNonce` from the last proposal which can be extracted from the last
`shift` or `push` transaction.

```sol
function shift(
  bytes32 rateId, address prevProposer, uint256 prevValue, bytes32 prevNonce, uint256 value, bytes memory data
) external
```

**Onchain price update**:

1. Any actor can call the public [`push`](./src/OptimisticChainlinkOracle.sol#210) method that will compute and update the price for a `rateId` on-chain.
The `push` method also resets the current proposal for the `rateId`

**Disputing a proposal**:

Proposers are assumed to watch incoming proposals and validate them off-chain by calling [`validate`](./src/OptimisticChainlinkOracle.sol#131)

```sol
function validate(uint256 proposedValue, bytes32 rateId, bytes32 nonce, bytes memory data)
  external
  returns (bool valid, uint256 validValue, bytes32 validNonce)
```

If `validate` returns false for `proposedValue` then either the `proposeWindow` was not respected or the proposal is indeed incorrect.
Anyone is then able to call [`dispute`](./src/OptimisticOracle.sol#L183)

```sol
function dispute(
  bytes32 rateId, address proposer, address receiver, uint256 value, bytes32 nonce, bytes memory data
) external
```

`dispute` will overwrite the invalid value by making a new proposal with the computed value and will transfer the proposer's
bond to the `recipient` specified by the caller.

## Requirements
This repository uses Foundry for building and testing and Solhint for formatting the contracts.
If you do not have Foundry already installed, you'll need to run the commands below.

### Install Foundry
```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Set .env
Copy and update contents from `.env.example` to `.env`

## Tests

After installing dependencies with `make`, run `make test` to run the tests.

## Building and testing

```sh
git clone https://github.com/ecruware/ecru-oo
cd ecru-oo
make # This installs the project's dependencies.
make test
make test-gas # requires .env file (see example.env)
```

# Llama Token Voting Factory

The `LlamaTokenVotingFactory` contract enables the deployment of Llama Token Voting. This factory contract deploys a new `LlamaTokenGovernor` and `LlamaTokenAdapter`. These two contracts comprise Llama Token Voting which is how holders of a specified token can participate in Llama governance.

## Deployment

To Deploy a `LlamaTokenGovernor` and a `LlamaTokenAdapter` through the `LlamaTokenVotingFactory`, a `LlamaTokenVotingConfig` struct is passed to the deploy method on the factory contract.  

At deploy time, a `LlamaTokenAdapter` logic contract and config are passed to the factory's deploy function.

### Token Adapters

`LlamaTokenAdapter` allow the `LlamaTokenGovernor` to connect to many different implementations of tokens.

We've implemented a `LlamaTokenAdapter` that works with ERC20 and ERC721 tokens that implement the [IVotes interface](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol) and checkpoint supply using `block.timestamp`.

Many tokens checkpoint using `block.number`, or have different method names than the `IVotes` interface. The purpose of the adapter is to provide a constant interface for the governor, while being flexible to handle many different token implementations.

Currently only timestamp based tokens are supported, but we can extend functionality to tokens that checkpoint in block number by writing a new adapter.

## Integrating with a Llama instance

A dedicated role and policy with the corresponding role to the `LlamaTokenVotingGovernor` contract.

In order for token holders to approve or disapprove actions, Strategies have to utilize the `LlamaTokenVotingGovernor` as the approval or disapproval role so token holders can vote on certain actions.

Additionally, Permissions can be issued to the governor contract so that policyholders can create certain actions on your Llama instance.

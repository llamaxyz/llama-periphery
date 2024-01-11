# Llama Token Voting Factory

The `LlamaTokenVotingFactory` contract enables the deployment of token voting modules. A token voting module consists of a new `LlamaTokenGovernor` and `LlamaTokenAdapter` pair.

## Deployment

Token voting modules are configured and deployed by calling the `deploy` function on the factory with a [LlamaTokenVotingConfig](https://github.com/llamaxyz/llama-periphery/blob/main/src/lib/Structs.sol#L82) struct as the only parameter.

The struct includes values such as the action creation delegated token threshold, period lengths defined as percentages, and the vote and veto quorum percentages.

The `deploy` function also uses the provided token adapter logic contract and token adapter config to clone a new token adapter contract. This token adapter is used by the token governor to standardize the functions for retrieving the past total token supply and voting balances. 

## Integrating with a Llama instance

Once a token voting module has been deployed, an existing Llama instance can create a policy with a dedicated role and assign it to the token governor's address.

This role can be granted permissions, so token holders can create actions if they meet the creation threshold.

This role can also be used by strategies to grant token holders the ability to collectively approve and disapprove actions.

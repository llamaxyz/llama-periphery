# Llama Token Voting Factory

The `LlamaTokenVotingFactory` contract enables the deployment of token voting modules. A token voting module consists of a new `LlamaTokenGovernor` and `LlamaTokenAdapter` pair.

## Deployment

Token voting modules are configured using the [LlamaTokenVotingConfig struct](https://github.com/llamaxyz/llama-periphery/blob/main/src/lib/Structs.sol#L82). It is the factory's `deploy` function's only parameter.  

The struct includes values such as the action creation token threshold, relative voting period length, and the vote quorum.

The `deploy` function also uses the provided adapter logic contract and config to clone a token adapter contract. This token adapter is used by the token governor to standardize the functions for retrieving the historical total token supply and voting balances. 

## Integrating with a Llama instance

Once the token voting module has been deployed, an existing Llama instance can create a policy with a dedicated role and assign it to the token governor's address.

This role can be granted permissions, so token holders can create actions if they surpass the creation threshold.

This role can also be used by strategies to grant token holders the ability to approve or disapprove actions.

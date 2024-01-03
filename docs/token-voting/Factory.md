# Llama Token Voting Factory

The LlamaTokenVotingFactory contract is a key component in the Llama governance system, enabling the deployment of token voting modules. This factory contract streamlines the process of setting up a new LlamaTokenGovernor, which is essential for token holders to participate in governance through Llama.

## Deployment

To Deploy a Llama token voting governor contract through the llama token voting module factory, a `LlamaTokenVotingConfig` struct is passed to the deploy method on the factory contract. Here are the fields of the struct:

``` solidity
 ILlamaCore llamaCore; // The address of the Llama core.
 ILlamaTokenAdapter tokenAdapterLogic; // The logic contract of the token adapter.
 bytes adapterConfig; // The configuration of the token adapter.
 uint256 nonce; // The nonce to be used in the salt of the deterministic deployment.
 uint256 creationThreshold; // The number of tokens required to create an action.
 CasterConfig casterConfig; // The quorum and period data for the `LlamaTokenGovernor`.
```

The CasterConfig struct is structured like this:

```solidity
  struct CasterConfig {
    uint16 voteQuorumPct; // Minimum % of total supply for 'For' votes.
    uint16 vetoQuorumPct; // Minimum % of total supply for 'For' vetoes.
    uint16 delayPeriodPct; // % of total approval/queuing period for delay.
    uint16 castingPeriodPct; // % of total approval/queuing period for casting.
  }
```

The final non-primitive input is the token voting adapter config. Currently there is only one token voting adapter, and the config is simple:

```solidity
 struct Config {
   address token; // The address of the voting token.
 }
```

To cast the adapter config to bytes, follow this example:

```bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(tokenAddress));```

The Config struct may change with future token adapter contracts, which is why we don’t reference its type directly in the deploy function.

Learn more about token adapters [here](/docs/token-voting/TokenAdapters.md)


## Post Deployment

After deploying your token voting module, you will need to create a role and issue a policy with the corresponding role to the LlamaTokenVotingGovernor contract.

Finally, you will need to create some strategies that utilize the Caster as the approval or disapproval role so that the token holders can actually vote on certain actions.

Optionally, you can issue permissions to the governor contract if you wish for policyholders to be able to create certain actions on your llama instance.

# Llama Token Voting Module

![Llama Token Voting Module Overview](https://github.com/llamaxyz/llama/blob/main/diagrams/llama-token-voting-module-overview.png)

The Llama token voting module consists of a pair of smart contracts: a `LlamaTokenGovernor` and a token adapter.
It is deployed by the dedicated [token voting module factory](https://github.com/llamaxyz/llama/blob/main/docs/token-voting/token-voting-factory.md).

Each token voting module is associated with a Llama instance and a governance token that is used to get past total supply and account voting balances.
The `LlamaTokenGovernor` contract uses the token adapter to standardize interactions with the governance token.
Retrieving the token's past total supply and voting balances are required to conduct a voting process that can't be easily manipulated.

The token governor contract integrates directly with an associated Llama instance.
The instance creates a dedicated "Token Governor" role and assigns it to the deployed token governor contract.
This role can be granted permissions, so delegates can create actions on the instance.
This role can also be used in strategies, so delegates can collectively approve and disapprove actions on the instance.

The module can only create, approve, and disapprove actions on the associated Llama instance.
Llama instances can assign policies to multiple token voting modules to implement advanced multi-token strategies.

## Creating Actions

Governance token delegates can create actions on the associated Llama instance if they have a sufficient voting balance.

The `creationThreshold` is the number of tokens required to create an action. This value can be updated by the instance.

To create an action, a delegate must call the `createAction` function on the token governor which has the following fields:

```solidity
uint8 role,
ILlamaStrategy strategy,
address target,
uint256 value,
bytes data,
string description
```

- **Role:** A role assigned to the token governor that will be used to create the action.
- **Strategy:** The strategy contract that will determine how the action is executed.
- **Target:** The contract called when the action is executed.
- **Value:** The value in wei to be sent when the action is executed.
- **Data:** The action's function selector and its parameters.
- **Description:** A human readable description of the action and the changes it will enact.

Note that if the token governor does not have the permission to create the action on the instance's `LlamaCore`, `createAction` will fail.

Visit the [actions section](https://github.com/llamaxyz/llama/blob/main/docs/actions.md) in the llama docs to learn more about action creation.

## Approving and Disapproving Actions

The token governor allows delegates to collectively cast approvals and disapprovals for its instance's actions through votes and vetoes.
Votes and vetoes are nearly identical concepts. Votes are how token delegates build support to collectively approve an action and vetoes are how delegates build support to collectively disapprove an action.

If the token governor has the approval role or force approval role for an action, during that action's approval period delegates can cast votes to determine if the token governor should cast an approval.

If the token governor has the disapproval role or force disapproval role for an action, during that action's queueing period delegates can cast vetoes to determine if the token governor should cast a disapproval.

The entire voting and vetoing cycles take place during the action's approval and queuing periods. This includes a delay period for delegating votes, a casting period for voting and vetoing, and a submission period for submitting the approval or disapproval if quorum was met.

### Periods

There are three distinct periods during a voting and vetoing cycle:

- The delay period
- The casting period
- The submission period

The process begins with a delay period. This period is calculated by multiplying the `delayPeriodPct` by the action's approval or queueing period. The purpose of this delay period is to provide token holders time to delegate their tokens before voting balances are checkpointed for the duration of the vote.

The casting period is when delegates vote or veto to build support for approving or disapproving an action. The period length is calculated by multiplying the `votingPeriodPct` and the action's approval or queueing period. It begins at the end of the delay period.

The submission period is when the approval or disapproval can be submitted to the instance's `LlamaCore` contract if consensus was reached. It is the remaining amount of time left in the approval or queuing period after the delay and casting period. It begins at the end of the casting period.

### Casting Votes and Vetoes

During the casting period, token voters can cast a `For`, `Against`, or `Abstain` vote. At the conclusion of the period, the approval or disapproval can be submitted if the total number of `For` votes is greater than `Against` votes and the number of `For` votes as a fraction of the token's total supply is greater than or equal to the quorum percentage.

This same logic applies for casting vetoes. The only difference is that this process occurs during the queuing period of the action and results in casting a disapproval.

The `castVote` and `castVeto` functions require the following parameters:

```solidity
uint8 role,
ActionInfo actionInfo,
uint8 support,
string reason
```

- **Role:** This parameter specifies the role of the token governor.
- **ActionInfo:** This struct contains all the necessary information about the action on which the vote or veto is being cast, including the action ID, creator, strategy, target, value, and data.
- **Support:** Indicates the token holder's stance on the action. The values can be:
  - 0 for Against
  - 1 for For
  - 2 for Abstain
- **Reason:** A human-readable string providing the rationale behind the token holder's vote or veto.

The function returns the weight of the cast, representing the influence of the token holder's vote or veto based on their voting balance.

### Reaching Quorum

Quorum is calculated using the amount of `For` votes. `Abstain` votes do not count towards the quorum.

The vote or veto has passed when the quorum is met, and the `For` votes are greater than the `Against` votes.

### Submitting Results

Once the casting period is over, the result can be submitted if the vote or veto has passed.

If the vote or veto has not passed, no action needs to be taken.

If the vote or veto has passed, anyone can call the public `submitApproval` function for a vote and the `submitDisapproval` function for a veto. The submit functions must be called before the end of the submission period, otherwise they expire.

## Token Adapter

The module's token adapter contract is referenced by the `LlamaTokenGovernor` to retrieve past voting balances and total supply. The adapter is coded to the `ILlamaTokenAdapter` interface to provide a standardized way to interact with governance token contracts.

We've implemented `LlamaTokenAdapterVotesTimestamp` which is a token adapter for tokens that implement the [IVotes interface](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol) and checkpoint supply using `block.timestamp`.

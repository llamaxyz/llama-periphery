# Llama Token Governor

`LlamaTokenGovernor` is the contract that enables token holders to create actions and cast votes/vetoes.

Llama Token Voting works by issuing a Llama policy to the `LlamaTokenGovernor` contract, which can hold roles and permissions that enable the contract to cast approvals/disapprovals and create actions. The Governor contract exposes this policyholder functionality via public functions to token holders.

## Voting Periods

There are three distinct periods during a voting cycle:

- The delay period
- The casting period
- The submission period

Llama Token Voting process begins with a delay period. This period is calculated by multiplying the `delayPeriodPct` by the action's approval or disapproval period. The purpose of the delay period is to provide token holders a window to delegate their tokens before voting balances are crystallized for the duration of the vote.

The casting period is when token holders vote/veto a pending action. It is calculated as the product of the `votingPeriodPct` and the action's approval or disapproval period. It automatically begins at the end of the delay period.

Finally, the submission period is when the result is submitted to the instance's `LlamaCore` contract if consensus is reached. It is calculated by subtract the `delayPeriodPct` and `votingPeriodPct` from `ONE_HUNDRED_IN_BPS`. It automatically begins at the end of the casting period.

## Casting Votes/Vetoes

The `LlamaTokenGovernor` contract allows token holders to participate in the governance process by casting votes/vetoes on actions. This functionality is crucial for the decentralized decision-making process, ensuring that the actions reflect the collective will of the token holders.

### Delay Period

The Llama Token Voting process begins with a delay period. This period is calculated by multiplying the `delayPeriodPct` by the action's approval or disapproval period. The purpose of the delay period is to provide token holders a window to delegate their tokens before voting balances are crystallized for the duration of the token vote.

This checkpoint occurs at the conclusion of the delay period, so any token transfers or delegation updates after the checkpoint will have no affect on this action's token voting process.

### Casting Votes

Token holders can cast their votes during the casting period on actions created within the Llama governance system if the Governor holds the approval or force approval role for the action's strategy. The process of casting a vote involves indicating support or opposition to a particular action. The contract provides the `castVote` function, which requires the following parameters:

```solidity
    uint8 role,
    ActionInfo actionInfo,
    uint8 support,
    string reason
```

- Role: This parameter specifies the role of the token holder in the governance process. It is used to determine the permission ID of the `LlamaTokenGovernor`.
- ActionInfo: This struct contains all the necessary information about the action on which the vote is being cast, including the action ID, creator, strategy, target, value, and data.
- Support: Indicates the token holder's stance on the action. The values can be:
  - 0 for Against
  - 1 for For
  - 2 for Abstain
- Reason: A human-readable string providing the rationale behind the token holder's vote.

The function returns the weight of the cast, representing the influence of the token holder's vote based on their token balance.

### Casting Vetoes

In addition to casting votes, token holders also have the ability to cast vetoes.

The `castVeto` function is similar to castVote and requires the same parameters. The parameters have the same meaning as in the castVote function. The support parameter, in this context, indicates the token holder's stance on vetoing the action.

### Reaching Quorum and Approval

Quorum is calculated using the amount of `For` votes. `Abstain` votes do not count towards the quorum.

Approval is reached when the quorum is met, and the `For` votes surpass the `Against` votes.

### Submitting Results

Once the casting period is over, the result can be submitted.

If the action has not passed, no action needs to be taken.

If the action has passed, anyone now can call the `submitApproval` or `submitDisapproval` function depending on if the action is being voted or vetoed. The submit functions must be called before the end of the submission period, otherwise it expires.

## Creating Actions

Token holders can create actions on the Llama instance if they have a sufficient token balance.

The `creationThreshold` is the number of tokens required to create an action; it can be updated by the token governor's instance.

To create an action, a user must call the `createAction` function which has the following fields:

```solidity
    uint8 role,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes data,
    string description
```

- Role: The role that will be used to determine the permission ID of the `LlamaTokenGovernor`.
- Strategy: The strategy contract that will determine how the action is executed.
- Target: The contract called when the action is executed.
- Value: The value in wei to be sent when the action is executed.
- Data: Data to be called on the target when the action is executed.
- Description: A human readable description of the action and the changes it will enact.

Note that if the Governor itself does not have the permission to create the action on the instance's `LlamaCore`, `createAction` will fail.
  
The action creation process is the same as the core Llama system, but instead of creating actions based on the user's policy and permissions the Governor's validation check is based on if they hold enough tokens.

If unfamiliar with the canonical Llama action creation process, our the main [Llama docs](https://github.com/llamaxyz/llama/tree/main/docs) will help.

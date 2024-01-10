# Llama Token Voting Module

![Llama Token Voting Module Overview](https://github.com/llamaxyz/llama/blob/main/diagrams/llama-token-voting-module-overview.png)

The Llama token voting module includes a `LlamaTokenGovernor` and `LlamaTokenAdapter` pair that is deployed by the [token voting factory](https://github.com/llamaxyz/llama/blob/main/docs/token-voting/token-voting-factory.md).

The associated Llama instance can create a dedicated "Token Governor" role and assign it to the deployed token governor contract, so token holders can create actions and collectively cast approvals or disapprovals.

## Creating Actions

Token holders can create actions on the associated Llama instance if they have a sufficient token balance.

The `creationThreshold` is the number of tokens required to create an action. This value can be updated.

To create an action, a user must call the `createAction` function on the token governor which has the following fields:

```solidity
    uint8 role,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes data,
    string description
```

- **Role:** The role that will be used to determine the permission ID of the `LlamaTokenGovernor`.
- **Strategy:** The strategy contract that will determine how the action is executed.
- **Target:** The contract called when the action is executed.
- **Value:** The value in wei to be sent when the action is executed.
- **Data:** Call data to be used on the target when the action is executed.
- **Description:** A human readable description of the action and the changes it will enact.

Note that if the token governor does not have the permission to create the action on the instance's `LlamaCore`, `createAction` will fail.

Visit the [actions section](https://github.com/llamaxyz/llama/blob/main/docs/actions.md) in the llama docs to learn more about action creation.

## Approving and Disapproving Actions

The `LlamaTokenGovernor` contract allows token holders to collectively cast approvals and disapprovals for its instance's actions.

If the token governor has the approval role or a force approval role for an action, then during that action's approval period token holders can cast votes to determine if the token governor should cast an approval.

If the token governor has the disapproval role or a force disapproval role for an action, then during that action's queueing period token holders can cast vetoes to determine if the token governor should cast a disapproval.

The entire voting and vetoing cycles take place during the action's approval and queuing periods. This includes a delay period for delegating votes, a casting period for voting and vetoing, and a submission period for submitting the approval or disapproval if quorum was met.

### Periods

There are three distinct periods during a voting and vetoing cycle:

- The delay period
- The casting period
- The submission period

The process begins with a delay period. This period is calculated by multiplying the `delayPeriodPct` by the action's approval or queueing period. The purpose of this delay period is to provide token holders with a window to delegate their tokens before voting balances are checkpointed for the duration of the vote.

The casting period is when token holders vote or veto to build support for approving or disapproving an action. The period length is calculated by multiplying the `votingPeriodPct` and the action's approval or queueing period. It begins at the end of the delay period.

The submission period is when the approval or disapproval can be submitted to the instance's `LlamaCore` contract if consensus was reached. It is the remaining about of time left in the approval or queuing period after the delay and casting period. It begins at the end of the casting period.

### Casting Votes and Vetoes

Votes and vetoes are similar concepts. Votes are how token delegates build support to collectively approve an action and vetoes are how delegates collectively disapprove an action.

During the casting period, token voters can cast a `For`, `Against`, or `Abstain` vote or veto. At the conclusion of the period, the approval or disapproval be be submitted if the total number of `For` votes exceeds `Against` votes and the number of `For` votes as a fraction of the token's total supply is greater than or equal to the quorum percentage.

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

Approval is reached when the quorum is met, and the `For` votes surpass the `Against` votes.

### Submitting Results

Once the casting period is over, the result can be submitted.

If the action has not passed, no action needs to be taken.

If the action has passed, anyone now can call the `submitApproval` or `submitDisapproval` function depending on if the action is being voted or vetoed. The submit functions must be called before the end of the submission period, otherwise it expires.

## Token Adapter

The module's token adapter contract is referenced by the `LlamaTokenGovernor` to past voting balances and total supply. The adapter is coded to the `ILlamaTokenAdapter` interface to provide a standardized interface for interacting with token contracts.

We've implemented `LlamaTokenAdapterVotesTimestamp` which is a token adapter that works with tokens that implement the [IVotes interface](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol) and checkpoint supply using `block.timestamp`.

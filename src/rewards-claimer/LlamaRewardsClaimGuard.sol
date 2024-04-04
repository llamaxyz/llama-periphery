// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaActionGuard} from "src/interfaces/ILlamaActionGuard.sol";
import {ActionInfo} from "src/lib/Structs.sol";

/// @title Llama Rewards Claim Guard
/// @author Llama (devsdosomething@llama.xyz)
/// @notice A guard that only allows the `RewardsClaimer.claimRewards` to be delegate-called
/// @dev This guard should be used to protect the `execute` function in the `LlamaAccount` contract
contract LlamaRewardsClaimGuard is ILlamaActionGuard {
  /// @dev Thrown if the call is not authorized.
  error UnauthorizedCall(address target, bytes4 selector, bool withDelegatecall);

  /// @notice The address of the `RewardsClaimer` contract.
  address public immutable REWARDS_CLAIMER;

  /// @dev Initializes the Llama rewards claim guard.
  constructor(address rewardsClaimer) {
    REWARDS_CLAIMER = rewardsClaimer;
  }

  /// @inheritdoc ILlamaActionGuard
  function validateActionCreation(ActionInfo calldata actionInfo) external view {
    // Decode the action calldata to get the LlamaAccount execute target, call type and call data.
    (address target, bool withDelegatecall,, bytes memory data) =
      abi.decode(actionInfo.data[4:], (address, bool, uint256, bytes));
    bytes4 selector = bytes4(data);

    // Check if the target is the rewards claimer and the call type is a delegatecall.
    if (target != REWARDS_CLAIMER || !withDelegatecall) revert UnauthorizedCall(target, selector, withDelegatecall);
  }

  /// @inheritdoc ILlamaActionGuard
  function validatePreActionExecution(ActionInfo calldata actionInfo) external pure {}

  /// @inheritdoc ILlamaActionGuard
  function validatePostActionExecution(ActionInfo calldata actionInfo) external pure {}
}

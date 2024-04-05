// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {LlamaBaseAccountExtension} from "src/common/LlamaBaseAccountExtension.sol";
import {LlamaUtils} from "src/lib/LlamaUtils.sol";
import {LlamaRewardsClaimStorage} from "src/rewards-claimer/LlamaRewardsClaimStorage.sol";

/// @title Llama Rewards Claim Account Extension
/// @author Llama (devsdosomething@llama.xyz)
/// @notice An account extension that claims rewards on behalf of the Llama account.
/// @dev This contract should be delegate-called from a Llama account.
contract LlamaRewardsClaimAccountExtension is LlamaBaseAccountExtension {
  /// @dev Struct to hold target data.
  struct TargetData {
    address target; // The target contract.
    uint256 value; // The target call value.
    bytes data; // The target call data.
  }

  /// @dev The call did not succeed.
  /// @param index Index of the target data being called.
  /// @param revertData Data returned by the called function.
  error CallReverted(uint256 index, bytes revertData);

  /// @dev Thrown if the target-selector is not authorized.
  error UnauthorizedTargetSelector(address target, bytes4 selector);

  /// @notice The rewards claim storage contract.
  LlamaRewardsClaimStorage public immutable REWARDS_CLAIM_STORAGE;

  /// @dev Initializes the Llama rewards claim account extenstion.
  constructor(LlamaRewardsClaimStorage rewardsClaimStorage) {
    REWARDS_CLAIM_STORAGE = rewardsClaimStorage;
  }

  /// @notice Claims rewards from the target contracts.
  /// @param targetData The target data to claim rewards from.
  /// @return returnData The return data from the target calls.
  function claimRewards(TargetData[] memory targetData) external onlyDelegateCall returns (bytes[] memory returnData) {
    uint256 length = targetData.length;
    returnData = new bytes[](length);
    for (uint256 i = 0; i < length; LlamaUtils.uncheckedIncrement(i)) {
      address target = targetData[i].target;
      uint256 value = targetData[i].value;
      bytes memory callData = targetData[i].data;
      bytes4 selector = bytes4(callData);

      // Check if the target-selector is authorized.
      if (!REWARDS_CLAIM_STORAGE.authorizedTargetSelectors(target, selector)) {
        revert UnauthorizedTargetSelector(target, selector);
      }

      // Execute the call.
      (bool success, bytes memory result) = target.call{value: value}(callData);
      if (!success) revert CallReverted(i, result);
      returnData[i] = result;
    }
  }
}

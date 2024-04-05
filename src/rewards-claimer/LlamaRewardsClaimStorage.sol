// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {LlamaUtils} from "src/lib/LlamaUtils.sol";

/// @title Llama Rewards Claim Storage
/// @author Llama (devsdosomething@llama.xyz)
/// @notice The storage contract for the `LlamaRewardsClaimAccountExtension` contract.
/// @dev This is a separate storage contract to prevent storage collisions with the Llama account.
contract LlamaRewardsClaimStorage {
  /// @dev Struct to hold authorized target-selectors.
  struct TargetSelectorAuthorization {
    address target; // The target contract.
    bytes4 selector; // The selector of the function being called.
    bool isAuthorized; // Is the target-selector authorized.
  }

  /// @dev Only callable by a Llama instance's executor.
  error OnlyLlama();

  /// @notice Emitted when a target-selector is authorized.
  event TargetSelectorAuthorized(address indexed target, bytes4 indexed selector, bool isAuthorized);

  /// @notice The Llama instance's executor.
  address public immutable LLAMA_EXECUTOR;

  /// @notice Mapping of all authorized target-selectors.
  mapping(address target => mapping(bytes4 selector => bool isAuthorized)) public authorizedTargetSelectors;

  /// @dev Initializes the Llama rewards claim storage.
  constructor(address llamaExecutor, TargetSelectorAuthorization[] memory data) {
    LLAMA_EXECUTOR = llamaExecutor;
    _setAuthorizedTargetSelectors(data);
  }

  /// @notice Sets the authorized target-selectors.
  /// @param data The target-selectors to authorize.
  function setAuthorizedTargetSelectors(TargetSelectorAuthorization[] memory data) external {
    if (msg.sender != LLAMA_EXECUTOR) revert OnlyLlama();
    _setAuthorizedTargetSelectors(data);
  }

  /// @dev Sets the authorized target-selectors.
  function _setAuthorizedTargetSelectors(TargetSelectorAuthorization[] memory data) internal {
    uint256 length = data.length;
    for (uint256 i = 0; i < length; i = LlamaUtils.uncheckedIncrement(i)) {
      authorizedTargetSelectors[data[i].target][data[i].selector] = data[i].isAuthorized;
      emit TargetSelectorAuthorized(data[i].target, data[i].selector, data[i].isAuthorized);
    }
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ILlamaTokenAdapter
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract provides an interface for clock _tokenAdapters. Clock _tokenAdapters enable voting tokens that
/// don't use
/// timestamp-based checkpointing to work with the Llama token voting module.
interface ILlamaTokenAdapter {
  /// @notice Returns the current timepoint according to the token's clock.
  /// @return timepoint the current timepoint
  function clock() external view returns (uint48 timepoint);

  function checkIfInconsistentClock() external view;

  /// @notice Converts a timestamp to timepoint units.
  /// @param timestamp The timestamp to convert.
  /// @return timepoint the current timepoint
  function timestampToTimepoint(uint256 timestamp) external view returns (uint48 timepoint);

  function getPastVotes(address account, uint48 timepoint) external view returns (uint256);

  function getPastTotalSupply(uint48 timepoint) external view returns (uint256);
}

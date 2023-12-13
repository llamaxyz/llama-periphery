// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ILlamaTokenClockAdapter
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract provides an interface for clock adapters. Clock adapters enable voting tokens that don't use timestamp-based checkpointing to work with the Llama token voting module.
interface ILlamaTokenClockAdapter {
  /// @notice returns the most recent timepoint in the past.
  function currentTimepointMinusOne() external view returns (uint256 timepoint);
  /// @notice converts a timestamp to a timepoint units.
  /// @param timestamp The timestamp to convert.
  function timestampToTimepoint(uint256 timestamp) external view returns (uint256 timepoint);
  /// @notice returns true if the clock mode is supported.
  /// @param clockMode The clock mode to check.
  function isClockModeSupported(string memory clockMode) external pure returns (bool);
}

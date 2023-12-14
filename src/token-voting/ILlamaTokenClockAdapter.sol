// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ILlamaTokenClockAdapter
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract provides an interface for clock adapters. Clock adapters enable voting tokens that don't use
/// timestamp-based checkpointing to work with the Llama token voting module.
interface ILlamaTokenClockAdapter {
  /// @notice Returns the current timepoint according to the token's clock.
  /// @return timepoint the current timepoint
  function clock() external view returns (uint48 timepoint);

  /// @notice Machine-readable description of the clock as specified in ERC-6372.
  function CLOCK_MODE() external view returns (string memory);

  /// @notice Converts a timestamp to timepoint units.
  /// @param timestamp The timestamp to convert.
  /// @return timepoint the current timepoint
  function timestampToTimepoint(uint256 timestamp) external view returns (uint48 timepoint);

  /// @notice Returns true if the clock mode is supported and false if it is unsupported.
  /// @param clockMode The clock mode to check.
  function isClockModeSupported(string memory clockMode) external pure returns (bool);
}

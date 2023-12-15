// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ILlamaTokenAdapter
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract provides an interface for voting token adapters.
interface ILlamaTokenAdapter {
  /// @notice Returns the current timepoint according to the token's clock.
  /// @return timepoint the current timepoint
  function clock() external view returns (uint48 timepoint);

  /// @notice Reverts if the token's CLOCK_MODE changes from what's in the adapter or if the clock() function doesn't
  /// return the correct timepoint based on CLOCK_MODE.
  function checkIfInconsistentClock() external view;

  /// @notice Converts a timestamp to timepoint units.
  /// @param timestamp The timestamp to convert.
  /// @return timepoint the current timepoint
  function timestampToTimepoint(uint256 timestamp) external view returns (uint48 timepoint);

  /// @notice Get the voting balance of a token holder at a specified past timepoint.
  /// @param account The token holder's address.
  /// @param timepoint The timepoint at which to get the voting balance.
  function getPastVotes(address account, uint48 timepoint) external view returns (uint256);

  /// @notice Get the total supply of a token at a specified past timepoint.
  /// @param timepoint The timepoint at which to get the total supply.
  function getPastTotalSupply(uint48 timepoint) external view returns (uint256);
}

pragma solidity ^0.8.23;

abstract contract LlamaTokenVotingTimeManager {
  function currentTimepointMinusOne() internal view virtual returns (uint256 timepoint);
  function timestampToTimepoint(uint256 timestamp) internal view virtual returns (uint256 timepoint);
  function timepointToTimestramp(uint256 timepoint) internal view virtual returns (uint256 timestamp);
  function isClockModeSupported(string memory clockMode) internal view virtual returns (bool);
}

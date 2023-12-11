pragma solidity ^0.8.23;

import {LlamaTokenVotingTimeManager} from "src/token-voting/time/LlamaTokenVotingTimeManager.sol";

/// @title LlamaTimestampTimeManager
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract allows the token voting module to support Votes tokens that are checkpointed in timestamp.
contract LlamaTimestampTimeManager is LlamaTokenVotingTimeManager {
  /// @inheritdoc LlamaTokenVotingTimeManager
  function currentTimepointMinusOne() external view override returns (uint256 timepoint) {
    return block.timestamp - 1;
  }

  /// @inheritdoc LlamaTokenVotingTimeManager
  function timestampToTimepoint(uint256 timestamp) external pure override returns (uint256 timepoint) {
    return timestamp;
  }

  /// @inheritdoc LlamaTokenVotingTimeManager
  function isClockModeSupported(string memory clockMode) external pure override returns (bool) {
    return keccak256(abi.encodePacked(clockMode)) == keccak256(abi.encodePacked("mode=timestamp"));
  }
}

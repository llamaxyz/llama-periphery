// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IVotes} from "@openzeppelin/governance/utils/IVotes.sol";
import {IERC6372} from "@openzeppelin/interfaces/IERC6372.sol";

import {LlamaUtils} from "src/lib/LlamaUtils.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";

contract LlamaTokenAdapter is ILlamaTokenAdapter {
  /// @dev The clock was incorrectly modified.
  error ERC6372InconsistentClock();

  /// @notice The token to be used for voting.
  IVotes public token;

  string CLOCK_MODE;

  constructor(IVotes _token, string memory _clockMode) {
    token = _token;

    if (keccak256(abi.encodePacked(_clockMode)) != keccak256(abi.encodePacked(""))) {
      CLOCK_MODE = _clockMode;
    } else {
      try IERC6372(address(token)).CLOCK_MODE() returns (string memory mode) {
        CLOCK_MODE = mode;
      } catch {
        CLOCK_MODE = "mode=timestamp";
      }
    }
  }

  function clock() public view returns (uint48 timepoint) {
    try IERC6372(address(token)).clock() returns (uint48 tokenTimepoint) {
      timepoint = tokenTimepoint;
    } catch {
      timepoint = LlamaUtils.toUint48(block.timestamp);
    }
  }

  function checkIfInconsistentClock() external view {
    bool hasClockChanged = _hasClockChanged();
    bool hasClockModeChanged = _hasClockModeChanged();

    if (hasClockChanged || hasClockModeChanged) revert ERC6372InconsistentClock();
  }

  function timestampToTimepoint(uint256 timestamp) external view returns (uint48 timepoint) {
    return LlamaUtils.toUint48(timestamp);
  }

  function getPastVotes(address account, uint48 timepoint) external view returns (uint256) {
    return token.getPastVotes(account, timepoint);
  }

  function getPastTotalSupply(uint48 timepoint) external view returns (uint256) {
    return token.getPastTotalSupply(timepoint);
  }

  function _hasClockModeChanged() internal view returns (bool) {
    try IERC6372(address(token)).CLOCK_MODE() returns (string memory mode) {
      return keccak256(abi.encodePacked(mode)) != keccak256(abi.encodePacked(CLOCK_MODE));
    } catch {
      return false;
    }
  }

  function _hasClockChanged() internal view returns (bool) {
    if (keccak256(abi.encodePacked(CLOCK_MODE)) == keccak256(abi.encodePacked("mode=timestamp"))) {
      return clock() != LlamaUtils.toUint48(block.timestamp);
    } else {
      return clock() != LlamaUtils.toUint48(block.number);
    }
  }
}

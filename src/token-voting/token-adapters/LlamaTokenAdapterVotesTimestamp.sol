// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {IVotes} from "@openzeppelin/governance/utils/IVotes.sol";
import {IERC6372} from "@openzeppelin/interfaces/IERC6372.sol";

import {LlamaUtils} from "src/lib/LlamaUtils.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";

contract LlamaTokenAdapterVotesTimestamp is ILlamaTokenAdapter, Initializable {
  // =========================
  // ======== Structs ========
  // =========================

  /// @dev Llama token adapter initialization configuration.
  struct Config {
    address token; // The address of the voting token.
  }

  // ========================
  // ======== Errors ========
  // ========================

  /// @dev The clock was incorrectly modified.
  error ERC6372InconsistentClock();

  // =================================================
  // ======== Constants and Storage Variables ========
  // =================================================

  /// @notice The token to be used for voting.
  address public token;

  /// @notice Machine-readable description of the clock as specified in ERC-6372.
  string public CLOCK_MODE;

  // ================================
  // ======== Initialization ========
  // ================================

  /// @dev This contract is deployed as a minimal proxy from the factory's `deploy` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @inheritdoc ILlamaTokenAdapter
  function initialize(bytes memory config) external initializer returns (bool) {
    Config memory adapterConfig = abi.decode(config, (Config));
    token = adapterConfig.token;
    CLOCK_MODE = "mode=timestamp";

    return true;
  }

  /// @inheritdoc ILlamaTokenAdapter
  function clock() public view returns (uint48 timepoint) {
    try IERC6372(address(token)).clock() returns (uint48 tokenTimepoint) {
      timepoint = tokenTimepoint;
    } catch {
      timepoint = LlamaUtils.toUint48(block.timestamp);
    }
  }

  /// @inheritdoc ILlamaTokenAdapter
  function checkIfInconsistentClock() external view {
    bool hasClockChanged = _hasClockChanged();
    bool hasClockModeChanged = _hasClockModeChanged();

    if (hasClockChanged || hasClockModeChanged) revert ERC6372InconsistentClock();
  }

  /// @inheritdoc ILlamaTokenAdapter
  function timestampToTimepoint(uint256 timestamp) external pure returns (uint48 timepoint) {
    return LlamaUtils.toUint48(timestamp);
  }

  /// @inheritdoc ILlamaTokenAdapter
  function getPastVotes(address account, uint48 timepoint) external view returns (uint256) {
    return IVotes(token).getPastVotes(account, timepoint);
  }

  /// @inheritdoc ILlamaTokenAdapter
  function getPastTotalSupply(uint48 timepoint) external view returns (uint256) {
    return IVotes(token).getPastTotalSupply(timepoint);
  }

  function _hasClockModeChanged() internal view returns (bool) {
    try IERC6372(token).CLOCK_MODE() returns (string memory mode) {
      return keccak256(abi.encodePacked(mode)) != keccak256(abi.encodePacked(CLOCK_MODE));
    } catch {
      return false;
    }
  }

  function _hasClockChanged() internal view returns (bool) {
    return clock() != LlamaUtils.toUint48(block.timestamp);
  }
}

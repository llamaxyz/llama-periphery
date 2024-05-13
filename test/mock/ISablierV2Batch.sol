// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";

/// @notice Struct encapsulating the broker parameters passed to the create functions. Both can be set to zero.
/// @param account The address receiving the broker's fee.
/// @param fee The broker's percentage fee from the total amount, denoted as a fixed-point number where 1e18 is 100%.
struct Broker {
  address account;
  UD60x18 fee;
}

/// @notice Struct encapsulating the cliff duration and the total duration.
/// @param cliff The cliff duration in seconds.
/// @param total The total duration in seconds.
struct Durations {
  uint40 cliff;
  uint40 total;
}

/// @notice A struct encapsulating all parameters of {SablierV2LockupLinear.createWithDurations} except for the
/// asset.
struct CreateWithDurations {
  address sender;
  address recipient;
  uint128 totalAmount;
  bool cancelable;
  bool transferable;
  Durations durations;
  Broker broker;
}

/// @title ISablierV2Batch
/// @notice Helper to batch create Sablier V2 Lockup streams.
interface ISablierV2Batch {
  /*//////////////////////////////////////////////////////////////////////////
                              SABLIER-V2-LOCKUP-LINEAR
    //////////////////////////////////////////////////////////////////////////*/

  /// @notice Creates a batch of Lockup Linear streams using `createWithDurations`.
  ///
  /// @dev Requirements:
  /// - There must be at least one element in `batch`.
  /// - All requirements from {ISablierV2LockupLinear.createWithDurations} must be met for each stream.
  ///
  /// @param lockupLinear The address of the {SablierV2LockupLinear} contract.
  /// @param asset The contract address of the ERC-20 asset used for streaming.
  /// @param batch An array of structs, each encapsulating a subset of the parameters of
  /// {SablierV2LockupLinear.createWithDurations}.
  /// @return streamIds The ids of the newly created streams.
  function createWithDurations(address lockupLinear, IERC20 asset, CreateWithDurations[] calldata batch)
    external
    returns (uint256[] memory streamIds);
}

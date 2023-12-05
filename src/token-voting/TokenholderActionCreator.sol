// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";

/// @title TokenholderActionCreator
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance token create actions if they have
/// sufficient token balance.
/// @dev This contract is deployed by `LlamaTokenVotingFactory`. Anyone can deploy this contract using the factory, but
/// it must hold a Policy from the specified `LlamaCore` instance to actually be able to create an action. The
/// instance's policy encodes what actions this contract is allowed to create, and attempting to create an action that
/// is not allowed by the policy will result in a revert.
abstract contract TokenholderActionCreator {
  /// @notice The core contract for this Llama instance.
  ILlamaCore public immutable LLAMA_CORE;

  /// @notice The address of the tokenholder that created the action.
  mapping(uint256 => address) public actionCreators;

  /// @notice The default number of tokens required to create an action.
  uint256 public creationThreshold;

  /// @dev Emitted when an action is canceled.
  event ActionCanceled(uint256 id, address indexed creator);

  /// @dev Emitted when an action is created.
  /// @dev This is the same as the `ActionCreated` event from `LlamaCore`. The two events will be
  /// nearly identical, with the `creator` being the only difference. This version will emit the
  /// address of the tokenholder that created the action, while the `LlamaCore` version will emit
  /// the address of this contract as the action creator.
  event ActionCreated(
    uint256 id,
    address indexed creator,
    uint8 role,
    ILlamaStrategy indexed strategy,
    address indexed target,
    uint256 value,
    bytes data,
    string description
  );

  /// @dev Emitted when the default number of tokens required to create an action is changed.
  event ActionThresholdSet(uint256 newThreshold);

  /// @dev Thrown when a user tries to create an action but the clock mode is not supported.
  error ClockModeNotSupported(string clockMode);

  /// @dev Thrown when a user tries to create an action but does not have enough tokens.
  error InsufficientBalance(uint256 balance);

  /// @dev Thrown when an invalid `llamaCore` address is passed to the constructor.
  error InvalidLlamaCoreAddress();

  /// @dev Thrown when an invalid `token` address is passed to the constructor.
  error InvalidTokenAddress();

  /// @dev Thrown when an invalid `creationThreshold` is passed to the constructor.
  error InvalidCreationThreshold();

  /// @dev Thrown when a user tries to cancel an action but they are not the action creator.
  error OnlyActionCreator();

  /// @dev Thrown when an address other than the `LlamaExecutor` tries to call a function.
  error OnlyLlamaExecutor();

  /// @param llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _creationThreshold The default number of tokens required to create an action. This must
  /// be in the same decimals as the token. For example, if the token has 18 decimals and you want a
  /// creation threshold of 1000 tokens, pass in 1000e18.
  constructor(ILlamaCore llamaCore, uint256 _creationThreshold) {
    if (llamaCore.actionsCount() < 0) revert InvalidLlamaCoreAddress();

    LLAMA_CORE = llamaCore;
    _setActionThreshold(_creationThreshold);
  }

  /// @notice Creates an action.
  /// @dev Use `""` for `description` if there is no description.
  /// @param role The role that will be used to determine the permission ID of the policyholder.
  /// @param strategy The strategy contract that will determine how the action is executed.
  /// @param target The contract called when the action is executed.
  /// @param value The value in wei to be sent when the action is executed.
  /// @param data Data to be called on the target when the action is executed.
  /// @param description A human readable description of the action and the changes it will enact.
  /// @return actionId Action ID of the newly created action.
  function createAction(
    uint8 role,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string memory description
  ) external returns (uint256 actionId) {
    /// @dev only timestamp mode is supported for now
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    uint256 balance = _getPastVotes(msg.sender, block.timestamp - 1);
    if (balance < creationThreshold) revert InsufficientBalance(balance);

    actionCreators[actionId] = msg.sender;

    actionId = LLAMA_CORE.createAction(role, strategy, target, value, data, description);
    emit ActionCreated(actionId, msg.sender, role, strategy, target, value, data, description);
  }

  /// @notice Cancels an action.
  /// @param actionInfo The action to cancel.
  /// @dev Relies on the validation checks in `LlamaCore.cancelAction()`.
  function cancelAction(ActionInfo calldata actionInfo) external {
    if (msg.sender != actionCreators[actionInfo.id]) revert OnlyActionCreator();
    LLAMA_CORE.cancelAction(actionInfo);
    emit ActionCanceled(actionInfo.id, msg.sender);
  }

  /// @notice Sets the default number of tokens required to create an action.
  /// @param _creationThreshold The number of tokens required to create an action.
  /// @dev This must be in the same decimals as the token.
  function setActionThreshold(uint256 _creationThreshold) external {
    if (msg.sender != address(LLAMA_CORE.executor())) revert OnlyLlamaExecutor();
    if (_creationThreshold > _getPastTotalSupply(block.timestamp - 1)) revert InvalidCreationThreshold();
    _setActionThreshold(_creationThreshold);
  }

  function _setActionThreshold(uint256 _creationThreshold) internal {
    creationThreshold = _creationThreshold;
    emit ActionThresholdSet(_creationThreshold);
  }

  function _getPastVotes(address account, uint256 timestamp) internal view virtual returns (uint256) {}
  function _getPastTotalSupply(uint256 timestamp) internal view virtual returns (uint256) {}
  function _getClockMode() internal view virtual returns (string memory) {}
}

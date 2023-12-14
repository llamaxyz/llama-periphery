// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ILlamaTokenClockAdapter} from "src/token-voting/ILlamaTokenClockAdapter.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {LlamaUtils} from "src/lib/LlamaUtils.sol";

/// @title LlamaTokenActionCreator
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance token create actions if they have
/// sufficient token balance.
/// @dev This contract is deployed by `LlamaTokenVotingFactory`. Anyone can deploy this contract using the factory, but
/// it must hold a Policy from the specified `LlamaCore` instance to actually be able to create an action. The
/// instance's policy encodes what actions this contract is allowed to create, and attempting to create an action that
/// is not allowed by the policy will result in a revert.
abstract contract LlamaTokenActionCreator is Initializable {
  // ========================
  // ======== Errors ========
  // ========================

  /// @dev Thrown when a user tries to create an action but the clock mode is not supported.
  error ClockModeNotSupported(string clockMode);

  /// @dev Thrown when a user tries to create an action but does not have enough tokens.
  error InsufficientBalance(uint256 balance);

  /// @dev Thrown when an invalid `llamaCore` address is passed to the constructor.
  error InvalidLlamaCoreAddress();

  /// @dev The recovered signer does not match the expected token holder.
  error InvalidSignature();

  /// @dev Thrown when an invalid `token` address is passed to the constructor.
  error InvalidTokenAddress();

  /// @dev Thrown when an invalid `creationThreshold` is passed to the constructor.
  error InvalidCreationThreshold();

  /// @dev Thrown when a user tries to cancel an action but they are not the action creator.
  error OnlyActionCreator();

  /// @dev Thrown when an address other than the `LlamaExecutor` tries to call a function.
  error OnlyLlamaExecutor();

  /// @dev Thrown when an invalid `role` is passed to the constructor.
  error RoleNotInitialized(uint8 role);

  // ========================
  // ======== Events ========
  // ========================

  /// @dev Emitted when an action is created.
  event ActionCreated(uint256 id, address indexed creator);

  /// @dev Emitted when an action is canceled.
  event ActionCanceled(uint256 id, address indexed creator);

  /// @dev Emitted when the default number of tokens required to create an action is changed.
  event ActionThresholdSet(uint256 newThreshold);

  // =================================================
  // ======== Constants and Storage Variables ========
  // =================================================

  /// @dev EIP-712 base typehash.
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @dev EIP-712 createAction typehash.
  bytes32 internal constant CREATE_ACTION_TYPEHASH = keccak256(
    "CreateAction(address tokenHolder,address strategy,address target,uint256 value,bytes data,string description,uint256 nonce)"
  );

  /// @dev EIP-712 cancelAction typehash.
  bytes32 internal constant CANCEL_ACTION_TYPEHASH = keccak256(
    "CancelAction(address tokenHolder,ActionInfo actionInfo,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev EIP-712 actionInfo typehash.
  bytes32 internal constant ACTION_INFO_TYPEHASH = keccak256(
    "ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice The core contract for this Llama instance.
  ILlamaCore public llamaCore;

  /// @notice The contract that manages the timepoints for this token voting module.
  ILlamaTokenClockAdapter public clockAdapter;

  /// @notice The default number of tokens required to create an action.
  uint256 public creationThreshold;

  /// @notice The role used by this contract to cast approvals and disapprovals.
  /// @dev This role is expected to have the permissions to create appropriate actions.
  uint8 public role;

  /// @notice The address of the tokenholder that created the action.
  mapping(uint256 => address) public actionCreators;

  /// @notice Mapping of token holder to function selectors to current nonces for EIP-712 signatures.
  /// @dev This is used to prevent replay attacks by incrementing the nonce for each operation (`createAction`,
  /// `cancelAction`, `castApproval` and `castDisapproval`) signed by the token holder.
  mapping(address tokenHolder => mapping(bytes4 selector => uint256 currentNonce)) public nonces;

  // ================================
  // ======== Initialization ========
  // ================================

  /// @dev This will be called by the `initialize` of the inheriting contract.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _creationThreshold The default number of tokens required to create an action. This must
  /// be in the same decimals as the token. For example, if the token has 18 decimals and you want a
  /// creation threshold of 1000 tokens, pass in 1000e18.
  function __initializeLlamaTokenActionCreatorMinimalProxy(
    ILlamaCore _llamaCore,
    ILlamaTokenClockAdapter _clockAdapter,
    uint8 _role,
    uint256 _creationThreshold
  ) internal {
    if (_llamaCore.actionsCount() < 0) revert InvalidLlamaCoreAddress();
    if (_role > _llamaCore.policy().numRoles()) revert RoleNotInitialized(_role);

    llamaCore = _llamaCore;
    clockAdapter = _clockAdapter;
    role = _role;
    _setActionThreshold(_creationThreshold);
  }

  // ===========================================
  // ======== External and Public Logic ========
  // ===========================================

  // -------- Action Lifecycle Management --------

  /// @notice Creates an action.
  /// @dev Use `""` for `description` if there is no description.
  /// @param strategy The strategy contract that will determine how the action is executed.
  /// @param target The contract called when the action is executed.
  /// @param value The value in wei to be sent when the action is executed.
  /// @param data Data to be called on the target when the action is executed.
  /// @param description A human readable description of the action and the changes it will enact.
  /// @return actionId Action ID of the newly created action.
  function createAction(
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string memory description
  ) external returns (uint256 actionId) {
    return _createAction(msg.sender, strategy, target, value, data, description);
  }

  /// @notice Creates an action via an off-chain signature. The creator needs to have sufficient token balance that is
  /// greater than or equal to the creation threshold.
  /// @dev Use `""` for `description` if there is no description.
  /// @param tokenHolder The tokenHolder that signed the message.
  /// @param strategy The strategy contract that will determine how the action is executed.
  /// @param target The contract called when the action is executed.
  /// @param value The value in wei to be sent when the action is executed.
  /// @param data Data to be called on the target when the action is executed.
  /// @param description A human readable description of the action and the changes it will enact.
  /// @param v ECDSA signature component: Parity of the `y` coordinate of point `R`
  /// @param r ECDSA signature component: x-coordinate of `R`
  /// @param s ECDSA signature component: `s` value of the signature
  /// @return actionId Action ID of the newly created action.
  function createActionBySig(
    address tokenHolder,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string memory description,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint256 actionId) {
    bytes32 digest = _getCreateActionTypedDataHash(tokenHolder, strategy, target, value, data, description);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != tokenHolder) revert InvalidSignature();
    actionId = _createAction(signer, strategy, target, value, data, description);
  }

  /// @notice Cancels an action.
  /// @param actionInfo The action to cancel.
  /// @dev Relies on the validation checks in `LlamaCore.cancelAction()`.
  function cancelAction(ActionInfo calldata actionInfo) external {
    _cancelAction(msg.sender, actionInfo);
  }

  /// @notice Cancels an action by its `actionInfo` struct via an off-chain signature.
  /// @dev Rules for cancelation are defined by the strategy.
  /// @param policyholder The policyholder that signed the message.
  /// @param actionInfo Data required to create an action.
  /// @param v ECDSA signature component: Parity of the `y` coordinate of point `R`
  /// @param r ECDSA signature component: x-coordinate of `R`
  /// @param s ECDSA signature component: `s` value of the signature
  function cancelActionBySig(address policyholder, ActionInfo calldata actionInfo, uint8 v, bytes32 r, bytes32 s)
    external
  {
    bytes32 digest = _getCancelActionTypedDataHash(policyholder, actionInfo);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != policyholder) revert InvalidSignature();
    _cancelAction(signer, actionInfo);
  }

  // -------- Instance Management --------

  /// @notice Sets the default number of tokens required to create an action.
  /// @param _creationThreshold The number of tokens required to create an action.
  /// @dev This must be in the same decimals as the token.
  function setActionThreshold(uint256 _creationThreshold) external {
    if (msg.sender != address(llamaCore.executor())) revert OnlyLlamaExecutor();
    if (_creationThreshold > _getPastTotalSupply(_currentTimepointMinusOne())) revert InvalidCreationThreshold();
    _setActionThreshold(_creationThreshold);
  }

  // -------- User Nonce Management --------

  /// @notice Increments the caller's nonce for the given `selector`. This is useful for revoking
  /// signatures that have not been used yet.
  /// @param selector The function selector to increment the nonce for.
  function incrementNonce(bytes4 selector) external {
    // Safety: Can never overflow a uint256 by incrementing.
    nonces[msg.sender][selector] = LlamaUtils.uncheckedIncrement(nonces[msg.sender][selector]);
  }

  // ================================
  // ======== Internal Logic ========
  // ================================

  /// @dev Creates an action. The creator needs to have sufficient token balance.
  function _createAction(
    address tokenHolder,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string memory description
  ) internal returns (uint256 actionId) {
    /// @dev only timestamp mode is supported for now
    _isClockModeSupported(); // reverts if clock mode is not supported

    uint256 balance = _getPastVotes(tokenHolder, _currentTimepointMinusOne());
    if (balance < creationThreshold) revert InsufficientBalance(balance);

    actionId = llamaCore.createAction(role, strategy, target, value, data, description);
    actionCreators[actionId] = tokenHolder;
    emit ActionCreated(actionId, tokenHolder);
  }

  /// @dev Cancels an action by its `actionInfo` struct. Only the action creator can cancel.
  function _cancelAction(address creator, ActionInfo calldata actionInfo) internal {
    if (creator != actionCreators[actionInfo.id]) revert OnlyActionCreator();
    llamaCore.cancelAction(actionInfo);
    emit ActionCanceled(actionInfo.id, creator);
  }

  /// @dev Sets the default number of tokens required to create an action.
  function _setActionThreshold(uint256 _creationThreshold) internal {
    creationThreshold = _creationThreshold;
    emit ActionThresholdSet(_creationThreshold);
  }

  ///@dev Reverts if the clock mode is not supported.
  function _isClockModeSupported() internal view {
    if (!_isClockModeTimestamp()) {
      string memory clockMode = _getClockMode();
      bool supported = clockAdapter.isClockModeSupported(clockMode);
      if (!supported) revert ClockModeNotSupported(clockMode);
    }
  }

  /// @dev Returns the current timepoint minus one.
  function _currentTimepointMinusOne() internal view returns (uint48) {
    if (_isClockModeTimestamp()) return LlamaUtils.toUint48(block.timestamp - 1);
    return clockAdapter.clock() - 1;
  }

  // Returns true if the clock mode is timestamp
  function _isClockModeTimestamp() internal view returns (bool) {
    string memory clockMode = _getClockMode();
    return keccak256(abi.encodePacked(clockMode)) == keccak256(abi.encodePacked("mode=timestamp"));
  }

  /// @dev Returns the number of votes for a given token holder at a given timestamp.
  function _getPastVotes(address account, uint48 timepoint) internal view virtual returns (uint256) {}

  /// @dev Returns the total supply of the token at a given timestamp.
  function _getPastTotalSupply(uint48 timepoint) internal view virtual returns (uint256) {}

  /// @dev Returns the clock mode of the token (https://eips.ethereum.org/EIPS/eip-6372).
  function _getClockMode() internal view virtual returns (string memory) {}

  /// @dev Returns the current nonce for a given tokenHolder and selector, and increments it. Used to prevent
  /// replay attacks.
  function _useNonce(address tokenHolder, bytes4 selector) internal returns (uint256 nonce) {
    nonce = nonces[tokenHolder][selector];
    nonces[tokenHolder][selector] = LlamaUtils.uncheckedIncrement(nonce);
  }

  // -------- EIP-712 Getters --------

  /// @dev Returns the EIP-712 domain separator.
  function _getDomainHash() internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        EIP712_DOMAIN_TYPEHASH, keccak256(bytes(llamaCore.name())), keccak256(bytes("1")), block.chainid, address(this)
      )
    );
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CreateAction` domain, which can be used to
  /// recover the signer.
  function _getCreateActionTypedDataHash(
    address tokenHolder,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string memory description
  ) internal returns (bytes32) {
    // Calculating and storing nonce in memory and using that below, instead of calculating in place to prevent stack
    // too deep error.
    uint256 nonce = _useNonce(tokenHolder, msg.sig);

    bytes32 createActionHash = keccak256(
      abi.encode(
        CREATE_ACTION_TYPEHASH,
        tokenHolder,
        address(strategy),
        target,
        value,
        keccak256(data),
        keccak256(bytes(description)),
        nonce
      )
    );

    return keccak256(abi.encodePacked("\x19\x01", _getDomainHash(), createActionHash));
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CancelAction` domain, which can be used to
  /// recover the signer.
  function _getCancelActionTypedDataHash(address tokenHolder, ActionInfo calldata actionInfo)
    internal
    returns (bytes32)
  {
    bytes32 cancelActionHash = keccak256(
      abi.encode(CANCEL_ACTION_TYPEHASH, tokenHolder, _getActionInfoHash(actionInfo), _useNonce(tokenHolder, msg.sig))
    );

    return keccak256(abi.encodePacked("\x19\x01", _getDomainHash(), cancelActionHash));
  }

  /// @dev Returns the hash of `actionInfo`.
  function _getActionInfoHash(ActionInfo calldata actionInfo) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_INFO_TYPEHASH,
        actionInfo.id,
        actionInfo.creator,
        actionInfo.creatorRole,
        address(actionInfo.strategy),
        actionInfo.target,
        actionInfo.value,
        keccak256(actionInfo.data)
      )
    );
  }
}

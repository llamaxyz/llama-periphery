// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {LlamaUtils} from "src/lib/LlamaUtils.sol";

/// @title TokenholderActionCreator
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance token create actions if they have
/// sufficient token balance.
/// @dev This contract can be deployed by anyone, but to actually be able to create an action it
/// will need to hold a Policy from the specified `LlamaCore` instance. That policy encodes what
/// actions this contract is allowed to create, and attempting to create an action that is not
/// allowed by the policy will result in a revert.
abstract contract TokenholderActionCreator {
  /// @notice The core contract for this Llama instance.
  ILlamaCore public immutable LLAMA_CORE;

  /// @dev EIP-712 actionInfo typehash.
  bytes32 internal constant ACTION_INFO_TYPEHASH = keccak256(
    "ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev EIP-712 cancelAction typehash.
  bytes32 internal constant CANCEL_ACTION_TYPEHASH = keccak256(
    "CancelAction(address tokenHolder,ActionInfo actionInfo,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev EIP-712 createAction typehash.
  bytes32 internal constant CREATE_ACTION_TYPEHASH = keccak256(
    "CreateAction(address tokenHolder,uint8 role,address strategy,address target,uint256 value,bytes data,string description,uint256 nonce)"
  );

  /// @dev EIP-712 base typehash.
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @notice The address of the tokenholder that created the action.
  mapping(uint256 => address) public actionCreators;

  /// @notice Mapping of token holder to function selectors to current nonces for EIP-712 signatures.
  /// @dev This is used to prevent replay attacks by incrementing the nonce for each operation (`createAction`,
  /// `cancelAction`, `castApproval` and `castDisapproval`) signed by the token holder.
  mapping(address tokenHolder => mapping(bytes4 selector => uint256 currentNonce)) public nonces;

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
    return _createAction(msg.sender, role, strategy, target, value, data, description);
  }

  /// @notice Creates an action via an off-chain signature. The creator needs to hold a policy with the permission ID
  /// of the provided `(target, selector, strategy)`.
  /// @dev Use `""` for `description` if there is no description.
  /// @param tokenHolder The tokenHolder that signed the message.
  /// @param role The role that will be used to determine the permission ID of the tokenHolder.
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
    uint8 role,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string memory description,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint256 actionId) {
    bytes32 digest = _getCreateActionTypedDataHash(tokenHolder, role, strategy, target, value, data, description);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != tokenHolder) revert InvalidSignature();
    actionId = _createAction(signer, role, strategy, target, value, data, description);
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

  /// @notice Sets the default number of tokens required to create an action.
  /// @param _creationThreshold The number of tokens required to create an action.
  /// @dev This must be in the same decimals as the token.
  function setActionThreshold(uint256 _creationThreshold) external {
    if (msg.sender != address(LLAMA_CORE.executor())) revert OnlyLlamaExecutor();
    if (_creationThreshold > _getPastTotalSupply(block.timestamp - 1)) revert InvalidCreationThreshold();
    _setActionThreshold(_creationThreshold);
  }

  /// @notice Increments the caller's nonce for the given `selector`. This is useful for revoking
  /// signatures that have not been used yet.
  /// @param selector The function selector to increment the nonce for.
  function incrementNonce(bytes4 selector) external {
    // Safety: Can never overflow a uint256 by incrementing.
    nonces[msg.sender][selector] = LlamaUtils.uncheckedIncrement(nonces[msg.sender][selector]);
  }

  function _createAction(
    address tokenHolder,
    uint8 role,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string memory description
  ) internal returns (uint256 actionId) {
    /// @dev only timestamp mode is supported for now
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    uint256 balance = _getPastVotes(tokenHolder, block.timestamp - 1);
    if (balance < creationThreshold) revert InsufficientBalance(balance);

    actionCreators[actionId] = tokenHolder;

    actionId = LLAMA_CORE.createAction(role, strategy, target, value, data, description);
    emit ActionCreated(actionId, tokenHolder, role, strategy, target, value, data, description);
  }

  function _setActionThreshold(uint256 _creationThreshold) internal {
    creationThreshold = _creationThreshold;
    emit ActionThresholdSet(_creationThreshold);
  }

  function _cancelAction(address creator, ActionInfo calldata actionInfo) internal {
    if (creator != actionCreators[actionInfo.id]) revert OnlyActionCreator();
    LLAMA_CORE.cancelAction(actionInfo);
    emit ActionCanceled(actionInfo.id, creator);
  }

  function _getPastVotes(address account, uint256 timestamp) internal view virtual returns (uint256) {}
  function _getPastTotalSupply(uint256 timestamp) internal view virtual returns (uint256) {}
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
        EIP712_DOMAIN_TYPEHASH, keccak256(bytes(LLAMA_CORE.name())), keccak256(bytes("1")), block.chainid, address(this)
      )
    );
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CreateAction` domain, which can be used to
  /// recover the signer.
  function _getCreateActionTypedDataHash(
    address tokenHolder,
    uint8 role,
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
        role,
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

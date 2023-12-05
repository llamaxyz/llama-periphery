// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ActionState} from "src/lib/Enums.sol";
import {LlamaUtils} from "src/lib/LlamaUtils.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {ILlamaRelativeStrategyBase} from "src/interfaces/ILlamaRelativeStrategyBase.sol";

/// @title TokenholderCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance token cast approvals and disapprovals
/// on created actions.
/// @dev This contract can be deployed by anyone, but to actually be able to cast on an action it
/// will need to hold the appropriate Policy from the specified `LlamaCore` instance. This contract
/// does not verify that it holds the correct policy when voting, and relies on `LlamaCore` to
/// verify that during submission.
abstract contract TokenholderCaster {
  // =========================
  // ======== Structs ========
  // =========================

  /// @dev Cast counts and submission data.
  struct CastData {
    uint96 approvalsFor; // Number of approvals casted for this action. This is the standard approval in `LlamaCore`.
    uint96 approvalsAbstain; // Number of abstentions casted for this action. This does not exist in `LlamaCore`.
    uint96 approvalsAgainst; // Number of approvals casted against this action. This does not exist in `LlamaCore`.
    bool approvalSubmitted; // True if the approvals have been submitted to `LlamaCore, false otherwise.
    uint96 disapprovalsFor; // Number of disapprovals casted for this action. This is the standard disapproval in
      // `LlamaCore`.
    uint96 disapprovalsAbstain; // Number of abstentions casted for this action. This does not exist in `LlamaCore`.
    uint96 disapprovalsAgainst; // Number of disapprovals casted against this action. This does not exist in
      // `LlamaCore`.
    bool disapprovalSubmitted; // True if the disapprovals have been submitted to `LlamaCore`, false otherwise.
    mapping(address tokenholder => bool) castApproval; // True if tokenholder casted approval, false otherwise.
    mapping(address tokenholder => bool) castDisapproval; // True if tokenholder casted disapproval, false otherwise.
  }

  // ========================
  // ======== Errors ========
  // ========================

  /// @dev Thrown when a user tries to cast approval but the action has expired.
  error ActionExpired();

  /// @dev Thrown when a user tries to cast approval but the action is not active.
  error ActionNotActive();

  /// @dev Thrown when a user tries to cast disapproval but but the action is not approved.
  error ActionNotApproved();

  /// @dev Thrown when a user tries to cast approval but has already casted.
  error AlreadyCastApproval();

  /// @dev Thrown when a user tries to cast approval but the casts have already been submitted to `LlamaCore`.
  error AlreadySubmittedApproval();

  /// @dev Thrown when a user tries to cast disapproval but has already casted.
  error AlreadyCastDisapproval();

  /// @dev Thrown when a user tries to cast disapproval but the casts have already been submitted to `LlamaCore.
  error AlreadySubmittedDisapproval();

  /// @dev Thrown when a user tries to cast (dis)approval but the casting period has ended.
  error CastingPeriodOver();

  /// @dev Thrown when a user tries to cast (dis)approval but the action cannot be submitted yet.
  error CantSubmitYet();

  /// @dev Thrown when a user tries to create an action but the clock mode is not supported.
  error ClockModeNotSupported(string clockMode);

  /// @dev Thrown when a user tries to cast (dis)approval but the (dis)approvals surpass the approvals.
  error ForDoesNotSurpassAgainst(uint256 approvals, uint256 disapprovals);

  /// @dev Thrown when a user tries to submit approvals but there are not enough approvals.
  error InsufficientApprovals(uint256 approvals, uint256 threshold);

  /// @dev Thrown when a user tries to cast but does not have enough tokens.
  error InsufficientBalance(uint256 balance);

  /// @dev Thrown when an invalid `approvalThreshold` is passed to the constructor.
  error InvalidMinApprovalPct(uint256 approvalThreshold);

  /// @dev Thrown when an invalid `disapprovalThreshold` is passed to the constructor.
  error InvalidMinDisapprovalPct(uint256 disapprovalThreshold);

  /// @dev Thrown when an invalid `llamaCore` address is passed to the constructor.
  error InvalidLlamaCoreAddress();

  /// @dev The recovered signer does not match the expected tokenholder.
  error InvalidSignature();

  /// @dev Thrown when an invalid `token` address is passed to the constructor.
  error InvalidTokenAddress();

  /// @dev Thrown when an invalid `support` value is used when casting.
  error InvalidSupport(uint8 support);

  /// @dev Thrown when an invalid `role` is passed to the constructor.
  error RoleNotInitialized(uint8 role);

  /// @dev Thrown when a user tries to submit (dis)approval but the submission period has ended.
  error SubmissionPeriodOver();

  // ========================
  // ======== Events ========
  // ========================

  /// @dev Emitted when an approval is cast.
  /// @dev This is almost the same as the `ApprovalCast` event from `LlamaCore`, with the addition of the support field.
  /// The two events will be nearly identical, with the `tokenholder` being the main difference. This version will emit
  /// the address of the tokenholder that casted, while the `LlamaCore` version will emit the address of this contract
  /// as the action creator. Additionally, there is no `role` emitted here as all tokenholders are eligible to vote.
  event ApprovalCast(
    uint256 id, address indexed tokenholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  /// @dev Emitted when cast approvals are submitted to the `LlamaCore` contract.
  event ApprovalsSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  /// @dev Emitted when a disapproval is cast.
  /// @dev This is the same as the `DisapprovalCast` event from `LlamaCore`. The two events will be
  /// nearly identical, with the `tokenholder` being the only difference. This version will emit
  /// the address of the tokenholder that casted, while the `LlamaCore` version will emit the
  /// address of this contract as the action creator.
  event DisapprovalCast(
    uint256 id, address indexed tokenholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  /// @dev Emitted when cast approvals are submitted to the `LlamaCore` contract.
  event DisapprovalsSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);
  // =================================================
  // ======== Constants and Storage Variables ========
  // =================================================

  /// @dev Equivalent to 100%, but in basis points.
  uint256 internal constant ONE_HUNDRED_IN_BPS = 10_000;

  uint256 internal constant ONE_THIRD_IN_BPS = 3333;
  uint256 internal constant TWO_THIRDS_IN_BPS = 6667;

  /// @notice The core contract for this Llama instance.
  ILlamaCore public immutable LLAMA_CORE;

  /// @notice The minimum % of approvals required to submit approvals to `LlamaCore`.
  uint256 public immutable MIN_APPROVAL_PCT;

  /// @notice The minimum % of disapprovals required to submit disapprovals to `LlamaCore`.
  uint256 public immutable MIN_DISAPPROVAL_PCT;

  /// @notice The role used by this contract to cast approvals and disapprovals.
  /// @dev This role is expected to have the ability to force approve and disapprove actions.
  uint8 public immutable ROLE;

  /// @dev EIP-712 base typehash.
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @notice EIP-712 castApproval typehash.
  bytes32 internal constant CAST_APPROVAL_BY_SIG_TYPEHASH = keccak256(
    "CastApproval(address tokenHolder,uint8 support,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice EIP-712 castDisapproval typehash.
  bytes32 internal constant CAST_DISAPPROVAL_BY_SIG_TYPEHASH = keccak256(
    "CastDisapproval(address tokenHolder,uint8 role,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev EIP-712 actionInfo typehash.
  bytes32 internal constant ACTION_INFO_TYPEHASH = keccak256(
    "ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice Mapping from action ID to the status of existing casts.
  mapping(uint256 actionId => CastData) public casts;

  /// @notice Mapping of tokenholders to function selectors to current nonces for EIP-712 signatures.
  /// @dev This is used to prevent replay attacks by incrementing the nonce for each operation (`createAction`,
  /// `cancelAction`, `castApproval` and `castDisapproval`) signed by the tokenholders.
  mapping(address tokenholders => mapping(bytes4 selector => uint256 currentNonce)) public nonces;

  /// @param llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param role The role used by this contract to cast approvals and disapprovals.
  /// @param minApprovalPct The minimum % of approvals required to submit approvals to `LlamaCore`.
  /// @param minDisapprovalPct The minimum % of disapprovals required to submit disapprovals to `LlamaCore`.
  constructor(ILlamaCore llamaCore, uint8 role, uint256 minApprovalPct, uint256 minDisapprovalPct) {
    if (llamaCore.actionsCount() < 0) revert InvalidLlamaCoreAddress();
    if (role > llamaCore.policy().numRoles()) revert RoleNotInitialized(role);
    if (minApprovalPct > ONE_HUNDRED_IN_BPS || minApprovalPct <= 0) revert InvalidMinApprovalPct(minApprovalPct);
    if (minDisapprovalPct > ONE_HUNDRED_IN_BPS || minDisapprovalPct <= 0) {
      revert InvalidMinDisapprovalPct(minDisapprovalPct);
    }

    LLAMA_CORE = llamaCore;
    ROLE = role;
    MIN_APPROVAL_PCT = minApprovalPct;
    MIN_DISAPPROVAL_PCT = minDisapprovalPct;
  }

  /// @notice How tokenholders add their support of the approval of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain, but this is not currently supported.
  /// @param reason The reason given for the approval by the tokenholder.
  function castApproval(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external {
    _castApproval(msg.sender, actionInfo, support, reason);
  }

  function castApprovalBySig(
    address caster,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 digest = _getCastApprovalTypedDataHash(caster, support, actionInfo, reason);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != caster) revert InvalidSignature();
    _castApproval(signer, actionInfo, support, reason);
  }

  /// @notice How tokenholders add their support of the dapproval of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain, but this is not currently supported.
  /// @param reason The reason given for the approval by the tokenholder.
  function castDisapproval(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external {
    _castDisapproval(msg.sender, actionInfo, support, reason);
  }

  function castDisapprovalBySig(
    address caster,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 digest = _getCastDisapprovalTypedDataHash(caster, support, actionInfo, reason);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != caster) revert InvalidSignature();
    _castDisapproval(signer, actionInfo, support, reason);
  }

  /// @notice Submits cast approvals to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev this function can be called by anyone
  function submitApprovals(ActionInfo calldata actionInfo) external {
    Action memory action = LLAMA_CORE.getAction(actionInfo.id);

    if (casts[actionInfo.id].approvalSubmitted) revert AlreadySubmittedApproval();
    // check to make sure the casting period has ended
    uint256 approvalPeriod = ILlamaRelativeStrategyBase(address(actionInfo.strategy)).approvalPeriod();
    if (block.timestamp < action.creationTime + (approvalPeriod * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS) {
      revert CantSubmitYet();
    }

    if (block.timestamp > action.creationTime + approvalPeriod) revert SubmissionPeriodOver();

    /// @dev only timestamp mode is supported for now.
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    uint256 totalSupply = _getPastTotalSupply(action.creationTime - 1);
    uint96 approvalsFor = casts[actionInfo.id].approvalsFor;
    uint96 approvalsAgainst = casts[actionInfo.id].approvalsAgainst;
    uint96 approvalsAbstain = casts[actionInfo.id].approvalsAbstain;
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, MIN_APPROVAL_PCT, ONE_HUNDRED_IN_BPS);
    if (approvalsFor < threshold) revert InsufficientApprovals(approvalsFor, threshold);
    if (approvalsFor <= approvalsAgainst) revert ForDoesNotSurpassAgainst(approvalsFor, approvalsAgainst);

    casts[actionInfo.id].approvalSubmitted = true;
    LLAMA_CORE.castApproval(ROLE, actionInfo, "");
    emit ApprovalsSubmitted(actionInfo.id, approvalsFor, approvalsAgainst, approvalsAbstain);
  }

  /// @notice Submits cast approvals to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev this function can be called by anyone
  function submitDisapprovals(ActionInfo calldata actionInfo) external {
    Action memory action = LLAMA_CORE.getAction(actionInfo.id);

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, msg.sender, ROLE); // Reverts if not allowed.
    if (casts[actionInfo.id].disapprovalSubmitted) revert AlreadySubmittedDisapproval();

    uint256 queuingPeriod = ILlamaRelativeStrategyBase(address(actionInfo.strategy)).queuingPeriod();
    // check to make sure the current timestamp is within the submitDisapprovalBuffer 9period
    if (block.timestamp < action.minExecutionTime - (queuingPeriod * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS) {
      revert CantSubmitYet();
    }
    if (block.timestamp >= action.minExecutionTime) revert SubmissionPeriodOver();
    /// @dev only timestamp mode is supported for now
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    uint256 totalSupply = _getPastTotalSupply(action.creationTime - 1);
    uint96 disapprovalsFor = casts[actionInfo.id].disapprovalsFor;
    uint96 disapprovalsAgainst = casts[actionInfo.id].disapprovalsAgainst;
    uint96 disapprovalsAbstain = casts[actionInfo.id].disapprovalsAbstain;
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, MIN_DISAPPROVAL_PCT, ONE_HUNDRED_IN_BPS);
    if (disapprovalsFor < threshold) revert InsufficientApprovals(disapprovalsFor, threshold);
    if (disapprovalsFor <= disapprovalsAgainst) revert ForDoesNotSurpassAgainst(disapprovalsFor, disapprovalsAgainst);

    casts[actionInfo.id].disapprovalSubmitted = true;
    LLAMA_CORE.castDisapproval(ROLE, actionInfo, "");
    emit DisapprovalsSubmitted(actionInfo.id, disapprovalsFor, disapprovalsAgainst, disapprovalsAbstain);
  }

  function _castApproval(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason)
    internal
  {
    Action memory action = LLAMA_CORE.getAction(actionInfo.id);

    actionInfo.strategy.checkIfApprovalEnabled(actionInfo, caster, ROLE); // Reverts if not allowed.
    if (LLAMA_CORE.getActionState(actionInfo) != uint8(ActionState.Active)) revert ActionNotActive();
    if (casts[actionInfo.id].castApproval[caster]) revert AlreadyCastApproval();
    if (
      block.timestamp
        > action.creationTime
          + (ILlamaRelativeStrategyBase(address(actionInfo.strategy)).approvalPeriod() * TWO_THIRDS_IN_BPS)
            / ONE_HUNDRED_IN_BPS
    ) revert CastingPeriodOver();

    uint256 balance = _getPastVotes(caster, action.creationTime - 1);
    _preCastAssertions(balance, support);

    if (support == 0) casts[actionInfo.id].approvalsAgainst += LlamaUtils.toUint96(balance);
    else if (support == 1) casts[actionInfo.id].approvalsFor += LlamaUtils.toUint96(balance);
    else if (support == 2) casts[actionInfo.id].approvalsAbstain += LlamaUtils.toUint96(balance);
    casts[actionInfo.id].castApproval[caster] = true;
    emit ApprovalCast(actionInfo.id, caster, ROLE, support, balance, reason);
  }

  function _castDisapproval(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason)
    internal
  {
    Action memory action = LLAMA_CORE.getAction(actionInfo.id);

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, caster, ROLE); // Reverts if not allowed.
    if (!actionInfo.strategy.isActionApproved(actionInfo)) revert ActionNotApproved();
    if (actionInfo.strategy.isActionExpired(actionInfo)) revert ActionExpired();
    if (casts[actionInfo.id].castDisapproval[caster]) revert AlreadyCastDisapproval();
    if (
      block.timestamp
        > action.minExecutionTime
          - (ILlamaRelativeStrategyBase(address(actionInfo.strategy)).queuingPeriod() * ONE_THIRD_IN_BPS)
            / ONE_HUNDRED_IN_BPS
    ) revert CastingPeriodOver();

    uint256 balance = _getPastVotes(caster, action.creationTime - 1);
    _preCastAssertions(balance, support);

    if (support == 0) casts[actionInfo.id].disapprovalsAgainst += LlamaUtils.toUint96(balance);
    else if (support == 1) casts[actionInfo.id].disapprovalsFor += LlamaUtils.toUint96(balance);
    else if (support == 2) casts[actionInfo.id].disapprovalsAbstain += LlamaUtils.toUint96(balance);
    casts[actionInfo.id].castDisapproval[caster] = true;
    emit DisapprovalCast(actionInfo.id, caster, ROLE, support, balance, reason);
  }

  function _preCastAssertions(uint256 balance, uint8 support) internal view {
    if (support > 2) revert InvalidSupport(support);

    /// @dev only timestamp mode is supported for now.
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    if (balance == 0) revert InsufficientBalance(balance);
  }

  /// @notice Increments the caller's nonce for the given `selector`. This is useful for revoking
  /// signatures that have not been used yet.
  /// @param selector The function selector to increment the nonce for.
  function incrementNonce(bytes4 selector) external {
    // Safety: Can never overflow a uint256 by incrementing.
    nonces[msg.sender][selector] = LlamaUtils.uncheckedIncrement(nonces[msg.sender][selector]);
  }

  function _getPastVotes(address account, uint256 timestamp) internal view virtual returns (uint256) {}
  function _getPastTotalSupply(uint256 timestamp) internal view virtual returns (uint256) {}
  function _getClockMode() internal view virtual returns (string memory) {}

  /// @dev Returns the current nonce for a given tokenholder and selector, and increments it. Used to prevent
  /// replay attacks.
  function _useNonce(address tokenholder, bytes4 selector) internal returns (uint256 nonce) {
    nonce = nonces[tokenholder][selector];
    nonces[tokenholder][selector] = LlamaUtils.uncheckedIncrement(nonce);
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

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CastApproval` domain, which can be used to
  /// recover the signer.
  function _getCastApprovalTypedDataHash(
    address tokenholder,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castApprovalHash = keccak256(
      abi.encode(
        CAST_APPROVAL_BY_SIG_TYPEHASH,
        tokenholder,
        support,
        _getActionInfoHash(actionInfo),
        keccak256(bytes(reason)),
        _useNonce(tokenholder, msg.sig)
      )
    );

    return keccak256(abi.encodePacked("\x19\x01", _getDomainHash(), castApprovalHash));
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CastDisapproval` domain, which can be used to
  /// recover the signer.
  function _getCastDisapprovalTypedDataHash(
    address tokenholder,
    uint8 role,
    ActionInfo calldata actionInfo,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castDisapprovalHash = keccak256(
      abi.encode(
        CAST_DISAPPROVAL_BY_SIG_TYPEHASH,
        tokenholder,
        role,
        _getActionInfoHash(actionInfo),
        keccak256(bytes(reason)),
        _useNonce(tokenholder, msg.sig)
      )
    );

    return keccak256(abi.encodePacked("\x19\x01", _getDomainHash(), castDisapprovalHash));
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ActionState, VoteType} from "src/lib/Enums.sol";
import {LlamaUtils} from "src/lib/LlamaUtils.sol";
import {PeriodPctCheckpoints} from "src/lib/PeriodPctCheckpoints.sol";
import {QuorumCheckpoints} from "src/lib/QuorumCheckpoints.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";

/// @title LlamaTokenCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance token collectively cast an approval or
/// disapproval on created actions.
/// @dev This contract is deployed by `LlamaTokenVotingFactory`. Anyone can deploy this contract using the factory, but
/// it must hold a Policy from the specified `LlamaCore` instance to actually be able to cast on an action. This
/// contract does not verify that it holds the correct policy when voting and relies on `LlamaCore` to
/// verify that during submission.
abstract contract LlamaTokenCaster is Initializable {
  using PeriodPctCheckpoints for PeriodPctCheckpoints.History;
  using QuorumCheckpoints for QuorumCheckpoints.History;
  // =========================
  // ======== Structs ========
  // =========================

  /// @dev Cast counts and submission data.
  struct CastData {
    uint96 votesFor; // Number of votes casted for this action.
    uint96 votesAbstain; // Number of abstentions casted for this action.
    uint96 votesAgainst; // Number of votes casted against this action.
    bool approvalSubmitted; // True if the approval was submitted to `LlamaCore, false otherwise.
    uint96 vetoesFor; // Number of vetoes casted for this action.
    uint96 vetoesAbstain; // Number of abstentions casted for this action.
    uint96 vetoesAgainst; // Number of disapprovals casted against this action.
    bool disapprovalSubmitted; // True if the disapproval has been submitted to `LlamaCore`, false otherwise.
    mapping(address tokenholder => bool) castVote; // True if tokenholder casted a vote, false otherwise.
    mapping(address tokenholder => bool) castVeto; // True if tokenholder casted a veto, false otherwise.
  }

  // ========================
  // ======== Errors ========
  // ========================

  /// @dev Thrown when a user tries to cast a vote but the action is not active.
  error ActionNotActive();

  /// @dev Thrown when a user tries to cast a veto but the action is not queued.
  error ActionNotQueued();

  /// @dev Thrown when a user tries to cast a vote but has already casted.
  error AlreadyCastedVote();

  /// @dev Thrown when a user tries to cast approval but the casts have already been submitted to `LlamaCore`.
  error AlreadySubmittedApproval();

  /// @dev Thrown when a user tries to cast a veto but has already casted.
  error AlreadyCastedVeto();

  /// @dev Thrown when a user tries to cast disapproval but the casts have already been submitted to `LlamaCore.
  error AlreadySubmittedDisapproval();

  /// @dev Thrown when a user tries to cast a vote or veto but the casting period has ended.
  error CastingPeriodOver();

  /// @dev Thrown when a user tries to cast (dis)approval but the action cannot be submitted yet.
  error CannotSubmitYet();

  /// @dev Thrown when a user tries to create an action but the clock mode is not supported.
  error ClockModeNotSupported(string clockMode);

  /// @dev Thrown when a user tries to cast a vote or veto but the against surpasses for.
  error ForDoesNotSurpassAgainst(uint256 castsFor, uint256 castsAgainst);

  /// @dev Thrown when a user tries to submit an approval but there are not enough votes.
  error InsufficientVotes(uint256 votes, uint256 threshold);

  /// @dev Thrown when a user tries to cast but does not have enough tokens.
  error InsufficientBalance(uint256 balance);

  /// @dev Thrown when an invalid `castingPeriodPct` and `submissionPeriodPct` are set.
  error InvalidPeriodPcts(uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct);

  /// @dev Thrown when an invalid `voteQuorumPct` is passed to the constructor.
  error InvalidVoteQuorumPct(uint16 voteQuorumPct);

  /// @dev Thrown when an invalid `vetoQuorumPct` is passed to the constructor.
  error InvalidVetoQuorumPct(uint16 vetoQuorumPct);

  /// @dev Thrown when an invalid `llamaCore` address is passed to the constructor.
  error InvalidLlamaCoreAddress();

  /// @dev The recovered signer does not match the expected tokenholder.
  error InvalidSignature();

  /// @dev Thrown when an invalid `token` address is passed to the constructor.
  error InvalidTokenAddress();

  /// @dev Thrown when an invalid `support` value is used when casting.
  error InvalidSupport(uint8 support);

  /// @dev Thrown when an address other than the `LlamaExecutor` tries to call a function.
  error OnlyLlamaExecutor();

  /// @dev Thrown when an invalid `role` is passed to the constructor.
  error RoleNotInitialized(uint8 role);

  /// @dev Thrown when a user tries to submit (dis)approval but the submission period has ended.
  error SubmissionPeriodOver();

  // ========================
  // ======== Events ========
  // ========================

  /// @dev Emitted when a cast approval is submitted to the `LlamaCore` contract.
  event ApprovalSubmitted(
    uint256 id, address indexed caller, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain
  );

  /// @dev Emitted when a cast disapproval is submitted to the `LlamaCore` contract.
  event DisapprovalSubmitted(
    uint256 id, address indexed caller, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain
  );

  /// @dev Emitted when the casting and submission period ratio is set.
  event PeriodsPctSet(uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct);

  /// @dev Emitted when the voting quorum and/or vetoing quorum is set.
  event QuorumSet(uint16 voteQuorumPct, uint16 vetoQuorumPct);

  /// @dev Emitted when a veto is cast.
  event VetoCast(uint256 id, address indexed tokenholder, uint8 indexed support, uint256 quantity, string reason);

  /// @dev Emitted when a vote is cast.
  event VoteCast(uint256 id, address indexed tokenholder, uint8 indexed support, uint256 quantity, string reason);

  // =================================================
  // ======== Constants and Storage Variables ========
  // =================================================

  /// @dev EIP-712 base typehash.
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @notice EIP-712 castVote typehash.
  bytes32 internal constant CAST_VOTE_TYPEHASH = keccak256(
    "CastVote(address tokenHolder,uint8 support,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice EIP-712 castVeto typehash.
  bytes32 internal constant CAST_VETO_TYPEHASH = keccak256(
    "CastVeto(address tokenHolder,uint8 role,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev EIP-712 actionInfo typehash.
  bytes32 internal constant ACTION_INFO_TYPEHASH = keccak256(
    "ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev Equivalent to 100%, but in basis points.
  uint256 internal constant ONE_HUNDRED_IN_BPS = 10_000;

  /// @dev Equivalent to 1/3, but in basis points.
  uint256 internal constant ONE_THIRD_IN_BPS = 3333;

  /// @dev Equivalent to 2/3, but in basis points.
  uint256 internal constant TWO_THIRDS_IN_BPS = 6667;

  /// @notice The core contract for this Llama instance.
  ILlamaCore public llamaCore;

  QuorumCheckpoints.History internal quorumCheckpoints;

  PeriodPctCheckpoints.History internal periodPctsCheckpoint;

  /// @notice The role used by this contract to cast approvals and disapprovals.
  /// @dev This role is expected to have the ability to force approve and disapprove actions.
  uint8 public role;

  /// @notice Mapping from action ID to the status of existing casts.
  mapping(uint256 actionId => CastData) public casts;

  /// @notice Mapping of tokenholders to function selectors to current nonces for EIP-712 signatures.
  /// @dev This is used to prevent replay attacks by incrementing the nonce for each operation (`createAction`,
  /// `cancelAction`, `castVote` and `castVeto`) signed by the tokenholders.
  mapping(address tokenholders => mapping(bytes4 selector => uint256 currentNonce)) public nonces;

  // ================================
  // ======== Initialization ========
  // ================================

  /// @dev This will be called by the `initialize` of the inheriting contract.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _voteQuorumPct The minimum % of votes required to submit an approval to `LlamaCore`.
  /// @param _vetoQuorumPct The minimum % of vetoes required to submit a disapproval to `LlamaCore`.
  function __initializeLlamaTokenCasterMinimalProxy(
    ILlamaCore _llamaCore,
    uint8 _role,
    uint16 _voteQuorumPct,
    uint16 _vetoQuorumPct
  ) internal {
    if (_llamaCore.actionsCount() < 0) revert InvalidLlamaCoreAddress();
    if (_role > _llamaCore.policy().numRoles()) revert RoleNotInitialized(_role);
    if (_voteQuorumPct > ONE_HUNDRED_IN_BPS || _voteQuorumPct <= 0) revert InvalidVoteQuorumPct(_voteQuorumPct);
    if (_vetoQuorumPct > ONE_HUNDRED_IN_BPS || _vetoQuorumPct <= 0) revert InvalidVetoQuorumPct(_vetoQuorumPct);

    llamaCore = _llamaCore;
    role = _role;
    quorumCheckpoints.push(_voteQuorumPct, _vetoQuorumPct);
    emit QuorumSet(_voteQuorumPct, _vetoQuorumPct);
  }

  // ===========================================
  // ======== External and Public Logic ========
  // ===========================================

  // -------- Action Lifecycle Management --------

  /// @notice How tokenholders add their support of the approval of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain, but this is not currently supported.
  /// @param reason The reason given for the approval by the tokenholder.
  function castVote(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external {
    _castVote(msg.sender, actionInfo, support, reason);
  }

  function castVoteBySig(
    address caster,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 digest = _getCastVoteTypedDataHash(caster, support, actionInfo, reason);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != caster) revert InvalidSignature();
    _castVote(signer, actionInfo, support, reason);
  }

  /// @notice How tokenholders add their support of the disapproval of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain, but this is not currently supported.
  /// @param reason The reason given for the approval by the tokenholder.
  function castVeto(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external {
    _castVeto(msg.sender, actionInfo, support, reason);
  }

  function castVetoBySig(
    address caster,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 digest = _getCastVetoTypedDataHash(caster, support, actionInfo, reason);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != caster) revert InvalidSignature();
    _castVeto(signer, actionInfo, support, reason);
  }

  /// @notice Submits a cast approval to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev this function can be called by anyone
  function submitApproval(ActionInfo calldata actionInfo) external {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfApprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (casts[actionInfo.id].approvalSubmitted) revert AlreadySubmittedApproval();
    // check to make sure the casting period has ended
    uint256 approvalPeriod = actionInfo.strategy.approvalPeriod();
    if (block.timestamp < action.creationTime + (approvalPeriod * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS) {
      revert CannotSubmitYet();
    }

    if (block.timestamp > action.creationTime + approvalPeriod) revert SubmissionPeriodOver();

    /// @dev only timestamp mode is supported for now.
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    uint256 totalSupply = _getPastTotalSupply(action.creationTime - 1);
    uint96 votesFor = casts[actionInfo.id].votesFor;
    uint96 votesAgainst = casts[actionInfo.id].votesAgainst;
    uint96 votesAbstain = casts[actionInfo.id].votesAbstain;
    (uint16 voteQuorumPct,) = quorumCheckpoints.getAtProbablyRecentTimestamp(action.creationTime - 1);
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, voteQuorumPct, ONE_HUNDRED_IN_BPS);
    if (votesFor < threshold) revert InsufficientVotes(votesFor, threshold);
    if (votesFor <= votesAgainst) revert ForDoesNotSurpassAgainst(votesFor, votesAgainst);

    casts[actionInfo.id].approvalSubmitted = true;
    llamaCore.castApproval(role, actionInfo, "");
    emit ApprovalSubmitted(actionInfo.id, msg.sender, votesFor, votesAgainst, votesAbstain);
  }

  /// @notice Submits a cast disapproval to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev this function can be called by anyone
  function submitDisapproval(ActionInfo calldata actionInfo) external {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (casts[actionInfo.id].disapprovalSubmitted) revert AlreadySubmittedDisapproval();

    uint256 queuingPeriod = actionInfo.strategy.queuingPeriod();
    // check to make sure the current timestamp is within the submitDisapprovalBuffer 9period
    if (block.timestamp < action.minExecutionTime - (queuingPeriod * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS) {
      revert CannotSubmitYet();
    }
    if (block.timestamp >= action.minExecutionTime) revert SubmissionPeriodOver();
    /// @dev only timestamp mode is supported for now
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    uint256 totalSupply = _getPastTotalSupply(action.creationTime - 1);
    uint96 vetoesFor = casts[actionInfo.id].vetoesFor;
    uint96 vetoesAgainst = casts[actionInfo.id].vetoesAgainst;
    uint96 vetoesAbstain = casts[actionInfo.id].vetoesAbstain;
    (, uint16 vetoQuorumPct) = quorumCheckpoints.getAtProbablyRecentTimestamp(action.creationTime - 1);
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, vetoQuorumPct, ONE_HUNDRED_IN_BPS);
    if (vetoesFor < threshold) revert InsufficientVotes(vetoesFor, threshold);
    if (vetoesFor <= vetoesAgainst) revert ForDoesNotSurpassAgainst(vetoesFor, vetoesAgainst);

    casts[actionInfo.id].disapprovalSubmitted = true;
    llamaCore.castDisapproval(role, actionInfo, "");
    emit DisapprovalSubmitted(actionInfo.id, msg.sender, vetoesFor, vetoesAgainst, vetoesAbstain);
  }

  // -------- Instance Management --------

  /// @notice Sets the voting quorum and vetoing quorum.
  /// @param _voteQuorumPct The minimum % of votes required to submit an approval to `LlamaCore`.
  /// @param _vetoQuorumPct The minimum % of vetoes required to submit a disapproval to `LlamaCore`.
  function setQuorumPct(uint16 _voteQuorumPct, uint16 _vetoQuorumPct) external {
    if (msg.sender != llamaCore.executor()) revert OnlyLlamaExecutor();
    if (_voteQuorumPct > ONE_HUNDRED_IN_BPS || _voteQuorumPct <= 0) revert InvalidVoteQuorumPct(_voteQuorumPct);
    if (_vetoQuorumPct > ONE_HUNDRED_IN_BPS || _vetoQuorumPct <= 0) revert InvalidVetoQuorumPct(_vetoQuorumPct);
    quorumCheckpoints.push(_voteQuorumPct, _vetoQuorumPct);
    emit QuorumSet(_voteQuorumPct, _vetoQuorumPct);
  }

  /// @notice Sets the casting / submission period ratio
  /// @dev `_castingPeriodPct` + `_submissionPeriodPct` must be equal to `ONE_HUNDRED_IN_BPS`
  /// @param _castingPeriodPct The minimum % of votes required to submit an approval to `LlamaCore`.
  /// @param _submissionPeriodPct The minimum % of vetoes required to submit a disapproval to `LlamaCore`.
  function setPeriodPcts(uint16 _delayPeriodPct, uint16 _castingPeriodPct, uint16 _submissionPeriodPct) external {
    if (msg.sender != llamaCore.executor()) revert OnlyLlamaExecutor();
    if (_delayPeriodPct + _castingPeriodPct + _submissionPeriodPct != ONE_HUNDRED_IN_BPS) {
      revert InvalidPeriodPcts(_delayPeriodPct, _castingPeriodPct, _submissionPeriodPct);
    }
    periodPctsCheckpoint.push(_delayPeriodPct, _castingPeriodPct, _submissionPeriodPct);
    emit PeriodsPctSet(_delayPeriodPct, _castingPeriodPct, _submissionPeriodPct);
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

  function _castVote(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason) internal {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfApprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (llamaCore.getActionState(actionInfo) != uint8(ActionState.Active)) revert ActionNotActive();
    if (casts[actionInfo.id].castVote[caster]) revert AlreadyCastedVote();
    if (
      block.timestamp
        > action.creationTime + (actionInfo.strategy.approvalPeriod() * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS
    ) revert CastingPeriodOver();

    uint256 balance = _getPastVotes(caster, action.creationTime - 1);
    _preCastAssertions(balance, support);

    if (support == uint8(VoteType.Against)) casts[actionInfo.id].votesAgainst += LlamaUtils.toUint96(balance);
    else if (support == uint8(VoteType.For)) casts[actionInfo.id].votesFor += LlamaUtils.toUint96(balance);
    else if (support == uint8(VoteType.Abstain)) casts[actionInfo.id].votesAbstain += LlamaUtils.toUint96(balance);
    casts[actionInfo.id].castVote[caster] = true;
    emit VoteCast(actionInfo.id, caster, support, balance, reason);
  }

  function _castVeto(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason) internal {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (llamaCore.getActionState(actionInfo) != uint8(ActionState.Queued)) revert ActionNotQueued();
    if (casts[actionInfo.id].castVeto[caster]) revert AlreadyCastedVeto();
    if (
      block.timestamp
        > action.minExecutionTime - (actionInfo.strategy.queuingPeriod() * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS
    ) revert CastingPeriodOver();

    uint256 balance = _getPastVotes(caster, action.creationTime - 1);
    _preCastAssertions(balance, support);

    if (support == uint8(VoteType.Against)) casts[actionInfo.id].vetoesAgainst += LlamaUtils.toUint96(balance);
    else if (support == uint8(VoteType.For)) casts[actionInfo.id].vetoesFor += LlamaUtils.toUint96(balance);
    else if (support == uint8(VoteType.Abstain)) casts[actionInfo.id].vetoesAbstain += LlamaUtils.toUint96(balance);
    casts[actionInfo.id].castVeto[caster] = true;
    emit VetoCast(actionInfo.id, caster, support, balance, reason);
  }

  function _preCastAssertions(uint256 balance, uint8 support) internal view {
    if (support > uint8(VoteType.Abstain)) revert InvalidSupport(support);

    /// @dev only timestamp mode is supported for now.
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    if (balance == 0) revert InsufficientBalance(balance);
  }

  /// @dev Returns the number of votes for a given token holder at a given timestamp.
  function _getPastVotes(address account, uint256 timestamp) internal view virtual returns (uint256) {}

  /// @dev Returns the total supply of the token at a given timestamp.
  function _getPastTotalSupply(uint256 timestamp) internal view virtual returns (uint256) {}

  /// @dev Returns the clock mode of the token (https://eips.ethereum.org/EIPS/eip-6372).
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
        EIP712_DOMAIN_TYPEHASH, keccak256(bytes(llamaCore.name())), keccak256(bytes("1")), block.chainid, address(this)
      )
    );
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CastApproval` domain, which can be used to
  /// recover the signer.
  function _getCastVoteTypedDataHash(
    address tokenholder,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castVoteHash = keccak256(
      abi.encode(
        CAST_VOTE_TYPEHASH,
        tokenholder,
        support,
        _getActionInfoHash(actionInfo),
        keccak256(bytes(reason)),
        _useNonce(tokenholder, msg.sig)
      )
    );

    return keccak256(abi.encodePacked("\x19\x01", _getDomainHash(), castVoteHash));
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CastDisapproval` domain, which can be used to
  /// recover the signer.
  function _getCastVetoTypedDataHash(
    address tokenholder,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castVetoHash = keccak256(
      abi.encode(
        CAST_VETO_TYPEHASH,
        tokenholder,
        support,
        _getActionInfoHash(actionInfo),
        keccak256(bytes(reason)),
        _useNonce(tokenholder, msg.sig)
      )
    );

    return keccak256(abi.encodePacked("\x19\x01", _getDomainHash(), castVetoHash));
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

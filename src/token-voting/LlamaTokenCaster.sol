// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {ActionState, VoteType} from "src/lib/Enums.sol";
import {CasterConfig} from "src/lib/Structs.sol";
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
contract LlamaTokenCaster is Initializable {
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

  /// @dev Thrown when a user tries to cast a veto but has already casted.
  error AlreadyCastedVeto();

  /// @dev Thrown when a user tries to cast a vote but has already casted.
  error AlreadyCastedVote();

  /// @dev Thrown when a user tries to cast approval but the casts have already been submitted to `LlamaCore`.
  error AlreadySubmittedApproval();

  /// @dev Thrown when a user tries to cast disapproval but the casts have already been submitted to `LlamaCore.
  error AlreadySubmittedDisapproval();

  /// @dev Thrown when a user tries to cast (dis)approval but the action cannot be submitted yet.
  error CannotSubmitYet();

  /// @dev Thrown when a user tries to cast a vote or veto but the casting period has ended.
  error CastingPeriodOver();

  /// @dev Thrown when a user tries to cast a vote or veto but the against surpasses for.
  error ForDoesNotSurpassAgainst(uint256 castsFor, uint256 castsAgainst);

  /// @dev Thrown when a user tries to submit an approval but there are not enough votes.
  error InsufficientVotes(uint256 votes, uint256 threshold);

  /// @dev Thrown when a user tries to query checkpoints at non-existant indices.
  error InvalidIndices();

  /// @dev Thrown when an invalid `llamaCore` address is passed to the constructor.
  error InvalidLlamaCoreAddress();

  /// @dev Thrown when an invalid `castingPeriodPct` and `submissionPeriodPct` are set.
  error InvalidPeriodPcts(uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct);

  /// @dev The recovered signer does not match the expected tokenholder.
  error InvalidSignature();

  /// @dev Thrown when an invalid `support` value is used when casting.
  error InvalidSupport(uint8 support);

  /// @dev Thrown when an invalid `vetoQuorumPct` is passed to the constructor.
  error InvalidVetoQuorumPct(uint16 vetoQuorumPct);

  /// @dev Thrown when an invalid `voteQuorumPct` is passed to the constructor.
  error InvalidVoteQuorumPct(uint16 voteQuorumPct);

  /// @dev Thrown when an address other than the `LlamaExecutor` tries to call a function.
  error OnlyLlamaExecutor();

  /// @dev Thrown when an invalid `role` is passed to the constructor.
  error RoleNotInitialized(uint8 role);

  /// @dev Thrown when a user tries to submit (dis)approval but the submission period has ended.
  error SubmissionPeriodOver();

  /// @dev Thrown when a user tries to cast a vote or veto but the voting delay has not passed.
  error VotingDelayNotOver();

  // ========================
  // ======== Events ========
  // ========================

  /// @dev Emitted when a cast approval is submitted to the `LlamaCore` contract.
  event ApprovalSubmitted(
    uint256 id, address indexed caller, uint256 weightFor, uint256 weightAgainst, uint256 weightAbstain
  );

  /// @dev Emitted when a cast disapproval is submitted to the `LlamaCore` contract.
  event DisapprovalSubmitted(
    uint256 id, address indexed caller, uint256 weightFor, uint256 weightAgainst, uint256 weightAbstain
  );

  /// @dev Emitted when the casting and submission period ratio is set.
  event PeriodPctSet(uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct);

  /// @dev Emitted when the voting quorum and/or vetoing quorum is set.
  event QuorumPctSet(uint16 voteQuorumPct, uint16 vetoQuorumPct);

  /// @dev Emitted when a veto is cast.
  event VetoCast(uint256 id, address indexed tokenholder, uint8 indexed support, uint256 weight, string reason);

  /// @dev Emitted when a vote is cast.
  event VoteCast(uint256 id, address indexed tokenholder, uint8 indexed support, uint256 weight, string reason);

  // =================================================
  // ======== Constants and Storage Variables ========
  // =================================================

  /// @dev EIP-712 base typehash.
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @notice EIP-712 castVote typehash.
  bytes32 internal constant CAST_VOTE_TYPEHASH = keccak256(
    "CastVote(address tokenHolder,ActionInfo actionInfo,uint8 support,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice EIP-712 castVeto typehash.
  bytes32 internal constant CAST_VETO_TYPEHASH = keccak256(
    "CastVeto(address tokenHolder,ActionInfo actionInfo,uint8 support,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev EIP-712 actionInfo typehash.
  bytes32 internal constant ACTION_INFO_TYPEHASH = keccak256(
    "ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev Equivalent to 100%, but in basis points.
  uint256 internal constant ONE_HUNDRED_IN_BPS = 10_000;

  /// @notice The core contract for this Llama instance.
  ILlamaCore public llamaCore;

  /// @dev The quorum checkpoints for this token voting module.
  QuorumCheckpoints.History internal quorumCheckpoints;

  /// @dev The period pct checkpoints for this token voting module.
  PeriodPctCheckpoints.History internal periodPctsCheckpoint;

  /// @notice The contract that manages the timepoints for this token voting module.
  ILlamaTokenAdapter public tokenAdapter;

  /// @notice The role used by this contract to cast approvals and disapprovals.
  /// @dev This role is expected to have the ability to force approve and disapprove actions.
  uint8 public role;

  /// @notice Mapping from action ID to the status of existing casts.
  mapping(uint256 actionId => CastData) public casts;

  /// @notice Mapping of tokenholders to function selectors to current nonces for EIP-712 signatures.
  /// @dev This is used to prevent replay attacks by incrementing the nonce for each operation (`castVote` and
  /// `castVeto`) signed by the tokenholders.
  mapping(address tokenholders => mapping(bytes4 selector => uint256 currentNonce)) public nonces;

  // ================================
  // ======== Initialization ========
  // ================================

  /// @dev This contract is deployed as a minimal proxy from the factory's `deploy` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC20TokenCaster` clone.
  /// @dev This function is called by the `deploy` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _tokenAdapter The token adapter that manages the clock, timepoints, past votes and past supply for this
  /// token voting module.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param casterConfig Contains the quorum and period pct values to initialize the contract with.
  function initialize(
    ILlamaCore _llamaCore,
    ILlamaTokenAdapter _tokenAdapter,
    uint8 _role,
    CasterConfig memory casterConfig
  ) external initializer {
    if (_llamaCore.actionsCount() < 0) revert InvalidLlamaCoreAddress();
    if (_role > _llamaCore.policy().numRoles()) revert RoleNotInitialized(_role);

    llamaCore = _llamaCore;
    tokenAdapter = _tokenAdapter;
    role = _role;
    _setQuorumPct(casterConfig.voteQuorumPct, casterConfig.vetoQuorumPct);
    _setPeriodPct(casterConfig.delayPeriodPct, casterConfig.castingPeriodPct, casterConfig.submissionPeriodPct);
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
  ///   2 = Abstain
  /// @param reason The reason given for the approval by the tokenholder.
  /// @return The weight of the cast.
  function castVote(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external returns (uint96) {
    return _castVote(msg.sender, actionInfo, support, reason);
  }

  /// @notice How tokenholders add their support of the approval of an action with a reason via an off-chain
  /// signature.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param caster The tokenholder that signed the message.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain
  /// @param reason The reason given for the approval by the tokenholder.
  /// @param v ECDSA signature component: Parity of the `y` coordinate of point `R`
  /// @param r ECDSA signature component: x-coordinate of `R`
  /// @param s ECDSA signature component: `s` value of the signature
  /// @return The weight of the cast.
  function castVoteBySig(
    address caster,
    ActionInfo calldata actionInfo,
    uint8 support,
    string calldata reason,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint96) {
    bytes32 digest = _getCastVoteTypedDataHash(caster, actionInfo, support, reason);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != caster) revert InvalidSignature();
    return _castVote(signer, actionInfo, support, reason);
  }

  /// @notice How tokenholders add their support of the disapproval of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain
  /// @param reason The reason given for the approval by the tokenholder.
  /// @return The weight of the cast.
  function castVeto(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external returns (uint96) {
    return _castVeto(msg.sender, actionInfo, support, reason);
  }

  /// @notice How tokenholders add their support of the disapproval of an action with a reason via an off-chain
  /// signature.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param caster The tokenholder that signed the message.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain
  /// @param reason The reason given for the approval by the tokenholder.
  /// @param v ECDSA signature component: Parity of the `y` coordinate of point `R`
  /// @param r ECDSA signature component: x-coordinate of `R`
  /// @param s ECDSA signature component: `s` value of the signature
  /// @return The weight of the cast.
  function castVetoBySig(
    address caster,
    ActionInfo calldata actionInfo,
    uint8 support,
    string calldata reason,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint96) {
    bytes32 digest = _getCastVetoTypedDataHash(caster, actionInfo, support, reason);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != caster) revert InvalidSignature();
    return _castVeto(signer, actionInfo, support, reason);
  }

  /// @notice Submits a cast approval to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev this function can be called by anyone
  function submitApproval(ActionInfo calldata actionInfo) external {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfApprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (casts[actionInfo.id].approvalSubmitted) revert AlreadySubmittedApproval();
    // Reverts if clock or CLOCK_MODE() has changed
    tokenAdapter.checkIfInconsistentClock();

    // Checks to ensure it's the submission period.
    (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
      periodPctsCheckpoint.getAtProbablyRecentTimestamp(action.creationTime - 1);
    uint256 approvalPeriod = actionInfo.strategy.approvalPeriod();
    uint256 delayPeriodEndTime = action.creationTime + ((approvalPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((approvalPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
    if (block.timestamp <= castingPeriodEndTime) revert CannotSubmitYet();
    // Doing (action.creationTime + approvalPeriod) vs (castingPeriodEndTime + ((approvalPeriod * submissionPeriodPct) /
    // ONE_HUNDRED_IN_BPS)) to prevent any off-by-one errors due to precision loss.
    // Llama approval period is inclusive of approval end time.
    if (block.timestamp > action.creationTime + approvalPeriod) revert SubmissionPeriodOver();

    uint256 totalSupply = tokenAdapter.getPastTotalSupply(tokenAdapter.timestampToTimepoint(delayPeriodEndTime));
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
    // Reverts if clock or CLOCK_MODE() has changed
    tokenAdapter.checkIfInconsistentClock();

    // Checks to ensure it's the submission period.
    (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
      periodPctsCheckpoint.getAtProbablyRecentTimestamp(action.creationTime - 1);
    uint256 queuingPeriod = actionInfo.strategy.queuingPeriod();
    uint256 delayPeriodEndTime =
      (action.minExecutionTime - queuingPeriod) + ((queuingPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((queuingPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
    // Doing (castingPeriodEndTime) vs (action.minExecutionTime - ((queuingPeriod * submissionPeriodPct) /
    // ONE_HUNDRED_IN_BPS)) to prevent any off-by-one errors due to precision loss.
    if (block.timestamp <= castingPeriodEndTime) revert CannotSubmitYet();
    // Llama disapproval period is exclusive of min execution time.
    if (block.timestamp >= action.minExecutionTime) revert SubmissionPeriodOver();

    uint256 totalSupply = tokenAdapter.getPastTotalSupply(tokenAdapter.timestampToTimepoint(delayPeriodEndTime));
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
    _setQuorumPct(_voteQuorumPct, _vetoQuorumPct);
  }

  /// @notice Sets the delay period, casting period and submission period.
  /// @param _delayPeriodPct The % of the total period that must pass before voting can begin.
  /// @param _castingPeriodPct The % of the total period that voting can occur.
  /// @param _submissionPeriodPct The % of the total period withing which the (dis)approval must be submitted.
  function setPeriodPct(uint16 _delayPeriodPct, uint16 _castingPeriodPct, uint16 _submissionPeriodPct) external {
    if (msg.sender != llamaCore.executor()) revert OnlyLlamaExecutor();
    _setPeriodPct(_delayPeriodPct, _castingPeriodPct, _submissionPeriodPct);
  }

  // -------- User Nonce Management --------

  /// @notice Increments the caller's nonce for the given `selector`. This is useful for revoking
  /// signatures that have not been used yet.
  /// @param selector The function selector to increment the nonce for.
  function incrementNonce(bytes4 selector) external {
    // Safety: Can never overflow a uint256 by incrementing.
    nonces[msg.sender][selector] = LlamaUtils.uncheckedIncrement(nonces[msg.sender][selector]);
  }

  // -------- Getters --------
  /// @notice Returns the current voting quorum and vetoing quorum.
  function getQuorum() external view returns (uint16 voteQuorumPct, uint16 vetoQuorumPct) {
    return quorumCheckpoints.latest();
  }

  /// @notice Returns the voting quorum and vetoing quorum at a given timestamp.
  function getPastQuorum(uint256 timestamp) external view returns (uint16 voteQuorumPct, uint16 vetoQuorumPct) {
    return quorumCheckpoints.getAtProbablyRecentTimestamp(timestamp);
  }

  /// @notice Returns all quorum checkpoints.
  function getQuorumCheckpoints() external view returns (QuorumCheckpoints.History memory) {
    return quorumCheckpoints;
  }

  /// @notice Returns the quorum checkpoints array from a given set of indices.
  function getQuorumCheckpoints(uint256 start, uint256 end) external view returns (QuorumCheckpoints.History memory) {
    if (start > end) revert InvalidIndices();
    uint256 checkpointsLength = quorumCheckpoints._checkpoints.length;
    if (end > checkpointsLength) revert InvalidIndices();

    uint256 sliceLength = end - start;
    QuorumCheckpoints.Checkpoint[] memory checkpoints = new QuorumCheckpoints.Checkpoint[](sliceLength);
    for (uint256 i = start; i < end; i = LlamaUtils.uncheckedIncrement(i)) {
      checkpoints[i - start] = quorumCheckpoints._checkpoints[i];
    }
    return QuorumCheckpoints.History(checkpoints);
  }

  /// @notice Returns the current delay, casting and submission period ratio.
  function getPeriodPcts()
    external
    view
    returns (uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct)
  {
    return periodPctsCheckpoint.latest();
  }

  /// @notice Returns the delay, casting and submission period ratio at a given timestamp.
  function getPastPeriodPcts(uint256 timestamp)
    external
    view
    returns (uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct)
  {
    return periodPctsCheckpoint.getAtProbablyRecentTimestamp(timestamp);
  }

  /// @notice Returns all period pct checkpoints.
  function getPeriodPctCheckpoints() external view returns (PeriodPctCheckpoints.History memory) {
    return periodPctsCheckpoint;
  }

  /// @notice Returns the period pct checkpoints array from a given set of indices.
  function getPeriodPctCheckpoints(uint256 start, uint256 end)
    external
    view
    returns (PeriodPctCheckpoints.History memory)
  {
    if (start > end) revert InvalidIndices();
    uint256 checkpointsLength = periodPctsCheckpoint._checkpoints.length;
    if (end > checkpointsLength) revert InvalidIndices();

    uint256 sliceLength = end - start;
    PeriodPctCheckpoints.Checkpoint[] memory checkpoints = new PeriodPctCheckpoints.Checkpoint[](sliceLength);
    for (uint256 i = start; i < end; i = LlamaUtils.uncheckedIncrement(i)) {
      checkpoints[i - start] = periodPctsCheckpoint._checkpoints[i];
    }
    return PeriodPctCheckpoints.History(checkpoints);
  }

  // ================================
  // ======== Internal Logic ========
  // ================================

  /// @dev How token holders add their support of the approval of an action with a reason.
  function _castVote(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason)
    internal
    returns (uint96)
  {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfApprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (llamaCore.getActionState(actionInfo) != uint8(ActionState.Active)) revert ActionNotActive();
    if (casts[actionInfo.id].castVote[caster]) revert AlreadyCastedVote();
    _preCastAssertions(support);

    // Checks to ensure it's the casting period.
    (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
      periodPctsCheckpoint.getAtProbablyRecentTimestamp(action.creationTime - 1);
    uint256 approvalPeriod = actionInfo.strategy.approvalPeriod();
    uint256 delayPeriodEndTime = action.creationTime + ((approvalPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((approvalPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
    if (block.timestamp <= delayPeriodEndTime) revert VotingDelayNotOver();
    if (block.timestamp > castingPeriodEndTime) revert CastingPeriodOver();

    uint96 weight =
      LlamaUtils.toUint96(tokenAdapter.getPastVotes(caster, tokenAdapter.timestampToTimepoint(delayPeriodEndTime)));

    if (support == uint8(VoteType.Against)) casts[actionInfo.id].votesAgainst += weight;
    else if (support == uint8(VoteType.For)) casts[actionInfo.id].votesFor += weight;
    else if (support == uint8(VoteType.Abstain)) casts[actionInfo.id].votesAbstain += weight;
    casts[actionInfo.id].castVote[caster] = true;

    emit VoteCast(actionInfo.id, caster, support, weight, reason);
    return weight;
  }

  /// @dev How token holders add their support of the disapproval of an action with a reason.
  function _castVeto(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason)
    internal
    returns (uint96)
  {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (llamaCore.getActionState(actionInfo) != uint8(ActionState.Queued)) revert ActionNotQueued();
    if (casts[actionInfo.id].castVeto[caster]) revert AlreadyCastedVeto();
    _preCastAssertions(support);

    // Checks to ensure it's the casting period.
    (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
      periodPctsCheckpoint.getAtProbablyRecentTimestamp(action.creationTime - 1);
    uint256 queuingPeriod = actionInfo.strategy.queuingPeriod();
    uint256 delayPeriodEndTime =
      (action.minExecutionTime - queuingPeriod) + ((queuingPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((queuingPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
    if (block.timestamp <= delayPeriodEndTime) revert VotingDelayNotOver();
    if (block.timestamp > castingPeriodEndTime) revert CastingPeriodOver();

    uint96 weight =
      LlamaUtils.toUint96(tokenAdapter.getPastVotes(caster, tokenAdapter.timestampToTimepoint(delayPeriodEndTime)));

    if (support == uint8(VoteType.Against)) casts[actionInfo.id].vetoesAgainst += weight;
    else if (support == uint8(VoteType.For)) casts[actionInfo.id].vetoesFor += weight;
    else if (support == uint8(VoteType.Abstain)) casts[actionInfo.id].vetoesAbstain += weight;
    casts[actionInfo.id].castVeto[caster] = true;

    emit VetoCast(actionInfo.id, caster, support, weight, reason);
    return weight;
  }

  /// @dev The only `support` values allowed to be passed into this method are Against (0), For (1) or Abstain (2).
  function _preCastAssertions(uint8 support) internal view {
    if (support > uint8(VoteType.Abstain)) revert InvalidSupport(support);

    // Reverts if clock or CLOCK_MODE() has changed
    tokenAdapter.checkIfInconsistentClock();
  }

  /// @dev Sets the voting quorum and vetoing quorum.
  function _setQuorumPct(uint16 _voteQuorumPct, uint16 _vetoQuorumPct) internal {
    if (_voteQuorumPct > ONE_HUNDRED_IN_BPS || _voteQuorumPct <= 0) revert InvalidVoteQuorumPct(_voteQuorumPct);
    if (_vetoQuorumPct > ONE_HUNDRED_IN_BPS || _vetoQuorumPct <= 0) revert InvalidVetoQuorumPct(_vetoQuorumPct);
    quorumCheckpoints.push(_voteQuorumPct, _vetoQuorumPct);
    emit QuorumPctSet(_voteQuorumPct, _vetoQuorumPct);
  }

  /// @dev Sets the delay, casting and submission period ratio.
  function _setPeriodPct(uint16 _delayPeriodPct, uint16 _castingPeriodPct, uint16 _submissionPeriodPct) internal {
    if (_delayPeriodPct + _castingPeriodPct + _submissionPeriodPct != ONE_HUNDRED_IN_BPS) {
      revert InvalidPeriodPcts(_delayPeriodPct, _castingPeriodPct, _submissionPeriodPct);
    }
    periodPctsCheckpoint.push(_delayPeriodPct, _castingPeriodPct, _submissionPeriodPct);
    emit PeriodPctSet(_delayPeriodPct, _castingPeriodPct, _submissionPeriodPct);
  }

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
    ActionInfo calldata actionInfo,
    uint8 support,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castVoteHash = keccak256(
      abi.encode(
        CAST_VOTE_TYPEHASH,
        tokenholder,
        _getActionInfoHash(actionInfo),
        support,
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
    ActionInfo calldata actionInfo,
    uint8 support,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castVetoHash = keccak256(
      abi.encode(
        CAST_VETO_TYPEHASH,
        tokenholder,
        _getActionInfoHash(actionInfo),
        support,
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

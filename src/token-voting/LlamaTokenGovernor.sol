// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {ActionState, VoteType} from "src/lib/Enums.sol";
import {Action, ActionInfo, CasterConfig} from "src/lib/Structs.sol";
import {LlamaUtils} from "src/lib/LlamaUtils.sol";
import {PeriodPctCheckpoints} from "src/lib/PeriodPctCheckpoints.sol";
import {QuorumCheckpoints} from "src/lib/QuorumCheckpoints.sol";

/// @title LlamaTokenGovernor
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance token create actions if they have a
/// sufficient token balance and collectively cast an approval or disapproval on created actions.
/// @dev This contract is deployed by `LlamaTokenVotingFactory`. Anyone can deploy this contract using the factory, but
/// it must hold a Policy from the specified `LlamaCore` instance to actually be able to create and cast on an action.
contract LlamaTokenGovernor is Initializable {
  using PeriodPctCheckpoints for PeriodPctCheckpoints.History;
  using QuorumCheckpoints for QuorumCheckpoints.History;
  // =========================
  // ======== Structs ========
  // =========================

  /// @dev Cast counts and submission data.
  struct CastData {
    uint128 votesFor; // Number of votes casted for this action.
    uint128 votesAbstain; // Number of abstentions casted for this action.
    uint128 votesAgainst; // Number of votes casted against this action.
    uint128 vetoesFor; // Number of vetoes casted for this action.
    uint128 vetoesAbstain; // Number of abstentions casted for this action.
    uint128 vetoesAgainst; // Number of disapprovals casted against this action.
    mapping(address tokenholder => bool) castVote; // True if tokenholder casted a vote, false otherwise.
    mapping(address tokenholder => bool) castVeto; // True if tokenholder casted a veto, false otherwise.
  }

  // ======================================
  // ======== Errors and Modifiers ========
  // ======================================

  /// @dev Thrown when a user tries to submit (dis)approval but the casting period has not ended.
  error CastingPeriodNotOver();

  /// @dev Thrown when a user tries to cast a vote or veto but the casting period has ended.
  error CastingPeriodOver();

  /// @dev Thrown when a user tries to cast a vote or veto but the delay period has not ended.
  error DelayPeriodNotOver();

  /// @dev Token holders can only cast once.
  error DuplicateCast();

  /// @dev Thrown when a user tries to cast a vote or veto but the against surpasses for.
  error ForDoesNotSurpassAgainst(uint256 castsFor, uint256 castsAgainst);

  /// @dev Thrown when a user tries to create an action but does not have enough tokens.
  error InsufficientBalance(uint256 balance);

  /// @dev Thrown when a user tries to submit an approval but there are not enough votes.
  error InsufficientVotes(uint256 votes, uint256 threshold);

  /// @dev The action is not in the expected state.
  /// @param current The current state of the action.
  error InvalidActionState(ActionState current);

  /// @dev Thrown when an invalid `creationThreshold` is passed to the constructor.
  error InvalidCreationThreshold();

  /// @dev The indices would result in `Panic: Index Out of Bounds`.
  /// @dev Thrown when the `end` index is greater than array length or when the `start` index is greater than the `end`
  /// index.
  error InvalidIndices();

  /// @dev Thrown when an invalid `llamaCore` address is passed to the constructor.
  error InvalidLlamaCoreAddress();

  /// @dev Thrown when an invalid `castingPeriodPct` and `submissionPeriodPct` are set.
  error InvalidPeriodPcts(uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct);

  /// @dev This token caster contract does not have the defined role at action creation time.
  error InvalidPolicyholder();

  /// @dev The recovered signer does not match the expected tokenholder.
  error InvalidSignature();

  /// @dev Thrown when an invalid `support` value is used when casting.
  error InvalidSupport(uint8 support);

  /// @dev Thrown when a `token` with an invalid totaly supply is passed to the constructor.
  error InvalidTotalSupply();

  /// @dev Thrown when an invalid `vetoQuorumPct` is passed to the constructor.
  error InvalidVetoQuorumPct(uint16 vetoQuorumPct);

  /// @dev Thrown when an invalid `voteQuorumPct` is passed to the constructor.
  error InvalidVoteQuorumPct(uint16 voteQuorumPct);

  /// @dev Thrown when a user tries to cancel an action but they are not the action creator.
  error OnlyActionCreator();

  /// @dev Thrown when an address other than the `LlamaExecutor` tries to call a function.
  error OnlyLlamaExecutor();

  /// @dev Thrown when an invalid `role` is passed to the constructor.
  error RoleNotInitialized(uint8 role);

  /// @dev Thrown when a user tries to submit (dis)approval but the submission period has ended.
  error SubmissionPeriodOver();

  /// @dev Checks that the caller is the Llama Executor and reverts if not.
  modifier onlyLlama() {
    if (msg.sender != address(llamaCore.executor())) revert OnlyLlamaExecutor();
    _;
  }

  // ========================
  // ======== Events ========
  // ========================

  /// @dev Emitted when an action is canceled.
  event ActionCanceled(uint256 id, address indexed creator);

  /// @dev Emitted when an action is created.
  event ActionCreated(uint256 id, address indexed creator);

  /// @dev Emitted when the default number of tokens required to create an action is changed.
  event ActionThresholdSet(uint256 newThreshold);

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

  /// @dev EIP-712 createAction typehash.
  bytes32 internal constant CREATE_ACTION_TYPEHASH = keccak256(
    "CreateAction(address tokenHolder,address strategy,address target,uint256 value,bytes data,string description,uint256 nonce)"
  );

  /// @dev EIP-712 cancelAction typehash.
  bytes32 internal constant CANCEL_ACTION_TYPEHASH = keccak256(
    "CancelAction(address tokenHolder,ActionInfo actionInfo,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

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

  /// @notice The contract that manages the timepoints for this token voting module.
  ILlamaTokenAdapter public tokenAdapter;

  /// @notice The role used by this contract to create actions and cast approvals and disapprovals.
  /// @dev This role is expected to have the ability to create actions and force approve and disapprove actions.
  uint8 public role;

  /// @notice The number of tokens required to create an action.
  uint256 public creationThreshold;

  /// @dev The quorum checkpoints for this token voting module.
  QuorumCheckpoints.History internal quorumCheckpoints;

  /// @dev The period pct checkpoints for this token voting module.
  PeriodPctCheckpoints.History internal periodPctsCheckpoint;

  /// @notice The address of the tokenholder that created the action.
  mapping(uint256 => address) public actionCreators;

  /// @notice Mapping from action ID to the status of existing casts.
  mapping(uint256 actionId => CastData) public casts;

  /// @notice Mapping of tokenholders to function selectors to current nonces for EIP-712 signatures.
  /// @dev This is used to prevent replay attacks by incrementing the nonce for each operation (`castVote`,
  /// `createAction`, `cancelAction`, and `castVeto`) signed by the tokenholders.
  mapping(address tokenholders => mapping(bytes4 selector => uint256 currentNonce)) public nonces;

  // ================================
  // ======== Initialization ========
  // ================================

  /// @dev This contract is deployed as a minimal proxy from the factory's `deploy` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaTokenGovernor clone.
  /// @dev This function is called by the `deploy` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _tokenAdapter The token adapter that manages the clock, timepoints, past votes and past supply for this
  /// token voting module.
  /// @param _role The role used by this contract to create actions and cast approvals and disapprovals.
  /// @param _creationThreshold The default number of tokens required to create an action. This must
  /// be in the same decimals as the token. For example, if the token has 18 decimals and you want a
  /// creation threshold of 1000 tokens, pass in 1000e18.
  /// @param casterConfig Contains the quorum and period pct values to initialize the contract with.
  function initialize(
    ILlamaCore _llamaCore,
    ILlamaTokenAdapter _tokenAdapter,
    uint8 _role,
    uint256 _creationThreshold,
    CasterConfig memory casterConfig
  ) external initializer {
    // This check insures that:
    // 1. _llamaCore is not the zero address (otherwise it would revert).
    // 2. By duck testing the actionsCount method we can be relatively sure that it is a LlamaCore contract.
    if (!(_llamaCore.actionsCount() >= 0)) revert InvalidLlamaCoreAddress();
    if (_role > _llamaCore.policy().numRoles()) revert RoleNotInitialized(_role);

    llamaCore = _llamaCore;
    tokenAdapter = _tokenAdapter;
    role = _role;
    _setActionThreshold(_creationThreshold);
    _setQuorumPct(casterConfig.voteQuorumPct, casterConfig.vetoQuorumPct);
    _setPeriodPct(casterConfig.delayPeriodPct, casterConfig.castingPeriodPct, casterConfig.submissionPeriodPct);
  }

  // ===========================================
  // ======== External and Public Logic ========
  // ===========================================

  // -------- Action Creation Lifecycle Management --------

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
    string calldata description
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
    string calldata description,
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

  // -------- Action Casting Lifecycle Management --------

  /// @notice How tokenholders add their support of the approval of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the approval of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain
  /// @param reason The reason given for the approval by the tokenholder.
  /// @return The weight of the cast.
  function castVote(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external returns (uint128) {
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
  ) external returns (uint128) {
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
  function castVeto(ActionInfo calldata actionInfo, uint8 support, string calldata reason) external returns (uint128) {
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
  ) external returns (uint128) {
    bytes32 digest = _getCastVetoTypedDataHash(caster, actionInfo, support, reason);
    address signer = ecrecover(digest, v, r, s);
    if (signer == address(0) || signer != caster) revert InvalidSignature();
    return _castVeto(signer, actionInfo, support, reason);
  }

  /// @notice Submits a cast approval to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev This function can be called by anyone.
  function submitApproval(ActionInfo calldata actionInfo) external {
    Action memory action = llamaCore.getAction(actionInfo.id);
    uint256 checkpointTime = action.creationTime - 1;

    // Reverts if clock or CLOCK_MODE() has changed
    tokenAdapter.checkIfInconsistentClock();

    uint256 delayPeriodEndTime;
    uint256 castingPeriodEndTime;
    // Scoping to prevent stack too deep errors.
    {
      // Checks to ensure it's the submission period.
      (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
        periodPctsCheckpoint.getAtProbablyRecentTimestamp(checkpointTime);
      uint256 approvalPeriod = actionInfo.strategy.approvalPeriod();
      unchecked {
        delayPeriodEndTime = action.creationTime + ((approvalPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
        castingPeriodEndTime = delayPeriodEndTime + ((approvalPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
      }
      if (block.timestamp <= castingPeriodEndTime) revert CastingPeriodNotOver();
      // Doing (action.creationTime + approvalPeriod) vs (castingPeriodEndTime + ((approvalPeriod * submissionPeriodPct)
      // / ONE_HUNDRED_IN_BPS)) to prevent any off-by-one errors due to precision loss.
      // Llama approval period is inclusive of approval end time.
      if (block.timestamp > action.creationTime + approvalPeriod) revert SubmissionPeriodOver();
    }

    CastData storage castData = casts[actionInfo.id];

    uint256 totalSupply = tokenAdapter.getPastTotalSupply(tokenAdapter.timestampToTimepoint(delayPeriodEndTime));
    uint128 votesFor = castData.votesFor;
    uint128 votesAgainst = castData.votesAgainst;
    uint128 votesAbstain = castData.votesAbstain;
    (uint16 voteQuorumPct,) = quorumCheckpoints.getAtProbablyRecentTimestamp(checkpointTime);
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, voteQuorumPct, ONE_HUNDRED_IN_BPS);
    if (votesFor < threshold) revert InsufficientVotes(votesFor, threshold);
    if (votesFor <= votesAgainst) revert ForDoesNotSurpassAgainst(votesFor, votesAgainst);

    llamaCore.castApproval(role, actionInfo, "");
    emit ApprovalSubmitted(actionInfo.id, msg.sender, votesFor, votesAgainst, votesAbstain);
  }

  /// @notice Submits a cast disapproval to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev This function can be called by anyone.
  function submitDisapproval(ActionInfo calldata actionInfo) external {
    Action memory action = llamaCore.getAction(actionInfo.id);
    uint256 checkpointTime = action.creationTime - 1;

    // Reverts if clock or CLOCK_MODE() has changed
    tokenAdapter.checkIfInconsistentClock();

    uint256 delayPeriodEndTime;
    uint256 castingPeriodEndTime;
    // Scoping to prevent stack too deep errors.
    {
      // Checks to ensure it's the submission period.
      (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
        periodPctsCheckpoint.getAtProbablyRecentTimestamp(checkpointTime);
      uint256 queuingPeriod = actionInfo.strategy.queuingPeriod();
      unchecked {
        delayPeriodEndTime =
          (action.minExecutionTime - queuingPeriod) + ((queuingPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
        castingPeriodEndTime = delayPeriodEndTime + ((queuingPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
      }
      // Doing (castingPeriodEndTime) vs (action.minExecutionTime - ((queuingPeriod * submissionPeriodPct) /
      // ONE_HUNDRED_IN_BPS)) to prevent any off-by-one errors due to precision loss.
      if (block.timestamp <= castingPeriodEndTime) revert CastingPeriodNotOver();
      // Llama disapproval period is exclusive of min execution time.
      if (block.timestamp >= action.minExecutionTime) revert SubmissionPeriodOver();
    }

    CastData storage castData = casts[actionInfo.id];

    uint256 totalSupply = tokenAdapter.getPastTotalSupply(tokenAdapter.timestampToTimepoint(delayPeriodEndTime));
    uint128 vetoesFor = castData.vetoesFor;
    uint128 vetoesAgainst = castData.vetoesAgainst;
    uint128 vetoesAbstain = castData.vetoesAbstain;
    (, uint16 vetoQuorumPct) = quorumCheckpoints.getAtProbablyRecentTimestamp(checkpointTime);
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, vetoQuorumPct, ONE_HUNDRED_IN_BPS);
    if (vetoesFor < threshold) revert InsufficientVotes(vetoesFor, threshold);
    if (vetoesFor <= vetoesAgainst) revert ForDoesNotSurpassAgainst(vetoesFor, vetoesAgainst);

    llamaCore.castDisapproval(role, actionInfo, "");
    emit DisapprovalSubmitted(actionInfo.id, msg.sender, vetoesFor, vetoesAgainst, vetoesAbstain);
  }

  // -------- Instance Management --------

  /// @notice Sets the default number of tokens required to create an action.
  /// @param _creationThreshold The number of tokens required to create an action.
  /// @dev This must be in the same decimals as the token.
  function setActionThreshold(uint256 _creationThreshold) external onlyLlama {
    _setActionThreshold(_creationThreshold);
  }

  /// @notice Sets the voting quorum and vetoing quorum.
  /// @param _voteQuorumPct The minimum % of votes required to submit an approval to `LlamaCore`.
  /// @param _vetoQuorumPct The minimum % of vetoes required to submit a disapproval to `LlamaCore`.
  function setQuorumPct(uint16 _voteQuorumPct, uint16 _vetoQuorumPct) external onlyLlama {
    _setQuorumPct(_voteQuorumPct, _vetoQuorumPct);
  }

  /// @notice Sets the delay period, casting period and submission period.
  /// @param _delayPeriodPct The % of the total period that must pass before voting can begin.
  /// @param _castingPeriodPct The % of the total period that voting can occur.
  /// @param _submissionPeriodPct The % of the total period withing which the (dis)approval must be submitted.
  function setPeriodPct(uint16 _delayPeriodPct, uint16 _castingPeriodPct, uint16 _submissionPeriodPct)
    external
    onlyLlama
  {
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

  /// @notice Returns if a token holder has cast (vote or veto) yet for a given action.
  /// @param actionId ID of the action.
  /// @param tokenholder The tokenholder to check.
  /// @param isVote `true` if checking for a vote, `false` if checking for a veto.
  function hasTokenHolderCast(uint256 actionId, address tokenholder, bool isVote) external view returns (bool) {
    if (isVote) return casts[actionId].castVote[tokenholder];
    else return casts[actionId].castVeto[tokenholder];
  }

  /// @notice Returns the current voting quorum and vetoing quorum.
  function getQuorum() external view returns (uint16, uint16) {
    return quorumCheckpoints.latest();
  }

  /// @notice Returns the voting quorum and vetoing quorum at a given timestamp.
  /// @param timestamp The timestamp to get the quorum at.
  function getPastQuorum(uint256 timestamp) external view returns (uint16, uint16) {
    return quorumCheckpoints.getAtProbablyRecentTimestamp(timestamp);
  }

  /// @notice Returns all quorum checkpoints.
  function getQuorumCheckpoints() external view returns (QuorumCheckpoints.History memory) {
    return quorumCheckpoints;
  }

  /// @notice Returns the quorum checkpoints array from a given set of indices.
  /// @param start Start index of the checkpoints to get from their checkpoint history array. This index is inclusive.
  /// @param end End index of the checkpoints to get from their checkpoint history array. This index is exclusive.
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
  function getPeriodPcts() external view returns (uint16, uint16, uint16) {
    return periodPctsCheckpoint.latest();
  }

  /// @notice Returns the delay, casting and submission period ratio at a given timestamp.
  /// @param timestamp The timestamp to get the period pcts at.
  function getPastPeriodPcts(uint256 timestamp) external view returns (uint16, uint16, uint16) {
    return periodPctsCheckpoint.getAtProbablyRecentTimestamp(timestamp);
  }

  /// @notice Returns all period pct checkpoints.
  function getPeriodPctCheckpoints() external view returns (PeriodPctCheckpoints.History memory) {
    return periodPctsCheckpoint;
  }

  /// @notice Returns the period pct checkpoints array from a given set of indices.
  /// @param start Start index of the checkpoints to get from their checkpoint history array. This index is inclusive.
  /// @param end End index of the checkpoints to get from their checkpoint history array. This index is exclusive.
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

  // -------- Action Creation Internal Functions --------

  /// @dev Creates an action. The creator needs to have sufficient token balance.
  function _createAction(
    address tokenHolder,
    ILlamaStrategy strategy,
    address target,
    uint256 value,
    bytes calldata data,
    string calldata description
  ) internal returns (uint256 actionId) {
    // Reverts if clock or CLOCK_MODE() has changed
    tokenAdapter.checkIfInconsistentClock();

    uint256 balance = tokenAdapter.getPastVotes(tokenHolder, tokenAdapter.clock() - 1);
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

  // -------- Action Casting Internal Functions --------

  /// @dev How token holders add their support of the approval of an action with a reason.
  function _castVote(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason)
    internal
    returns (uint128)
  {
    Action memory action = llamaCore.getAction(actionInfo.id);
    uint256 checkpointTime = action.creationTime - 1;

    CastData storage castData = casts[actionInfo.id];

    actionInfo.strategy.checkIfApprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (castData.castVote[caster]) revert DuplicateCast();
    _preCastAssertions(actionInfo, support, ActionState.Active, checkpointTime);

    uint256 delayPeriodEndTime;
    uint256 castingPeriodEndTime;
    // Scoping to prevent stack too deep errors.
    {
      // Checks to ensure it's the casting period.
      (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
        periodPctsCheckpoint.getAtProbablyRecentTimestamp(checkpointTime);
      uint256 approvalPeriod = actionInfo.strategy.approvalPeriod();
      unchecked {
        delayPeriodEndTime = action.creationTime + ((approvalPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
        castingPeriodEndTime = delayPeriodEndTime + ((approvalPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
      }
      if (block.timestamp <= delayPeriodEndTime) revert DelayPeriodNotOver();
      if (block.timestamp > castingPeriodEndTime) revert CastingPeriodOver();
    }

    uint128 weight =
      LlamaUtils.toUint128(tokenAdapter.getPastVotes(caster, tokenAdapter.timestampToTimepoint(delayPeriodEndTime)));

    if (support == uint8(VoteType.Against)) castData.votesAgainst = _newCastCount(castData.votesAgainst, weight);
    else if (support == uint8(VoteType.For)) castData.votesFor = _newCastCount(castData.votesFor, weight);
    else if (support == uint8(VoteType.Abstain)) castData.votesAbstain = _newCastCount(castData.votesAbstain, weight);
    castData.castVote[caster] = true;

    emit VoteCast(actionInfo.id, caster, support, weight, reason);
    return weight;
  }

  /// @dev How token holders add their support of the disapproval of an action with a reason.
  function _castVeto(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason)
    internal
    returns (uint128)
  {
    Action memory action = llamaCore.getAction(actionInfo.id);
    uint256 checkpointTime = action.creationTime - 1;

    CastData storage castData = casts[actionInfo.id];

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, address(this), role); // Reverts if not allowed.
    if (castData.castVeto[caster]) revert DuplicateCast();
    _preCastAssertions(actionInfo, support, ActionState.Queued, checkpointTime);

    uint256 delayPeriodEndTime;
    uint256 castingPeriodEndTime;
    // Scoping to prevent stack too deep errors.
    {
      // Checks to ensure it's the casting period.
      (uint16 delayPeriodPct, uint16 castingPeriodPct,) =
        periodPctsCheckpoint.getAtProbablyRecentTimestamp(checkpointTime);
      uint256 queuingPeriod = actionInfo.strategy.queuingPeriod();
      unchecked {
        delayPeriodEndTime =
          (action.minExecutionTime - queuingPeriod) + ((queuingPeriod * delayPeriodPct) / ONE_HUNDRED_IN_BPS);
        castingPeriodEndTime = delayPeriodEndTime + ((queuingPeriod * castingPeriodPct) / ONE_HUNDRED_IN_BPS);
      }
      if (block.timestamp <= delayPeriodEndTime) revert DelayPeriodNotOver();
      if (block.timestamp > castingPeriodEndTime) revert CastingPeriodOver();
    }

    uint128 weight =
      LlamaUtils.toUint128(tokenAdapter.getPastVotes(caster, tokenAdapter.timestampToTimepoint(delayPeriodEndTime)));

    if (support == uint8(VoteType.Against)) castData.vetoesAgainst = _newCastCount(castData.vetoesAgainst, weight);
    else if (support == uint8(VoteType.For)) castData.vetoesFor = _newCastCount(castData.vetoesFor, weight);
    else if (support == uint8(VoteType.Abstain)) castData.vetoesAbstain = _newCastCount(castData.vetoesAbstain, weight);
    castData.castVeto[caster] = true;

    emit VetoCast(actionInfo.id, caster, support, weight, reason);
    return weight;
  }

  /// @dev The only `support` values allowed to be passed into this method are Against (0), For (1) or Abstain (2).
  function _preCastAssertions(
    ActionInfo calldata actionInfo,
    uint8 support,
    ActionState expectedState,
    uint256 checkpointTime
  ) internal view {
    if (support > uint8(VoteType.Abstain)) revert InvalidSupport(support);

    ActionState currentState = ActionState(llamaCore.getActionState(actionInfo));
    if (currentState != expectedState) revert InvalidActionState(currentState);

    bool hasRole = llamaCore.policy().hasRole(address(this), role, checkpointTime);
    if (!hasRole) revert InvalidPolicyholder();

    // Reverts if clock or CLOCK_MODE() has changed
    tokenAdapter.checkIfInconsistentClock();
  }

  /// @dev Returns the new total count of votes or vetoes in Against (0), For (1) or Abstain (2).
  function _newCastCount(uint128 currentCount, uint128 weight) internal pure returns (uint128) {
    if (uint256(currentCount) + weight >= type(uint128).max) return type(uint128).max;
    return currentCount + weight;
  }

  // -------- Instance Management Internal Functions --------

  /// @dev Sets the default number of tokens required to create an action.
  function _setActionThreshold(uint256 _creationThreshold) internal {
    uint256 totalSupply = tokenAdapter.getPastTotalSupply(tokenAdapter.clock() - 1);
    if (totalSupply == 0) revert InvalidTotalSupply();
    if (_creationThreshold > totalSupply) revert InvalidCreationThreshold();
    creationThreshold = _creationThreshold;
    emit ActionThresholdSet(_creationThreshold);
  }

  /// @dev Sets the voting quorum and vetoing quorum.
  function _setQuorumPct(uint16 _voteQuorumPct, uint16 _vetoQuorumPct) internal {
    if (_voteQuorumPct > ONE_HUNDRED_IN_BPS || _voteQuorumPct == 0) revert InvalidVoteQuorumPct(_voteQuorumPct);
    if (_vetoQuorumPct > ONE_HUNDRED_IN_BPS || _vetoQuorumPct == 0) revert InvalidVetoQuorumPct(_vetoQuorumPct);
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

  // -------- User Nonce Management Internal Functions --------

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
    string calldata description
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

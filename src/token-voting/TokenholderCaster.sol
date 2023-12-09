// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ActionState} from "src/lib/Enums.sol";
import {LlamaUtils} from "src/lib/LlamaUtils.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {ILlamaRelativeStrategyBase} from "src/interfaces/ILlamaRelativeStrategyBase.sol";

/// @title TokenholderCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance token cast votes and vetos
/// on created actions.
/// @dev This contract is deployed by `LlamaTokenVotingFactory`. Anyone can deploy this contract using the factory, but
/// it must hold a Policy from the specified `LlamaCore` instance to actually be able to cast on an action. This
/// contract does not verify that it holds the correct policy when voting and relies on `LlamaCore` to
/// verify that during submission.
abstract contract TokenholderCaster is Initializable {
  // =========================
  // ======== Structs ========
  // =========================

  /// @dev Cast counts and submission data.
  struct CastData {
    uint96 votesFor; // Number of votes casted for this action. This is the standard approval in `LlamaCore`.
    uint96 votesAbstain; // Number of abstentions casted for this action. This does not exist in `LlamaCore`.
    uint96 votesAgainst; // Number of votes casted against this action. This does not exist in `LlamaCore`.
    bool voteSubmitted; // True if the votes have been submitted to `LlamaCore, false otherwise.
    uint96 vetosFor; // Number of vetos casted for this action. This is the standard disapproval in
      // `LlamaCore`.
    uint96 vetosAbstain; // Number of abstentions casted for this action. This does not exist in `LlamaCore`.
    uint96 vetosAgainst; // Number of vetos casted against this action. This does not exist in
      // `LlamaCore`.
    bool vetoSubmitted; // True if the vetos have been submitted to `LlamaCore`, false otherwise.
    mapping(address tokenholder => bool) castVote; // True if tokenholder casted vote, false otherwise.
    mapping(address tokenholder => bool) castVeto; // True if tokenholder casted veto, false otherwise.
  }

  // ========================
  // ======== Errors ========
  // ========================

  /// @dev Thrown when a user tries to cast vote but the action has expired.
  error ActionExpired();

  /// @dev Thrown when a user tries to cast vote but the action is not active.
  error ActionNotActive();

  /// @dev Thrown when a user tries to cast veto but but the action is not approved.
  error ActionNotApproved();

  /// @dev Thrown when a user tries to cast vote but has already casted.
  error AlreadyCastVote();

  /// @dev Thrown when a user tries to cast vote but the casts have already been submitted to `LlamaCore`.
  error AlreadySubmittedVote();

  /// @dev Thrown when a user tries to cast veto but has already casted.
  error AlreadyCastVeto();

  /// @dev Thrown when a user tries to cast veto but the casts have already been submitted to `LlamaCore.
  error AlreadySubmittedVeto();

  /// @dev Thrown when a user tries to cast vote/veto but the casting period has ended.
  error CastingPeriodOver();

  /// @dev Thrown when a user tries to cast vote/veto but the action cannot be submitted yet.
  error CantSubmitYet();

  /// @dev Thrown when a user tries to create an action but the clock mode is not supported.
  error ClockModeNotSupported(string clockMode);

  /// @dev Thrown when a user tries to cast vote/veto but the vote/vetos surpass the votes.
  error ForDoesNotSurpassAgainst(uint256 votes, uint256 vetos);

  /// @dev Thrown when a user tries to submit votes but there are not enough votes.
  error InsufficientVotes(uint256 votes, uint256 threshold);

  /// @dev Thrown when a user tries to cast but does not have enough tokens.
  error InsufficientBalance(uint256 balance);

  /// @dev Thrown when an invalid `voteQuorum` is passed to the constructor.
  error InvalidVoteQuorum(uint256 approvalThreshold);

  /// @dev Thrown when an invalid `vetoThreshold` is passed to the constructor.
  error InvalidVetoQuorum(uint256 vetoThreshold);

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

  /// @dev Thrown when a user tries to submit vote/veto but the submission period has ended.
  error SubmissionPeriodOver();

  // ========================
  // ======== Events ========
  // ========================

  /// @dev Emitted when a vote is cast.
  /// @dev This is almost the same as the `VoteCast` event from `LlamaCore`, with the addition of the support field.
  /// The two events will be nearly identical, with the `tokenholder` being the main difference. This version will emit
  /// the address of the tokenholder that casted, while the `LlamaCore` version will emit the address of this contract
  /// as the action creator. Additionally, there is no `role` emitted here as all tokenholders are eligible to vote.
  event VoteCast(
    uint256 id, address indexed tokenholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  /// @dev Emitted when cast votes are submitted to the `LlamaCore` contract.
  event VotesSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  /// @dev Emitted when a veto is cast.
  /// @dev This is the same as the `VetoCast` event from `LlamaCore`. The two events will be
  /// nearly identical, with the `tokenholder` being the only difference. This version will emit
  /// the address of the tokenholder that casted, while the `LlamaCore` version will emit the
  /// address of this contract as the action creator.
  event VetoCast(
    uint256 id, address indexed tokenholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  /// @dev Emitted when cast votes are submitted to the `LlamaCore` contract.
  event VetosSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);
  // =================================================
  // ======== Constants and Storage Variables ========
  // =================================================

  /// @dev Equivalent to 100%, but in basis points.
  uint256 internal constant ONE_HUNDRED_IN_BPS = 10_000;

  uint256 internal constant ONE_THIRD_IN_BPS = 3333;
  uint256 internal constant TWO_THIRDS_IN_BPS = 6667;

  /// @notice The core contract for this Llama instance.
  ILlamaCore public llamaCore;

  /// @notice The minimum % of votes required to submit votes to `LlamaCore`.
  uint256 public voteQuorum;

  /// @notice The minimum % of vetos required to submit vetos to `LlamaCore`.
  uint256 public vetoQuorum;

  /// @notice The role used by this contract to cast votes and vetos.
  /// @dev This role is expected to have the ability to force approve and disapprove actions.
  uint8 public role;

  /// @dev EIP-712 base typehash.
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @notice EIP-712 castVote typehash.
  bytes32 internal constant CAST_VOTE_BY_SIG_TYPEHASH = keccak256(
    "CastVote(address tokenHolder,uint8 support,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice EIP-712 castVeto typehash.
  bytes32 internal constant CAST_VETO_BY_SIG_TYPEHASH = keccak256(
    "CastVeto(address tokenHolder,uint8 role,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @dev EIP-712 actionInfo typehash.
  bytes32 internal constant ACTION_INFO_TYPEHASH = keccak256(
    "ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice Mapping from action ID to the status of existing casts.
  mapping(uint256 actionId => CastData) public casts;

  /// @notice Mapping of tokenholders to function selectors to current nonces for EIP-712 signatures.
  /// @dev This is used to prevent replay attacks by incrementing the nonce for each operation (`createAction`,
  /// `cancelAction`, `castVote` and `castVeto`) signed by the tokenholders.
  mapping(address tokenholders => mapping(bytes4 selector => uint256 currentNonce)) public nonces;

  /// @dev This will be called by the `initialize` of the inheriting contract.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast votes and vetos.
  /// @param _voteQuorum The minimum % of votes required to submit votes to `LlamaCore`.
  /// @param _vetoQuorum The minimum % of vetos required to submit vetos to `LlamaCore`.
  function __initializeTokenholderCasterMinimalProxy(
    ILlamaCore _llamaCore,
    uint8 _role,
    uint256 _voteQuorum,
    uint256 _vetoQuorum
  ) internal {
    if (_llamaCore.actionsCount() < 0) revert InvalidLlamaCoreAddress();
    if (_role > _llamaCore.policy().numRoles()) revert RoleNotInitialized(_role);
    if (_voteQuorum > ONE_HUNDRED_IN_BPS || _voteQuorum <= 0) revert InvalidVoteQuorum(_voteQuorum);
    if (_vetoQuorum > ONE_HUNDRED_IN_BPS || _vetoQuorum <= 0) revert InvalidVetoQuorum(_vetoQuorum);

    llamaCore = _llamaCore;
    role = _role;
    voteQuorum = _voteQuorum;
    vetoQuorum = _vetoQuorum;
  }

  /// @notice How tokenholders add their support to the vote of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the vote of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain, but this is not currently supported.
  /// @param reason The reason given for the vote by the tokenholder.
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

  /// @notice How tokenholders add their support to the veto of an action with a reason.
  /// @dev Use `""` for `reason` if there is no reason.
  /// @param actionInfo Data required to create an action.
  /// @param support The tokenholder's support of the veto of the action.
  ///   0 = Against
  ///   1 = For
  ///   2 = Abstain, but this is not currently supported.
  /// @param reason The reason given for the veto by the tokenholder.
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

  /// @notice Submits cast votes to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev this function can be called by anyone
  function submitVotes(ActionInfo calldata actionInfo) external {
    Action memory action = llamaCore.getAction(actionInfo.id);

    if (casts[actionInfo.id].voteSubmitted) revert AlreadySubmittedVote();
    // check to make sure the casting period has ended
    uint256 votingPeriod = ILlamaRelativeStrategyBase(address(actionInfo.strategy)).approvalPeriod();
    if (block.timestamp < action.creationTime + (votingPeriod * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS) {
      revert CantSubmitYet();
    }

    if (block.timestamp > action.creationTime + votingPeriod) revert SubmissionPeriodOver();

    /// @dev only timestamp mode is supported for now.
    string memory clockMode = _getClockMode();
    if (keccak256(abi.encodePacked(clockMode)) != keccak256(abi.encodePacked("mode=timestamp"))) {
      revert ClockModeNotSupported(clockMode);
    }

    uint256 totalSupply = _getPastTotalSupply(action.creationTime - 1);
    uint96 votesFor = casts[actionInfo.id].votesFor;
    uint96 votesAgainst = casts[actionInfo.id].votesAgainst;
    uint96 votesAbstain = casts[actionInfo.id].votesAbstain;
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, voteQuorum, ONE_HUNDRED_IN_BPS);
    if (votesFor < threshold) revert InsufficientVotes(votesFor, threshold);
    if (votesFor <= votesAgainst) revert ForDoesNotSurpassAgainst(votesFor, votesAgainst);

    casts[actionInfo.id].voteSubmitted = true;
    llamaCore.castApproval(role, actionInfo, "");
    emit VotesSubmitted(actionInfo.id, votesFor, votesAgainst, votesAbstain);
  }

  /// @notice Submits cast votes to the `LlamaCore` contract.
  /// @param actionInfo Data required to create an action.
  /// @dev this function can be called by anyone
  function submitVetos(ActionInfo calldata actionInfo) external {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, msg.sender, role); // Reverts if not allowed.
    if (casts[actionInfo.id].vetoSubmitted) revert AlreadySubmittedVeto();

    uint256 queuingPeriod = ILlamaRelativeStrategyBase(address(actionInfo.strategy)).queuingPeriod();
    // check to make sure the current timestamp is within the submitVetoBuffer period
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
    uint96 vetosFor = casts[actionInfo.id].vetosFor;
    uint96 vetosAgainst = casts[actionInfo.id].vetosAgainst;
    uint96 vetosAbstain = casts[actionInfo.id].vetosAbstain;
    uint256 threshold = FixedPointMathLib.mulDivUp(totalSupply, vetoQuorum, ONE_HUNDRED_IN_BPS);
    if (vetosFor < threshold) revert InsufficientVotes(vetosFor, threshold);
    if (vetosFor <= vetosAgainst) revert ForDoesNotSurpassAgainst(vetosFor, vetosAgainst);

    casts[actionInfo.id].vetoSubmitted = true;
    llamaCore.castDisapproval(role, actionInfo, "");
    emit VetosSubmitted(actionInfo.id, vetosFor, vetosAgainst, vetosAbstain);
  }

  function _castVote(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason) internal {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfApprovalEnabled(actionInfo, caster, role); // Reverts if not allowed.
    if (llamaCore.getActionState(actionInfo) != uint8(ActionState.Active)) revert ActionNotActive();
    if (casts[actionInfo.id].castVote[caster]) revert AlreadyCastVote();
    if (
      block.timestamp
        > action.creationTime
          + (ILlamaRelativeStrategyBase(address(actionInfo.strategy)).approvalPeriod() * TWO_THIRDS_IN_BPS)
            / ONE_HUNDRED_IN_BPS
    ) revert CastingPeriodOver();

    uint256 balance = _getPastVotes(caster, action.creationTime - 1);
    _preCastAssertions(balance, support);

    if (support == 0) casts[actionInfo.id].votesAgainst += LlamaUtils.toUint96(balance);
    else if (support == 1) casts[actionInfo.id].votesFor += LlamaUtils.toUint96(balance);
    else if (support == 2) casts[actionInfo.id].votesAbstain += LlamaUtils.toUint96(balance);
    casts[actionInfo.id].castVote[caster] = true;
    emit VoteCast(actionInfo.id, caster, role, support, balance, reason);
  }

  function _castVeto(address caster, ActionInfo calldata actionInfo, uint8 support, string calldata reason) internal {
    Action memory action = llamaCore.getAction(actionInfo.id);

    actionInfo.strategy.checkIfDisapprovalEnabled(actionInfo, caster, role); // Reverts if not allowed.
    if (!actionInfo.strategy.isActionApproved(actionInfo)) revert ActionNotApproved();
    if (actionInfo.strategy.isActionExpired(actionInfo)) revert ActionExpired();
    if (casts[actionInfo.id].castVeto[caster]) revert AlreadyCastVeto();
    if (
      block.timestamp
        > action.minExecutionTime
          - (ILlamaRelativeStrategyBase(address(actionInfo.strategy)).queuingPeriod() * ONE_THIRD_IN_BPS)
            / ONE_HUNDRED_IN_BPS
    ) revert CastingPeriodOver();

    uint256 balance = _getPastVotes(caster, action.creationTime - 1);
    _preCastAssertions(balance, support);

    if (support == 0) casts[actionInfo.id].vetosAgainst += LlamaUtils.toUint96(balance);
    else if (support == 1) casts[actionInfo.id].vetosFor += LlamaUtils.toUint96(balance);
    else if (support == 2) casts[actionInfo.id].vetosAbstain += LlamaUtils.toUint96(balance);
    casts[actionInfo.id].castVeto[caster] = true;
    emit VetoCast(actionInfo.id, caster, role, support, balance, reason);
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
        EIP712_DOMAIN_TYPEHASH, keccak256(bytes(llamaCore.name())), keccak256(bytes("1")), block.chainid, address(this)
      )
    );
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CastVote` domain, which can be used to
  /// recover the signer.
  function _getCastVoteTypedDataHash(
    address tokenholder,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castVoteHash = keccak256(
      abi.encode(
        CAST_VOTE_BY_SIG_TYPEHASH,
        tokenholder,
        support,
        _getActionInfoHash(actionInfo),
        keccak256(bytes(reason)),
        _useNonce(tokenholder, msg.sig)
      )
    );

    return keccak256(abi.encodePacked("\x19\x01", _getDomainHash(), castVoteHash));
  }

  /// @dev Returns the hash of the ABI-encoded EIP-712 message for the `CastVeto` domain, which can be used to
  /// recover the signer.
  function _getCastVetoTypedDataHash(
    address tokenholder,
    uint8 support,
    ActionInfo calldata actionInfo,
    string calldata reason
  ) internal returns (bytes32) {
    bytes32 castVetoHash = keccak256(
      abi.encode(
        CAST_VETO_BY_SIG_TYPEHASH,
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";
import {LlamaCoreSigUtils} from "test/utils/LlamaCoreSigUtils.sol";

import {ActionState, VoteType} from "src/lib/Enums.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaRelativeStrategyBase} from "src/interfaces/ILlamaRelativeStrategyBase.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {LlamaERC721TokenCaster} from "src/token-voting/LlamaERC721TokenCaster.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";

contract LlamaERC721TokenCasterTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
  event VoteCast(uint256 id, address indexed tokenholder, uint8 indexed support, uint256 weight, string reason);
  event ApprovalSubmitted(
    uint256 id, address indexed caller, uint256 weightFor, uint256 weightAgainst, uint256 weightAbstain
  );
  event VetoCast(uint256 id, address indexed tokenholder, uint8 indexed support, uint256 weight, string reason);
  event DisapprovalSubmitted(
    uint256 id, address indexed caller, uint256 weightFor, uint256 weightAgainst, uint256 weightAbstain
  );
  event QuorumSet(uint16 voteQuorumPct, uint16 vetoQuorumPct);

  ActionInfo actionInfo;
  LlamaERC721TokenCaster llamaERC721TokenCaster;
  ILlamaStrategy tokenVotingStrategy;

  function setUp() public virtual override {
    LlamaTokenVotingTestSetup.setUp();

    // Mint tokens to tokenholders so that there is an existing supply
    erc721VotesToken.mint(tokenHolder1, 0);
    vm.prank(tokenHolder1);
    erc721VotesToken.delegate(tokenHolder1);

    erc721VotesToken.mint(tokenHolder2, 1);
    vm.prank(tokenHolder2);
    erc721VotesToken.delegate(tokenHolder2);

    erc721VotesToken.mint(tokenHolder3, 2);
    vm.prank(tokenHolder3);
    erc721VotesToken.delegate(tokenHolder3);

    // Mine block so that the ERC20 and ERC721 supply will be available when doing a past timestamp check at initialize
    // during deployment.
    mineBlock();

    // Deploy ERC20 Token Voting Module.
    (, llamaERC721TokenCaster) = _deployERC721TokenVotingModuleAndSetRole();

    // Mine block so that Token Voting Caster Role will have supply during action creation (due to past timestamp check)
    mineBlock();

    tokenVotingStrategy = _deployRelativeQuantityQuorumAndSetRolePermissionToCoreTeam(tokenVotingCasterRole);
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    // Setting LlamaERC721TokenCaster's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(llamaERC721TokenCaster)
      })
    );
  }

  function castVotesFor() public {
    _skipVotingDelay();
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function castVetosFor() public {
    _skipVotingDelay();
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }
}

contract CastVote is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();
    _skipVotingDelay();
  }

  function test_RevertsIf_NotPastVotingDelay() public {
    vm.warp(block.timestamp - (1 days * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(LlamaTokenCaster.VotingDelayNotOver.selector);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.castVote(notActionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ApprovalNotEnabled() public {
    LlamaERC721TokenCaster casterWithWrongRole = LlamaERC721TokenCaster(
      Clones.cloneDeterministic(
        address(llamaERC721TokenCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, LLAMA_TOKEN_TIMESTAMP_ADAPTER, madeUpRole, ERC721_VOTE_QUORUM_PCT, ERC721_VETO_QUORUM_PCT
    );

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionNotActive() public {
    vm.warp(block.timestamp + 1 days + 1);
    vm.expectRevert(LlamaTokenCaster.ActionNotActive.selector);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_AlreadyCastedVote() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");

    vm.expectRevert(LlamaTokenCaster.AlreadyCastedVote.selector);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidSupport.selector, uint8(3)));
    llamaERC721TokenCaster.castVote(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    vm.warp(block.timestamp + ((1 days * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS) + 1); // 3/4 of the approval
      // period
    vm.expectRevert(LlamaTokenCaster.CastingPeriodOver.selector);
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_CanCastWithWeightZero() public {
    vm.expectEmit();
    emit VoteCast(actionInfo.id, address(this), uint8(VoteType.For), 0, "");
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_CastsVoteCorrectly(uint8 support) public {
    support = uint8(bound(support, uint8(VoteType.For), uint8(VoteType.Abstain)));
    vm.expectEmit();
    emit VoteCast(
      actionInfo.id, tokenHolder1, support, erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1), ""
    );
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(actionInfo, support, "");
  }

  function test_CastsVoteCorrectly_WithReason() public {
    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "reason");
  }
}

contract CastVoteBySig is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();
    _skipVotingDelay();
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CastVote memory castApproval = LlamaCoreSigUtils.CastVote({
      actionInfo: _actionInfo,
      support: uint8(VoteType.For),
      reason: "",
      tokenHolder: tokenHolder1,
      nonce: 0
    });
    bytes32 digest = getCastVoteTypedDataHash(castApproval);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function castVoteBySig(ActionInfo memory _actionInfo, uint8 support, uint8 v, bytes32 r, bytes32 s) internal {
    llamaERC721TokenCaster.castVoteBySig(tokenHolder1, support, _actionInfo, "", v, r, s);
  }

  function test_CastsVoteBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      uint8(VoteType.For),
      erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );

    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(llamaERC721TokenCaster.nonces(tokenHolder1, LlamaTokenCaster.castVoteBySig.selector), 0);
    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
    assertEq(llamaERC721TokenCaster.nonces(tokenHolder1, LlamaTokenCaster.castVoteBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenholder since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
  }

  function test_RevertIf_SignerIsNotTokenHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the erc20VotesTokenholder passed
    // in as parameter.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVoteBySig(actionInfo, uint8(VoteType.For), (v + 1), r, s);
  }

  function test_RevertIf_TokenHolderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.incrementNonce(LlamaTokenCaster.castVoteBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as
    // erc20VotesTokenholder since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
  }
}

contract CastVeto is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_NotPastVotingDelay() public {
    vm.expectRevert(LlamaTokenCaster.VotingDelayNotOver.selector);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.castVeto(notActionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    LlamaERC721TokenCaster casterWithWrongRole = LlamaERC721TokenCaster(
      Clones.cloneDeterministic(
        address(llamaERC721TokenCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, LLAMA_TOKEN_TIMESTAMP_ADAPTER, madeUpRole, ERC721_VOTE_QUORUM_PCT, ERC721_VETO_QUORUM_PCT
    );

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionNotQueued() public {
    bytes memory data = abi.encodeCall(mockProtocol.pause, (true));
    vm.prank(coreTeam1);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, tokenVotingStrategy, address(mockProtocol), 0, data, "");
    ActionInfo memory _actionInfo =
      ActionInfo(actionId, coreTeam1, CORE_TEAM_ROLE, tokenVotingStrategy, address(mockProtocol), 0, data);
    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(LlamaTokenCaster.ActionNotQueued.selector);
    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(_actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_AlreadyCastedVote() public {
    _skipVotingDelay();
    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");

    vm.expectRevert(LlamaTokenCaster.AlreadyCastedVeto.selector);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_InvalidSupport() public {
    _skipVotingDelay();
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidSupport.selector, uint8(3)));
    llamaERC721TokenCaster.castVeto(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + 2 + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS); // 3/4 of the approval period
    vm.expectRevert(LlamaTokenCaster.CastingPeriodOver.selector);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_CanCastWithWeightZero() public {
    _skipVotingDelay();
    vm.expectEmit();
    emit VetoCast(actionInfo.id, address(this), uint8(VoteType.For), 0, "");
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_CastsVetoCorrectly(uint8 support) public {
    _skipVotingDelay();
    support = uint8(bound(support, uint8(VoteType.For), uint8(VoteType.Abstain)));
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id, tokenHolder1, support, erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1), ""
    );
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(actionInfo, support, "");
  }

  function test_CastsVetoCorrectly_WithReason() public {
    _skipVotingDelay();
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      uint8(VoteType.For),
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "reason");
  }
}

contract CastVetoBySig is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.submitApproval(actionInfo);

    _skipVotingDelay();
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CastVeto memory castDisapproval = LlamaCoreSigUtils.CastVeto({
      actionInfo: _actionInfo,
      support: uint8(VoteType.For),
      reason: "",
      tokenHolder: tokenHolder1,
      nonce: 0
    });
    bytes32 digest = getCastVetoTypedDataHash(castDisapproval);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function castVetoBySig(ActionInfo memory _actionInfo, uint8 v, bytes32 r, bytes32 s) internal {
    llamaERC721TokenCaster.castVetoBySig(tokenHolder1, uint8(VoteType.For), _actionInfo, "", v, r, s);
  }

  function test_CastsVetoBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      uint8(VoteType.For),
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      ""
    );

    castVetoBySig(actionInfo, v, r, s);

    // assertEq(CORE.getAction(0).totalDisapprovals, 1);
    // assertEq(CORE.disapprovals(0, disapproverDrake), true);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(llamaERC721TokenCaster.nonces(tokenHolder1, LlamaTokenCaster.castVetoBySig.selector), 0);
    castVetoBySig(actionInfo, v, r, s);
    assertEq(llamaERC721TokenCaster.nonces(tokenHolder1, LlamaTokenCaster.castVetoBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    castVetoBySig(actionInfo, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenholder
    // since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsNotPolicyHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenholder
    // since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVetoBySig(actionInfo, (v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.incrementNonce(LlamaTokenCaster.castVetoBySig.selector);

    // Invalid Signature error since the recovered signer address during the second call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_FailsIfDisapproved() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    // First disapproval.
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      uint8(VoteType.For),
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      ""
    );
    castVetoBySig(actionInfo, v, r, s);
    // assertEq(CORE.getAction(actionInfo.id).totalDisapprovals, 1);

    // Second disapproval.
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");

    vm.warp(block.timestamp + 1 + (1 days * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    llamaERC721TokenCaster.submitDisapproval(actionInfo);

    // Assertions.
    ActionState state = ActionState(CORE.getActionState(actionInfo));
    assertEq(uint8(state), uint8(ActionState.Failed));

    vm.expectRevert(abi.encodeWithSelector(ILlamaCore.InvalidActionState.selector, ActionState.Failed));
    CORE.executeAction(actionInfo);
  }
}

contract SubmitApprovals is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.submitApproval(notActionInfo);
  }

  function test_RevertsIf_ApprovalNotEnabled() public {
    LlamaERC721TokenCaster casterWithWrongRole = LlamaERC721TokenCaster(
      Clones.cloneDeterministic(
        address(llamaERC721TokenCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, LLAMA_TOKEN_TIMESTAMP_ADAPTER, madeUpRole, ERC721_VOTE_QUORUM_PCT, ERC721_VETO_QUORUM_PCT
    );
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.submitApproval(actionInfo);
  }

  function test_RevertsIf_AlreadySubmittedApproval() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.submitApproval(actionInfo);

    vm.expectRevert(LlamaTokenCaster.AlreadySubmittedApproval.selector);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + ((1 days * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS) + 2); // 1/3 of the approval period
    vm.expectRevert(LlamaTokenCaster.SubmissionPeriodOver.selector);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_InsufficientVotes() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InsufficientVotes.selector, 0, 1));
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    _skipVotingDelay(); // 1/3 of the approval period
    vm.expectRevert(LlamaTokenCaster.CannotSubmitYet.selector);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    _skipVotingDelay();

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.Against), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.Against), "");

    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_SubmitsApprovalsCorrectly() public {
    vm.expectEmit();
    emit ApprovalSubmitted(actionInfo.id, address(this), 3, 0, 0);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }
}

contract SubmitDisapprovals is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.submitDisapproval(notActionInfo);
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    LlamaERC721TokenCaster casterWithWrongRole = LlamaERC721TokenCaster(
      Clones.cloneDeterministic(
        address(llamaERC721TokenCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, LLAMA_TOKEN_TIMESTAMP_ADAPTER, madeUpRole, ERC721_VOTE_QUORUM_PCT, ERC721_VETO_QUORUM_PCT
    );
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_AlreadySubmittedDisapproval() public {
    castVetosFor();

    vm.warp(block.timestamp + (1 days * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);

    vm.expectRevert(LlamaTokenCaster.AlreadySubmittedDisapproval.selector);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    castVetosFor();

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(LlamaTokenCaster.SubmissionPeriodOver.selector);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_InsufficientDisapprovals() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    castVotesFor();
    vm.warp(block.timestamp + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    llamaERC721TokenCaster.submitApproval(actionInfo);

    //TODO why add 1 here
    vm.warp(block.timestamp + 1 + (1 days * THREE_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InsufficientVotes.selector, 0, 1));
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(LlamaTokenCaster.CannotSubmitYet.selector);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    _skipVotingDelay();
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.Against), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.Against), "");

    vm.warp(block.timestamp + (1 days * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_SubmitsDisapprovalsCorrectly() public {
    castVetosFor();

    vm.warp(block.timestamp + (1 days * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectEmit();
    emit DisapprovalSubmitted(actionInfo.id, address(this), 3, 0, 0);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }
}

contract SetQuorumPct is LlamaERC721TokenCasterTest {
  function test_RevertsIf_NotLlamaExecutor(address notLlamaExecutor) public {
    vm.assume(notLlamaExecutor != address(EXECUTOR));
    vm.expectRevert(LlamaTokenCaster.OnlyLlamaExecutor.selector);
    vm.prank(notLlamaExecutor);
    llamaERC721TokenCaster.setQuorumPct(ERC20_VOTE_QUORUM_PCT, ERC20_VETO_QUORUM_PCT);
  }

  function test_RevertsIf_InvalidQuorumPct() public {
    vm.startPrank(address(EXECUTOR));
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVetoQuorumPct.selector, uint256(0)));
    llamaERC721TokenCaster.setQuorumPct(ERC20_VOTE_QUORUM_PCT, 0);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVoteQuorumPct.selector, uint256(0)));
    llamaERC721TokenCaster.setQuorumPct(0, ERC20_VETO_QUORUM_PCT);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVetoQuorumPct.selector, uint256(10_001)));
    llamaERC721TokenCaster.setQuorumPct(ERC20_VOTE_QUORUM_PCT, 10_001);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVoteQuorumPct.selector, uint256(10_001)));
    llamaERC721TokenCaster.setQuorumPct(10_001, ERC20_VETO_QUORUM_PCT);
    vm.stopPrank();
  }

  function test_SetsQuorumPctCorrectly(uint16 _voteQuorum, uint16 _vetoQuorum) public {
    _voteQuorum = uint16(bound(_voteQuorum, 1, ONE_HUNDRED_IN_BPS));
    _vetoQuorum = uint16(bound(_vetoQuorum, 1, ONE_HUNDRED_IN_BPS));
    vm.expectEmit();
    emit QuorumSet(_voteQuorum, _vetoQuorum);
    vm.prank(address(EXECUTOR));
    llamaERC721TokenCaster.setQuorumPct(_voteQuorum, _vetoQuorum);
  }
}

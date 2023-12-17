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
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {LlamaTokenAdapterVotesTimestamp} from "src/token-voting/token-adapters/LlamaTokenAdapterVotesTimestamp.sol";
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
  event QuorumPctSet(uint16 voteQuorumPct, uint16 vetoQuorumPct);
  event PeriodPctSet(uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct);

  ActionInfo actionInfo;
  uint256 actionCreationTime;
  uint256 minExecutionTime;
  LlamaTokenCaster llamaERC721TokenCaster;
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

    // Deploy ERC721 Token Voting Module.
    (, llamaERC721TokenCaster) = _deployERC721TokenVotingModuleAndSetRole();

    // Mine block so that Token Voting Caster Role will have supply during action creation (due to past timestamp check)
    mineBlock();

    tokenVotingStrategy = _deployRelativeQuantityQuorumAndSetRolePermissionToCoreTeam(tokenVotingCasterRole);
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    Action memory action = CORE.getAction(actionInfo.id);
    actionCreationTime = action.creationTime;
    minExecutionTime = action.minExecutionTime;

    // Setting LlamaTokenCaster's EIP-712 Domain Hash
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
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function castVetosFor() public {
    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function createTimestampTokenAdapter(address token, uint256 nonce) public returns (ILlamaTokenAdapter tokenAdapter) {
    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(token)));

    bytes32 salt = keccak256(abi.encodePacked(msg.sender, address(CORE), adapterConfig, nonce));

    tokenAdapter = ILlamaTokenAdapter(Clones.cloneDeterministic(address(llamaTokenAdapterTimestampLogic), salt));
    tokenAdapter.initialize(adapterConfig);
  }
}

contract CastVote is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();
    _skipVotingDelay(actionInfo);
  }

  function test_RevertsIf_NotPastVotingDelay() public {
    vm.warp(block.timestamp - 1);
    vm.expectRevert(LlamaTokenCaster.VotingDelayNotOver.selector);
    llamaERC721TokenCaster.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.castVote(notActionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ApprovalNotEnabled() public {
    ILlamaTokenAdapter tokenAdapter = createTimestampTokenAdapter(address(erc721VotesToken), 0);

    LlamaTokenCaster casterWithWrongRole = LlamaTokenCaster(
      Clones.cloneDeterministic(
        address(llamaTokenCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );

    casterWithWrongRole.initialize(CORE, tokenAdapter, madeUpRole, defaultCasterConfig);

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVote(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionNotActive() public {
    vm.warp(actionCreationTime + APPROVAL_PERIOD + 1);
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
    uint256 delayPeriodEndTime = actionCreationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);
    vm.expectRevert(LlamaTokenCaster.CastingPeriodOver.selector);
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
    uint96 weight = llamaERC721TokenCaster.castVote(actionInfo, support, "");
    assertEq(weight, erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1));
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

  function test_GetsWeightAtDelayPeriodTimestamp() public {
    // Currently we are at delayPeriodEndTime + 1.
    vm.startPrank(tokenHolder1);
    assertEq(erc721VotesToken.getVotes(tokenHolder1), 1);
    // Burning all of tokenHolder1's votes at delayPeriodEndTime + 1
    erc721VotesToken.transferFrom(tokenHolder1, address(0xdeadbeef), 0);
    assertEq(erc721VotesToken.getVotes(tokenHolder1), 0);
    // However tokenholder1 is able to vote with the weight they had at delayPeriodEndTime
    vm.expectEmit();
    emit VoteCast(actionInfo.id, tokenHolder1, 1, 1, "");
    uint96 weight = llamaERC721TokenCaster.castVote(actionInfo, 1, "");
    assertEq(weight, 1);
    vm.stopPrank();
  }
}

contract CastVoteBySig is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();
    _skipVotingDelay(actionInfo);
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
    llamaERC721TokenCaster.castVoteBySig(tokenHolder1, _actionInfo, support, "", v, r, s);
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
    // erc721VotesTokenholder since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
  }

  function test_RevertIf_SignerIsNotTokenHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the erc721VotesTokenholder passed
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
    // erc721VotesTokenholder since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVoteBySig(actionInfo, uint8(VoteType.For), v, r, s);
  }
}

contract CastVeto is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();

    _skipVotingDelay(actionInfo);
    castVotesFor();

    uint256 delayPeriodEndTime = actionCreationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);

    llamaERC721TokenCaster.submitApproval(actionInfo);
    _skipVetoDelay(actionInfo);
  }

  function test_RevertsIf_NotPastVotingDelay() public {
    vm.warp(block.timestamp - 1);
    vm.expectRevert(LlamaTokenCaster.VotingDelayNotOver.selector);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.castVeto(notActionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    ILlamaTokenAdapter tokenAdapter = createTimestampTokenAdapter(address(erc721VotesToken), 0);

    LlamaTokenCaster casterWithWrongRole = LlamaTokenCaster(
      Clones.cloneDeterministic(
        address(llamaTokenCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(CORE, tokenAdapter, madeUpRole, defaultCasterConfig);

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_ActionNotQueued() public {
    bytes memory data = abi.encodeCall(mockProtocol.pause, (true));
    vm.prank(coreTeam1);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, tokenVotingStrategy, address(mockProtocol), 0, data, "");
    ActionInfo memory _actionInfo =
      ActionInfo(actionId, coreTeam1, CORE_TEAM_ROLE, tokenVotingStrategy, address(mockProtocol), 0, data);
    // Currently at actionCreationTime which is Active state.
    vm.expectRevert(LlamaTokenCaster.ActionNotQueued.selector);
    llamaERC721TokenCaster.castVeto(_actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_AlreadyCastedVote() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");

    vm.expectRevert(LlamaTokenCaster.AlreadyCastedVeto.selector);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidSupport.selector, uint8(3)));
    llamaERC721TokenCaster.castVeto(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    Action memory action = CORE.getAction(actionInfo.id);
    uint256 delayPeriodEndTime =
      (action.minExecutionTime - QUEUING_PERIOD) + ((QUEUING_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((QUEUING_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);
    vm.expectRevert(LlamaTokenCaster.CastingPeriodOver.selector);
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_CanCastWithWeightZero() public {
    vm.expectEmit();
    emit VetoCast(actionInfo.id, address(this), uint8(VoteType.For), 0, "");
    llamaERC721TokenCaster.castVeto(actionInfo, uint8(VoteType.For), "");
  }

  function test_CastsVetoCorrectly(uint8 support) public {
    support = uint8(bound(support, uint8(VoteType.For), uint8(VoteType.Abstain)));
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id, tokenHolder1, support, erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1), ""
    );
    vm.prank(tokenHolder1);
    uint96 weight = llamaERC721TokenCaster.castVeto(actionInfo, support, "");
    assertEq(weight, erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1));
  }

  function test_CastsVetoCorrectly_WithReason() public {
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

  function test_GetsWeightAtDelayPeriodTimestamp() public {
    // Currently we are at delayPeriodEndTime + 1.
    vm.startPrank(tokenHolder1);
    assertEq(erc721VotesToken.getVotes(tokenHolder1), 1);
    // Burning all of tokenHolder1's votes at delayPeriodEndTime + 1
    erc721VotesToken.transferFrom(tokenHolder1, address(0xdeadbeef), 0);
    assertEq(erc721VotesToken.getVotes(tokenHolder1), 0);
    // However tokenholder1 is able to vote with the weight they had at delayPeriodEndTime
    vm.expectEmit();
    emit VetoCast(actionInfo.id, tokenHolder1, 1, 1, "");
    uint96 weight = llamaERC721TokenCaster.castVeto(actionInfo, 1, "");
    assertEq(weight, 1);
    vm.stopPrank();
  }
}

contract CastVetoBySig is LlamaERC721TokenCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenCasterTest.setUp();

    _skipVotingDelay(actionInfo);
    castVotesFor();

    uint256 delayPeriodEndTime = actionCreationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);

    llamaERC721TokenCaster.submitApproval(actionInfo);
    _skipVetoDelay(actionInfo);
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
    llamaERC721TokenCaster.castVetoBySig(tokenHolder1, _actionInfo, uint8(VoteType.For), "", v, r, s);
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
    // erc721VotesTokenholder
    // since nonce has increased.
    vm.expectRevert(LlamaTokenCaster.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsNotPolicyHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc721VotesTokenholder
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

    Action memory action = CORE.getAction(actionInfo.id);
    uint256 delayPeriodEndTime =
      (action.minExecutionTime - QUEUING_PERIOD) + ((QUEUING_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((QUEUING_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);

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

    _skipVotingDelay(actionInfo);
    castVotesFor();

    uint256 delayPeriodEndTime = actionCreationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.submitApproval(notActionInfo);
  }

  function test_RevertsIf_AlreadySubmittedApproval() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.submitApproval(actionInfo);

    vm.expectRevert(LlamaTokenCaster.AlreadySubmittedApproval.selector);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    vm.warp(actionCreationTime + APPROVAL_PERIOD + 1);
    vm.expectRevert(LlamaTokenCaster.SubmissionPeriodOver.selector);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_InsufficientVotes() public {
    ActionInfo memory _actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    Action memory action = CORE.getAction(_actionInfo.id);
    uint256 delayPeriodEndTime = action.creationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InsufficientVotes.selector, 0, 1));
    llamaERC721TokenCaster.submitApproval(_actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp - 1);
    vm.expectRevert(LlamaTokenCaster.CannotSubmitYet.selector);
    llamaERC721TokenCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    ActionInfo memory _actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    Action memory action = CORE.getAction(_actionInfo.id);

    uint256 delayPeriodEndTime = action.creationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.warp(delayPeriodEndTime + 1);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.Against), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.Against), "");

    vm.warp(castingPeriodEndTime + 1);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    llamaERC721TokenCaster.submitApproval(_actionInfo);
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

    _skipVotingDelay(actionInfo);
    castVotesFor();

    uint256 delayPeriodEndTime = actionCreationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);

    llamaERC721TokenCaster.submitApproval(actionInfo);

    _skipVetoDelay(actionInfo);
    castVetosFor();

    Action memory action = CORE.getAction(actionInfo.id);
    delayPeriodEndTime =
      (action.minExecutionTime - QUEUING_PERIOD) + ((QUEUING_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    castingPeriodEndTime = delayPeriodEndTime + ((QUEUING_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenCaster.submitDisapproval(notActionInfo);
  }

  function test_RevertsIf_AlreadySubmittedDisapproval() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);

    vm.expectRevert(LlamaTokenCaster.AlreadySubmittedDisapproval.selector);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    Action memory action = CORE.getAction(actionInfo.id);
    vm.warp(action.minExecutionTime);
    vm.expectRevert(LlamaTokenCaster.SubmissionPeriodOver.selector);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_InsufficientDisapprovals() public {
    ActionInfo memory _actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    Action memory action = CORE.getAction(_actionInfo.id);

    uint256 delayPeriodEndTime = action.creationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.warp(delayPeriodEndTime + 1);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.For), "");

    vm.warp(castingPeriodEndTime + 1);
    llamaERC721TokenCaster.submitApproval(_actionInfo);

    action = CORE.getAction(_actionInfo.id);

    delayPeriodEndTime =
      (action.minExecutionTime - QUEUING_PERIOD) + ((QUEUING_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    castingPeriodEndTime = delayPeriodEndTime + ((QUEUING_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.warp(castingPeriodEndTime + 1);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InsufficientVotes.selector, 0, 1));
    llamaERC721TokenCaster.submitDisapproval(_actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp - 1);
    vm.expectRevert(LlamaTokenCaster.CannotSubmitYet.selector);
    llamaERC721TokenCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    ActionInfo memory _actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    Action memory action = CORE.getAction(_actionInfo.id);

    uint256 delayPeriodEndTime = action.creationTime + ((APPROVAL_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    uint256 castingPeriodEndTime = delayPeriodEndTime + ((APPROVAL_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.warp(delayPeriodEndTime + 1);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVote(_actionInfo, uint8(VoteType.For), "");

    vm.warp(castingPeriodEndTime + 1);
    llamaERC721TokenCaster.submitApproval(_actionInfo);

    action = CORE.getAction(_actionInfo.id);

    delayPeriodEndTime =
      (action.minExecutionTime - QUEUING_PERIOD) + ((QUEUING_PERIOD * ONE_QUARTER_IN_BPS) / ONE_HUNDRED_IN_BPS);
    castingPeriodEndTime = delayPeriodEndTime + ((QUEUING_PERIOD * TWO_QUARTERS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.warp(delayPeriodEndTime + 1);

    vm.prank(tokenHolder1);
    llamaERC721TokenCaster.castVeto(_actionInfo, uint8(VoteType.For), "");
    vm.prank(tokenHolder2);
    llamaERC721TokenCaster.castVeto(_actionInfo, uint8(VoteType.Against), "");
    vm.prank(tokenHolder3);
    llamaERC721TokenCaster.castVeto(_actionInfo, uint8(VoteType.Against), "");

    vm.warp(castingPeriodEndTime + 1);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    llamaERC721TokenCaster.submitDisapproval(_actionInfo);
  }

  function test_SubmitsDisapprovalsCorrectly() public {
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
    llamaERC721TokenCaster.setQuorumPct(ERC721_VOTE_QUORUM_PCT, ERC721_VETO_QUORUM_PCT);
  }

  function test_RevertsIf_InvalidQuorumPct() public {
    vm.startPrank(address(EXECUTOR));
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVetoQuorumPct.selector, uint256(0)));
    llamaERC721TokenCaster.setQuorumPct(ERC721_VOTE_QUORUM_PCT, 0);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVoteQuorumPct.selector, uint256(0)));
    llamaERC721TokenCaster.setQuorumPct(0, ERC721_VETO_QUORUM_PCT);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVetoQuorumPct.selector, uint256(10_001)));
    llamaERC721TokenCaster.setQuorumPct(ERC721_VOTE_QUORUM_PCT, 10_001);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenCaster.InvalidVoteQuorumPct.selector, uint256(10_001)));
    llamaERC721TokenCaster.setQuorumPct(10_001, ERC721_VETO_QUORUM_PCT);
    vm.stopPrank();
  }

  function test_SetsQuorumPctCorrectly(uint16 _voteQuorum, uint16 _vetoQuorum) public {
    _voteQuorum = uint16(bound(_voteQuorum, 1, ONE_HUNDRED_IN_BPS));
    _vetoQuorum = uint16(bound(_vetoQuorum, 1, ONE_HUNDRED_IN_BPS));
    vm.expectEmit();
    emit QuorumPctSet(_voteQuorum, _vetoQuorum);
    vm.prank(address(EXECUTOR));
    llamaERC721TokenCaster.setQuorumPct(_voteQuorum, _vetoQuorum);
  }
}

contract SetPeriodPct is LlamaERC721TokenCasterTest {
  function test_RevertsIf_NotLlamaExecutor(address notLlamaExecutor) public {
    vm.assume(notLlamaExecutor != address(EXECUTOR));
    vm.expectRevert(LlamaTokenCaster.OnlyLlamaExecutor.selector);
    vm.prank(notLlamaExecutor);
    llamaERC721TokenCaster.setPeriodPct(
      uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS)
    );
  }

  function test_RevertsIf_InvalidPeriodPct() public {
    vm.startPrank(address(EXECUTOR));
    vm.expectRevert(
      abi.encodeWithSelector(
        LlamaTokenCaster.InvalidPeriodPcts.selector,
        uint16(ONE_QUARTER_IN_BPS),
        uint16(TWO_QUARTERS_IN_BPS),
        uint16(ONE_QUARTER_IN_BPS) + 1
      )
    );
    llamaERC721TokenCaster.setPeriodPct(
      uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS) + 1
    );
    vm.expectRevert(
      abi.encodeWithSelector(
        LlamaTokenCaster.InvalidPeriodPcts.selector,
        uint16(ONE_QUARTER_IN_BPS),
        uint16(TWO_QUARTERS_IN_BPS),
        uint16(ONE_QUARTER_IN_BPS) - 1
      )
    );
    llamaERC721TokenCaster.setPeriodPct(
      uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS) - 1
    );
    vm.stopPrank();
  }

  function test_SetsPeriodPctCorrectly() public {
    vm.expectEmit();
    emit PeriodPctSet(uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS));
    vm.prank(address(EXECUTOR));
    llamaERC721TokenCaster.setPeriodPct(
      uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS)
    );
  }
}

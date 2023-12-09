// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";
import {LlamaCoreSigUtils} from "test/utils/LlamaCoreSigUtils.sol";

import {ActionState} from "src/lib/Enums.sol";
import {Action, ActionInfo, PermissionData} from "src/lib/Structs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaRelativeStrategyBase} from "src/interfaces/ILlamaRelativeStrategyBase.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ERC721TokenHolderCaster} from "src/token-voting/ERC721TokenHolderCaster.sol";
import {TokenHolderCaster} from "src/token-voting/TokenHolderCaster.sol";

contract ERC721TokenHolderCasterTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
  event VoteCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event VotesSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  event DisapprovalCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event DisapprovalsSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  ActionInfo actionInfo;
  ERC721TokenHolderCaster erc721TokenHolderCaster;
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
    (, erc721TokenHolderCaster) = _deployERC721TokenVotingModuleAndSetRole();

    // Mine block so that Token Voting Caster Role will have supply during action creation (due to past timestamp check)
    mineBlock();

    tokenVotingStrategy = _deployRelativeQuantityQuorumAndSetRolePermissionToCoreTeam(tokenVotingCasterRole);
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    // Setting ERC721TokenHolderCaster's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(erc721TokenHolderCaster)
      })
    );
  }

  function castVotesFor() public {
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function castVetosFor() public {
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }
}

// contract Constructor is ERC721TokenHolderCasterTest {
//   function test_RevertsIf_InvalidLlamaCoreAddress() public {
//     // With invalid LlamaCore instance, TokenHolderActionCreator.InvalidLlamaCoreAddress is unreachable
//     vm.expectRevert();
//     new ERC721TokenHolderCaster(
//       erc721VotesToken, ILlamaCore(makeAddr("invalid-llama-core")), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidTokenAddress(address notAToken) public {
//     vm.assume(notAToken != address(0));
//     vm.assume(notAToken != address(erc721VotesToken));
//     vm.expectRevert(); // will revert with EvmError: Revert because `totalSupply` is not a function
//     new ERC721TokenHolderCaster(
//       ERC20Votes(notAToken), ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidRole(uint8 role) public {
//     role = uint8(bound(role, POLICY.numRoles(), 255));
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.RoleNotInitialized.selector, uint8(255)));
//     new ERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), uint8(255), uint256(1), uint256(1));
//   }

//   function test_RevertsIf_InvalidMinVotePct() public {
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinVotePct.selector, uint256(0)));
//     new ERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(0),
// uint256(1));
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinVotePct.selector, uint256(10_001)));
//     new ERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(10_001),
// uint256(1));
//   }

//   function test_RevertsIf_InvalidMinDisapprovalPct() public {
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinDisapprovalPct.selector, uint256(0)));
//     new ERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(0));
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinDisapprovalPct.selector, uint256(10_001)));
//     new ERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(10_001));
//   }

//   function test_ProperlySetsConstructorArguments() public {
//     erc721VotesToken.mint(address(this), 1_000_000e18); // we use erc721VotesToken because IVotesToken is an
// interface
//     // without the `mint` function

//     erc721TokenHolderCaster = new ERC721TokenHolderCaster(
//       erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, DEFAULT_APPROVAL_THRESHOLD,
// DEFAULT_APPROVAL_THRESHOLD
//     );

//     assertEq(address(erc721TokenHolderCaster.LLAMA_CORE()), address(CORE));
//     assertEq(address(erc721TokenHolderCaster.TOKEN()), address(erc721VotesToken));
//     assertEq(erc721TokenHolderCaster.ROLE(), tokenVotingCasterRole);
//     assertEq(erc721TokenHolderCaster.MIN_APPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//     assertEq(erc721TokenHolderCaster.MIN_DISAPPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//   }
// }

contract CastVote is ERC721TokenHolderCasterTest {
  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc721TokenHolderCaster.castVote(notActionInfo, 1, "");
  }

  function test_RevertsIf_VoteNotEnabled() public {
    ERC721TokenHolderCaster casterWithWrongRole = ERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(erc721TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, madeUpRole, ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_ActionNotActive() public {
    vm.warp(block.timestamp + 1 days + 1);
    vm.expectRevert(TokenHolderCaster.ActionNotActive.selector);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_AlreadyCastVote() public {
    vm.startPrank(tokenHolder1);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");

    vm.expectRevert(TokenHolderCaster.AlreadyCastVote.selector);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidSupport.selector, uint8(3)));
    erc721TokenHolderCaster.castVote(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    vm.warp(block.timestamp + ((1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS) + 1); // 2/3 of the approval period
    vm.expectRevert(TokenHolderCaster.CastingPeriodOver.selector);
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientBalance.selector, 0));
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_CastsVoteCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      support,
      erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVote(actionInfo, support, "");
  }

  function test_CastsVoteCorrectly_WithReason() public {
    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "reason");
  }
}

contract CastVoteBySig is ERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC721TokenHolderCasterTest.setUp();
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CastVote memory castVote =
      LlamaCoreSigUtils.CastVote({actionInfo: _actionInfo, support: 1, reason: "", tokenHolder: tokenHolder1, nonce: 0});
    bytes32 digest = getCastVoteTypedDataHash(castVote);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function castVoteBySig(ActionInfo memory _actionInfo, uint8 support, uint8 v, bytes32 r, bytes32 s) internal {
    erc721TokenHolderCaster.castVoteBySig(tokenHolder1, support, _actionInfo, "", v, r, s);
  }

  function test_CastsVoteBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );

    castVoteBySig(actionInfo, 1, v, r, s);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(erc721TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVoteBySig.selector), 0);
    castVoteBySig(actionInfo, 1, v, r, s);
    assertEq(erc721TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVoteBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    castVoteBySig(actionInfo, 1, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenHolder since nonce has increased.
    vm.expectRevert(TokenHolderCaster.InvalidSignature.selector);
    castVoteBySig(actionInfo, 1, v, r, s);
  }

  function test_RevertIf_SignerIsNotTokenHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the erc20VotesTokenHolder passed
    // in as parameter.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVoteBySig(actionInfo, 1, v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVoteBySig(actionInfo, 1, (v + 1), r, s);
  }

  function test_RevertIf_TokenHolderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.incrementNonce(TokenHolderCaster.castVoteBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as
    // erc20VotesTokenHolder since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVoteBySig(actionInfo, 1, v, r, s);
  }
}

contract CastVeto is ERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC721TokenHolderCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc721TokenHolderCaster.castVeto(notActionInfo, tokenVotingCasterRole, "");
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    ERC721TokenHolderCaster casterWithWrongRole = ERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(erc721TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, madeUpRole, ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVeto(actionInfo, madeUpRole, "");
  }

  function test_RevertsIf_AlreadyCastVote() public {
    vm.startPrank(tokenHolder1);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");

    vm.expectRevert(TokenHolderCaster.AlreadyCastVeto.selector);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidSupport.selector, uint8(3)));
    erc721TokenHolderCaster.castVeto(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + 2 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS); // 2/3 of the approval period
    vm.expectRevert(TokenHolderCaster.CastingPeriodOver.selector);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientBalance.selector, 0));
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_CastsDisapprovalCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      support,
      erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVeto(actionInfo, support, "");
  }

  function test_CastsDisapprovalCorrectly_WithReason() public {
    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "reason");
  }
}

contract CastVetoBySig is ERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC721TokenHolderCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CastVeto memory castVeto =
      LlamaCoreSigUtils.CastVeto({actionInfo: _actionInfo, support: 1, reason: "", tokenHolder: tokenHolder1, nonce: 0});
    bytes32 digest = getCastVetoTypedDataHash(castVeto);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function castVetoBySig(ActionInfo memory _actionInfo, uint8 v, bytes32 r, bytes32 s) internal {
    erc721TokenHolderCaster.castVetoBySig(tokenHolder1, 1, _actionInfo, "", v, r, s);
  }

  function test_CastsDisapprovalBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      ""
    );

    castVetoBySig(actionInfo, v, r, s);

    // assertEq(CORE.getAction(0).totalDisapprovals, 1);
    // assertEq(CORE.disapprovals(0, disapproverDrake), true);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(erc721TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVetoBySig.selector), 0);
    castVetoBySig(actionInfo, v, r, s);
    assertEq(erc721TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVetoBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    castVetoBySig(actionInfo, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenHolder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsNotPolicyHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenHolder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVetoBySig(actionInfo, (v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.incrementNonce(TokenHolderCaster.castVetoBySig.selector);

    // Invalid Signature error since the recovered signer address during the second call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_FailsIfDisapproved() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    // First disapproval.
    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      ""
    );
    castVetoBySig(actionInfo, v, r, s);
    // assertEq(CORE.getAction(actionInfo.id).totalDisapprovals, 1);

    // Second disapproval.
    vm.prank(tokenHolder2);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");

    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    erc721TokenHolderCaster.submitVetos(actionInfo);

    // Assertions.
    ActionState state = ActionState(CORE.getActionState(actionInfo));
    assertEq(uint8(state), uint8(ActionState.Failed));

    vm.expectRevert(abi.encodeWithSelector(ILlamaCore.InvalidActionState.selector, ActionState.Failed));
    CORE.executeAction(actionInfo);
  }
}

contract SubmitVotes is ERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC721TokenHolderCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc721TokenHolderCaster.submitVotes(notActionInfo);
  }

  function test_RevertsIf_AlreadySubmittedVotes() public {
    vm.startPrank(tokenHolder1);
    erc721TokenHolderCaster.submitVotes(actionInfo);

    vm.expectRevert(TokenHolderCaster.AlreadySubmittedVotes.selector);
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + ((1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS) + 2); // 1/3 of the approval period
    vm.expectRevert(TokenHolderCaster.SubmissionPeriodOver.selector);
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_InsufficientVotes() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientVotes.selector, 0, 1));
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(TokenHolderCaster.CantSubmitYet.selector);
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc721TokenHolderCaster.castVote(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    erc721TokenHolderCaster.castVote(actionInfo, 0, "");

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_SubmitsVotesCorrectly() public {
    vm.expectEmit();
    emit VotesSubmitted(actionInfo.id, 3, 0, 0);
    erc721TokenHolderCaster.submitVotes(actionInfo);
  }
}

contract SubmitDisapprovals is ERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC721TokenHolderCasterTest.setUp();

    castVotesFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    erc721TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc721TokenHolderCaster.submitVetos(notActionInfo);
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    ERC721TokenHolderCaster casterWithWrongRole = ERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(erc721TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, madeUpRole, ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.submitVetos(actionInfo);
  }

  function test_RevertsIf_AlreadySubmittedVetos() public {
    Action memory action = CORE.getAction(actionInfo.id);
    vm.warp(
      action.minExecutionTime
        - (ILlamaRelativeStrategyBase(address(actionInfo.strategy)).queuingPeriod() * ONE_THIRD_IN_BPS)
          / ONE_HUNDRED_IN_BPS
    );

    castVetosFor();

    vm.startPrank(tokenHolder1);
    erc721TokenHolderCaster.submitVetos(actionInfo);

    vm.expectRevert(TokenHolderCaster.AlreadySubmittedVetos.selector);
    erc721TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    castVetosFor();

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(TokenHolderCaster.SubmissionPeriodOver.selector);
    erc721TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_InsufficientDisapprovals() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    castVotesFor();
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    erc721TokenHolderCaster.submitVotes(actionInfo);

    //TODO why add 1 here
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientVotes.selector, 0, 1));
    erc721TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(TokenHolderCaster.CantSubmitYet.selector);
    erc721TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    vm.prank(tokenHolder1);
    erc721TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc721TokenHolderCaster.castVeto(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    erc721TokenHolderCaster.castVeto(actionInfo, 0, "");
    // TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    erc721TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_SubmitsDisapprovalsCorrectly() public {
    castVetosFor();

    //TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectEmit();
    emit DisapprovalsSubmitted(actionInfo.id, 3, 0, 0);
    erc721TokenHolderCaster.submitVetos(actionInfo);
  }
}

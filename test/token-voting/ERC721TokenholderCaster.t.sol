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
import {LlamaERC721TokenHolderCaster} from "src/token-voting/LlamaERC721TokenHolderCaster.sol";
import {LlamaTokenHolderCaster} from "src/token-voting/LlamaTokenHolderCaster.sol";

contract LlamaERC721TokenHolderCasterTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
  event VoteCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event ApprovalSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  event VetoCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event DisapprovalSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  ActionInfo actionInfo;
  LlamaERC721TokenHolderCaster llamaERC721TokenHolderCaster;
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
    (, llamaERC721TokenHolderCaster) = _deployERC721TokenVotingModuleAndSetRole();

    // Mine block so that Token Voting Caster Role will have supply during action creation (due to past timestamp check)
    mineBlock();

    tokenVotingStrategy = _deployRelativeQuantityQuorumAndSetRolePermissionToCoreTeam(tokenVotingCasterRole);
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    // Setting LlamaERC721TokenHolderCaster's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(llamaERC721TokenHolderCaster)
      })
    );
  }

  function castApprovalsFor() public {
    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function castDisapprovalsFor() public {
    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }
}

// contract Constructor is LlamaERC721TokenHolderCasterTest {
//   function test_RevertsIf_InvalidLlamaCoreAddress() public {
//     // With invalid LlamaCore instance, LlamaTokenHolderActionCreator.InvalidLlamaCoreAddress is unreachable
//     vm.expectRevert();
//     new LlamaERC721TokenHolderCaster(
//       erc721VotesToken, ILlamaCore(makeAddr("invalid-llama-core")), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidTokenAddress(address notAToken) public {
//     vm.assume(notAToken != address(0));
//     vm.assume(notAToken != address(erc721VotesToken));
//     vm.expectRevert(); // will revert with EvmError: Revert because `totalSupply` is not a function
//     new LlamaERC721TokenHolderCaster(
//       ERC20Votes(notAToken), ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidRole(uint8 role) public {
//     role = uint8(bound(role, POLICY.numRoles(), 255));
//     vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.RoleNotInitialized.selector, uint8(255)));
//     new LlamaERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), uint8(255), uint256(1),
// uint256(1));
//   }

//   function test_RevertsIf_InvalidVoteQuorumPct() public {
//     vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InvalidVoteQuorumPct.selector, uint256(0)));
//     new LlamaERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(0),
// uint256(1));
//     vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InvalidVoteQuorumPct.selector, uint256(10_001)));
//     new LlamaERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole,
// uint256(10_001),
// uint256(1));
//   }

//   function test_RevertsIf_InvalidVetoQuorumPct() public {
//     vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InvalidVetoQuorumPct.selector, uint256(0)));
//     new LlamaERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(0));
//     vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InvalidVetoQuorumPct.selector,
// uint256(10_001)));
//     new LlamaERC721TokenHolderCaster(erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(10_001));
//   }

//   function test_ProperlySetsConstructorArguments() public {
//     erc721VotesToken.mint(address(this), 1_000_000e18); // we use erc721VotesToken because IVotesToken is an
// interface
//     // without the `mint` function

//     llamaERC721TokenHolderCaster = new LlamaERC721TokenHolderCaster(
//       erc721VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, DEFAULT_APPROVAL_THRESHOLD,
// DEFAULT_APPROVAL_THRESHOLD
//     );

//     assertEq(address(llamaERC721TokenHolderCaster.LLAMA_CORE()), address(CORE));
//     assertEq(address(llamaERC721TokenHolderCaster.TOKEN()), address(erc721VotesToken));
//     assertEq(llamaERC721TokenHolderCaster.ROLE(), tokenVotingCasterRole);
//     assertEq(llamaERC721TokenHolderCaster.MIN_APPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//     assertEq(llamaERC721TokenHolderCaster.MIN_DISAPPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//   }
// }

contract CastApproval is LlamaERC721TokenHolderCasterTest {
  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenHolderCaster.castVote(notActionInfo, 1, "");
  }

  function test_RevertsIf_ApprovalNotEnabled() public {
    LlamaERC721TokenHolderCaster casterWithWrongRole = LlamaERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(llamaERC721TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
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
    vm.expectRevert(LlamaTokenHolderCaster.ActionNotActive.selector);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_AlreadyCastedVote() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");

    vm.expectRevert(LlamaTokenHolderCaster.AlreadyCastedVote.selector);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InvalidSupport.selector, uint8(3)));
    llamaERC721TokenHolderCaster.castVote(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    vm.warp(block.timestamp + ((1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS) + 1); // 2/3 of the approval period
    vm.expectRevert(LlamaTokenHolderCaster.CastingPeriodOver.selector);
    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InsufficientBalance.selector, 0));
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_CastsApprovalCorrectly(uint8 support) public {
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
    llamaERC721TokenHolderCaster.castVote(actionInfo, support, "");
  }

  function test_CastsApprovalCorrectly_WithReason() public {
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
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "reason");
  }
}

contract CastApprovalBySig is LlamaERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenHolderCasterTest.setUp();
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CastApproval memory castApproval = LlamaCoreSigUtils.CastApproval({
      actionInfo: _actionInfo,
      support: 1,
      reason: "",
      tokenHolder: tokenHolder1,
      nonce: 0
    });
    bytes32 digest = getCastApprovalTypedDataHash(castApproval);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function castApprovalBySig(ActionInfo memory _actionInfo, uint8 support, uint8 v, bytes32 r, bytes32 s) internal {
    llamaERC721TokenHolderCaster.castVoteBySig(tokenHolder1, support, _actionInfo, "", v, r, s);
  }

  function test_CastsApprovalBySig() public {
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

    castApprovalBySig(actionInfo, 1, v, r, s);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(llamaERC721TokenHolderCaster.nonces(tokenHolder1, LlamaTokenHolderCaster.castVoteBySig.selector), 0);
    castApprovalBySig(actionInfo, 1, v, r, s);
    assertEq(llamaERC721TokenHolderCaster.nonces(tokenHolder1, LlamaTokenHolderCaster.castVoteBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    castApprovalBySig(actionInfo, 1, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenholder since nonce has increased.
    vm.expectRevert(LlamaTokenHolderCaster.InvalidSignature.selector);
    castApprovalBySig(actionInfo, 1, v, r, s);
  }

  function test_RevertIf_SignerIsNotTokenHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the erc20VotesTokenholder passed
    // in as parameter.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castApprovalBySig(actionInfo, 1, v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castApprovalBySig(actionInfo, 1, (v + 1), r, s);
  }

  function test_RevertIf_TokenHolderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.incrementNonce(ILlamaCore.castApprovalBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as
    // erc20VotesTokenholder since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castApprovalBySig(actionInfo, 1, v, r, s);
  }
}

contract CastDisapproval is LlamaERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenHolderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenHolderCaster.castVeto(notActionInfo, tokenVotingCasterRole, "");
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    LlamaERC721TokenHolderCaster casterWithWrongRole = LlamaERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(llamaERC721TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, madeUpRole, ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVeto(actionInfo, madeUpRole, "");
  }

  function test_RevertsIf_AlreadyCastedVote() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");

    vm.expectRevert(LlamaTokenHolderCaster.AlreadyCastedVeto.selector);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InvalidSupport.selector, uint8(3)));
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + 2 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS); // 2/3 of the approval period
    vm.expectRevert(LlamaTokenHolderCaster.CastingPeriodOver.selector);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InsufficientBalance.selector, 0));
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_CastsDisapprovalCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      support,
      erc721VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );
    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, support, "");
  }

  function test_CastsDisapprovalCorrectly_WithReason() public {
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "reason");
  }
}

contract CastDisapprovalBySig is LlamaERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenHolderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CastDisapproval memory castDisapproval = LlamaCoreSigUtils.CastDisapproval({
      actionInfo: _actionInfo,
      support: 1,
      reason: "",
      tokenHolder: tokenHolder1,
      nonce: 0
    });
    bytes32 digest = getCastDisapprovalTypedDataHash(castDisapproval);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function castDisapprovalBySig(ActionInfo memory _actionInfo, uint8 v, bytes32 r, bytes32 s) internal {
    llamaERC721TokenHolderCaster.castVetoBySig(tokenHolder1, 1, _actionInfo, "", v, r, s);
  }

  function test_CastsDisapprovalBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      ""
    );

    castDisapprovalBySig(actionInfo, v, r, s);

    // assertEq(CORE.getAction(0).totalDisapprovals, 1);
    // assertEq(CORE.disapprovals(0, disapproverDrake), true);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(llamaERC721TokenHolderCaster.nonces(tokenHolder1, ILlamaCore.castDisapprovalBySig.selector), 0);
    castDisapprovalBySig(actionInfo, v, r, s);
    assertEq(llamaERC721TokenHolderCaster.nonces(tokenHolder1, ILlamaCore.castDisapprovalBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    castDisapprovalBySig(actionInfo, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castDisapprovalBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsNotPolicyHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castDisapprovalBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castDisapprovalBySig(actionInfo, (v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.incrementNonce(ILlamaCore.castDisapprovalBySig.selector);

    // Invalid Signature error since the recovered signer address during the second call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castDisapprovalBySig(actionInfo, v, r, s);
  }

  function test_FailsIfDisapproved() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    // First disapproval.
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc721VotesToken.getPastVotes(tokenHolder1, erc721VotesToken.clock() - 1),
      ""
    );
    castDisapprovalBySig(actionInfo, v, r, s);
    // assertEq(CORE.getAction(actionInfo.id).totalDisapprovals, 1);

    // Second disapproval.
    vm.prank(tokenHolder2);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");

    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);

    // Assertions.
    ActionState state = ActionState(CORE.getActionState(actionInfo));
    assertEq(uint8(state), uint8(ActionState.Failed));

    vm.expectRevert(abi.encodeWithSelector(ILlamaCore.InvalidActionState.selector, ActionState.Failed));
    CORE.executeAction(actionInfo);
  }
}

contract SubmitApprovals is LlamaERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenHolderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenHolderCaster.submitApproval(notActionInfo);
  }

  function test_RevertsIf_AlreadySubmittedApproval() public {
    vm.startPrank(tokenHolder1);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);

    vm.expectRevert(LlamaTokenHolderCaster.AlreadySubmittedApproval.selector);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + ((1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS) + 2); // 1/3 of the approval period
    vm.expectRevert(LlamaTokenHolderCaster.SubmissionPeriodOver.selector);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_InsufficientVotes() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InsufficientVotes.selector, 0, 1));
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(LlamaTokenHolderCaster.CannotSubmitYet.selector);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    llamaERC721TokenHolderCaster.castVote(actionInfo, 0, "");

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function test_SubmitsApprovalsCorrectly() public {
    vm.expectEmit();
    emit ApprovalSubmitted(actionInfo.id, 3, 0, 0);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }
}

contract SubmitDisapprovals is LlamaERC721TokenHolderCasterTest {
  function setUp() public virtual override {
    LlamaERC721TokenHolderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    llamaERC721TokenHolderCaster.submitApproval(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    llamaERC721TokenHolderCaster.submitDisapproval(notActionInfo);
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    LlamaERC721TokenHolderCaster casterWithWrongRole = LlamaERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(llamaERC721TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc721VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(
      erc721VotesToken, CORE, madeUpRole, ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_AlreadySubmittedDisapproval() public {
    Action memory action = CORE.getAction(actionInfo.id);
    vm.warp(
      action.minExecutionTime
        - (ILlamaRelativeStrategyBase(address(actionInfo.strategy)).queuingPeriod() * ONE_THIRD_IN_BPS)
          / ONE_HUNDRED_IN_BPS
    );

    castDisapprovalsFor();

    vm.startPrank(tokenHolder1);
    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);

    vm.expectRevert(LlamaTokenHolderCaster.AlreadySubmittedDisapproval.selector);
    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    castDisapprovalsFor();

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(LlamaTokenHolderCaster.SubmissionPeriodOver.selector);
    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_InsufficientDisapprovals() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    castApprovalsFor();
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    llamaERC721TokenHolderCaster.submitApproval(actionInfo);

    //TODO why add 1 here
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.InsufficientVotes.selector, 0, 1));
    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(LlamaTokenHolderCaster.CannotSubmitYet.selector);
    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    vm.prank(tokenHolder1);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    llamaERC721TokenHolderCaster.castVeto(actionInfo, 0, "");
    // TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(LlamaTokenHolderCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);
  }

  function test_SubmitsDisapprovalsCorrectly() public {
    castDisapprovalsFor();

    //TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectEmit();
    emit DisapprovalSubmitted(actionInfo.id, 3, 0, 0);
    llamaERC721TokenHolderCaster.submitDisapproval(actionInfo);
  }
}

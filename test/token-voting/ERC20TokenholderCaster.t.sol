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
import {ERC20TokenholderCaster} from "src/token-voting/ERC20TokenholderCaster.sol";
import {TokenholderCaster} from "src/token-voting/TokenholderCaster.sol";

contract ERC20TokenholderCasterTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
  event ApprovalCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event ApprovalsSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  event DisapprovalCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event DisapprovalsSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  ActionInfo actionInfo;
  ERC20TokenholderCaster erc20TokenholderCaster;
  ILlamaStrategy tokenVotingStrategy;

  function setUp() public virtual override {
    LlamaTokenVotingTestSetup.setUp();

    // Mint tokens to tokenholders so that there is an existing supply
    erc20VotesToken.mint(tokenHolder1, ERC20_CREATION_THRESHOLD / 2);
    vm.prank(tokenHolder1);
    erc20VotesToken.delegate(tokenHolder1);

    erc20VotesToken.mint(tokenHolder2, ERC20_CREATION_THRESHOLD / 2);
    vm.prank(tokenHolder2);
    erc20VotesToken.delegate(tokenHolder2);

    erc20VotesToken.mint(tokenHolder3, ERC20_CREATION_THRESHOLD / 2);
    vm.prank(tokenHolder3);
    erc20VotesToken.delegate(tokenHolder3);

    // Mine block so that the ERC20 and ERC721 supply will be available when doing a past timestamp check at initialize
    // during deployment.
    mineBlock();

    // Deploy ERC20 Token Voting Module.
    (, erc20TokenholderCaster) = _deployERC20TokenVotingModuleAndSetRole();

    // Mine block so that Token Voting Caster Role will have supply during action creation (due to past timestamp check)
    mineBlock();

    tokenVotingStrategy = _deployRelativeQuantityQuorumAndSetRolePermissionToCoreTeam(tokenVotingCasterRole);
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    // Setting ERC20TokenholderCaster's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(erc20TokenholderCaster)
      })
    );
  }

  function castApprovalsFor() public {
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
  }

  function castDisapprovalsFor() public {
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");
  }
}

// contract Constructor is ERC20TokenholderCasterTest {
//   function test_RevertsIf_InvalidLlamaCoreAddress() public {
//     // With invalid LlamaCore instance, TokenholderActionCreator.InvalidLlamaCoreAddress is unreachable
//     vm.expectRevert();
//     new ERC20TokenholderCaster(
//       erc20VotesToken, ILlamaCore(makeAddr("invalid-llama-core")), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidTokenAddress(address notAToken) public {
//     vm.assume(notAToken != address(0));
//     vm.assume(notAToken != address(erc20VotesToken));
//     vm.expectRevert(); // will revert with EvmError: Revert because `totalSupply` is not a function
//     new ERC20TokenholderCaster(
//       ERC20Votes(notAToken), ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidRole(uint8 role) public {
//     role = uint8(bound(role, POLICY.numRoles(), 255));
//     vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.RoleNotInitialized.selector, uint8(255)));
//     new ERC20TokenholderCaster(erc20VotesToken, ILlamaCore(address(CORE)), uint8(255), uint256(1), uint256(1));
//   }

//   function test_RevertsIf_InvalidMinApprovalPct() public {
//     vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinApprovalPct.selector, uint256(0)));
//     new ERC20TokenholderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(0),
// uint256(1));
//     vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinApprovalPct.selector, uint256(10_001)));
//     new ERC20TokenholderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(10_001),
// uint256(1));
//   }

//   function test_RevertsIf_InvalidMinDisapprovalPct() public {
//     vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinDisapprovalPct.selector, uint256(0)));
//     new ERC20TokenholderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(0));
//     vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinDisapprovalPct.selector, uint256(10_001)));
//     new ERC20TokenholderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(10_001));
//   }

//   function test_ProperlySetsConstructorArguments() public {
//     erc20VotesToken.mint(address(this), 1_000_000e18); // we use erc20VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     erc20TokenholderCaster = new ERC20TokenholderCaster(
//       erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, DEFAULT_APPROVAL_THRESHOLD,
// DEFAULT_APPROVAL_THRESHOLD
//     );

//     assertEq(address(erc20TokenholderCaster.LLAMA_CORE()), address(CORE));
//     assertEq(address(erc20TokenholderCaster.TOKEN()), address(erc20VotesToken));
//     assertEq(erc20TokenholderCaster.ROLE(), tokenVotingCasterRole);
//     assertEq(erc20TokenholderCaster.MIN_APPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//     assertEq(erc20TokenholderCaster.MIN_DISAPPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//   }
// }

contract CastApproval is ERC20TokenholderCasterTest {
  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenholderCaster.castApproval(notActionInfo, 1, "");
  }

  function test_RevertsIf_ApprovalNotEnabled() public {
    ERC20TokenholderCaster casterWithWrongRole = ERC20TokenholderCaster(
      Clones.cloneDeterministic(
        address(erc20TokenholderCasterLogic), keccak256(abi.encodePacked(address(erc20VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(erc20VotesToken, CORE, madeUpRole, ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT);

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castApproval(actionInfo, 1, "");
  }

  function test_RevertsIf_ActionNotActive() public {
    vm.warp(block.timestamp + 1 days + 1);
    vm.expectRevert(TokenholderCaster.ActionNotActive.selector);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
  }

  function test_RevertsIf_AlreadyCastApproval() public {
    vm.startPrank(tokenHolder1);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");

    vm.expectRevert(TokenholderCaster.AlreadyCastApproval.selector);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidSupport.selector, uint8(3)));
    erc20TokenholderCaster.castApproval(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    vm.warp(block.timestamp + ((1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS) + 1); // 2/3 of the approval period
    vm.expectRevert(TokenholderCaster.CastingPeriodOver.selector);
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientBalance.selector, 0));
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
  }

  function test_CastsApprovalCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit ApprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      support,
      erc20VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castApproval(actionInfo, support, "");
  }

  function test_CastsApprovalCorrectly_WithReason() public {
    vm.expectEmit();
    emit ApprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "reason");
  }
}

contract CastApprovalBySig is ERC20TokenholderCasterTest {
  function setUp() public virtual override {
    ERC20TokenholderCasterTest.setUp();
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
    erc20TokenholderCaster.castApprovalBySig(tokenHolder1, support, _actionInfo, "", v, r, s);
  }

  function test_CastsApprovalBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit ApprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );

    castApprovalBySig(actionInfo, 1, v, r, s);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(erc20TokenholderCaster.nonces(tokenHolder1, TokenholderCaster.castApprovalBySig.selector), 0);
    castApprovalBySig(actionInfo, 1, v, r, s);
    assertEq(erc20TokenholderCaster.nonces(tokenHolder1, TokenholderCaster.castApprovalBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    castApprovalBySig(actionInfo, 1, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // erc20VotesTokenholder since nonce has increased.
    vm.expectRevert(TokenholderCaster.InvalidSignature.selector);
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
    erc20TokenholderCaster.incrementNonce(ILlamaCore.castApprovalBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as
    // erc20VotesTokenholder since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castApprovalBySig(actionInfo, 1, v, r, s);
  }
}

contract CastDisapproval is ERC20TokenholderCasterTest {
  function setUp() public virtual override {
    ERC20TokenholderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    erc20TokenholderCaster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenholderCaster.castDisapproval(notActionInfo, tokenVotingCasterRole, "");
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    ERC20TokenholderCaster casterWithWrongRole = ERC20TokenholderCaster(
      Clones.cloneDeterministic(
        address(erc20TokenholderCasterLogic), keccak256(abi.encodePacked(address(erc20VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(erc20VotesToken, CORE, madeUpRole, ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT);

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castDisapproval(actionInfo, madeUpRole, "");
  }

  function test_RevertsIf_AlreadyCastApproval() public {
    vm.startPrank(tokenHolder1);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");

    vm.expectRevert(TokenholderCaster.AlreadyCastDisapproval.selector);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidSupport.selector, uint8(3)));
    erc20TokenholderCaster.castDisapproval(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + 2 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS); // 2/3 of the approval period
    vm.expectRevert(TokenholderCaster.CastingPeriodOver.selector);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientBalance.selector, 0));
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");
  }

  function test_CastsDisapprovalCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      support,
      erc20VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castDisapproval(actionInfo, support, "");
  }

  function test_CastsDisapprovalCorrectly_WithReason() public {
    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "reason");
  }
}

contract CastDisapprovalBySig is ERC20TokenholderCasterTest {
  function setUp() public virtual override {
    ERC20TokenholderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    erc20TokenholderCaster.submitApprovals(actionInfo);
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
    erc20TokenholderCaster.castDisapprovalBySig(tokenHolder1, 1, _actionInfo, "", v, r, s);
  }

  function test_CastsDisapprovalBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      ""
    );

    castDisapprovalBySig(actionInfo, v, r, s);

    // assertEq(CORE.getAction(0).totalDisapprovals, 1);
    // assertEq(CORE.disapprovals(0, disapproverDrake), true);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(erc20TokenholderCaster.nonces(tokenHolder1, ILlamaCore.castDisapprovalBySig.selector), 0);
    castDisapprovalBySig(actionInfo, v, r, s);
    assertEq(erc20TokenholderCaster.nonces(tokenHolder1, ILlamaCore.castDisapprovalBySig.selector), 1);
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
    erc20TokenholderCaster.incrementNonce(ILlamaCore.castDisapprovalBySig.selector);

    // Invalid Signature error since the recovered signer address during the second call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castDisapprovalBySig(actionInfo, v, r, s);
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
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      ""
    );
    castDisapprovalBySig(actionInfo, v, r, s);
    // assertEq(CORE.getAction(actionInfo.id).totalDisapprovals, 1);

    // Second disapproval.
    vm.prank(tokenHolder2);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");

    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    erc20TokenholderCaster.submitDisapprovals(actionInfo);

    // Assertions.
    ActionState state = ActionState(CORE.getActionState(actionInfo));
    assertEq(uint8(state), uint8(ActionState.Failed));

    vm.expectRevert(abi.encodeWithSelector(ILlamaCore.InvalidActionState.selector, ActionState.Failed));
    CORE.executeAction(actionInfo);
  }
}

contract SubmitApprovals is ERC20TokenholderCasterTest {
  function setUp() public virtual override {
    ERC20TokenholderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenholderCaster.submitApprovals(notActionInfo);
  }

  function test_RevertsIf_AlreadySubmittedApproval() public {
    vm.startPrank(tokenHolder1);
    erc20TokenholderCaster.submitApprovals(actionInfo);

    vm.expectRevert(TokenholderCaster.AlreadySubmittedApproval.selector);
    erc20TokenholderCaster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + ((1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS) + 2); // 1/3 of the approval period
    vm.expectRevert(TokenholderCaster.SubmissionPeriodOver.selector);
    erc20TokenholderCaster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_InsufficientApprovals() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientApprovals.selector, 0, 75_000e18));
    erc20TokenholderCaster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(TokenholderCaster.CantSubmitYet.selector);
    erc20TokenholderCaster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castApproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenholderCaster.castApproval(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    erc20TokenholderCaster.castApproval(actionInfo, 0, "");

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.ForDoesNotSurpassAgainst.selector, 250_000e18, 500_000e18));
    erc20TokenholderCaster.submitApprovals(actionInfo);
  }

  function test_SubmitsApprovalsCorrectly() public {
    vm.expectEmit();
    emit ApprovalsSubmitted(actionInfo.id, 750_000e18, 0, 0);
    erc20TokenholderCaster.submitApprovals(actionInfo);
  }
}

contract SubmitDisapprovals is ERC20TokenholderCasterTest {
  function setUp() public virtual override {
    ERC20TokenholderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    erc20TokenholderCaster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenholderCaster.submitDisapprovals(notActionInfo);
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    ERC20TokenholderCaster casterWithWrongRole = ERC20TokenholderCaster(
      Clones.cloneDeterministic(
        address(erc20TokenholderCasterLogic), keccak256(abi.encodePacked(address(erc20VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(erc20VotesToken, CORE, madeUpRole, ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT);
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.submitDisapprovals(actionInfo);
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
    erc20TokenholderCaster.submitDisapprovals(actionInfo);

    vm.expectRevert(TokenholderCaster.AlreadySubmittedDisapproval.selector);
    erc20TokenholderCaster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    castDisapprovalsFor();

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(TokenholderCaster.SubmissionPeriodOver.selector);
    erc20TokenholderCaster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_InsufficientDisapprovals() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    castApprovalsFor();
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    erc20TokenholderCaster.submitApprovals(actionInfo);

    //TODO why add 1 here
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientApprovals.selector, 0, 75_000e18));
    erc20TokenholderCaster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(TokenholderCaster.CantSubmitYet.selector);
    erc20TokenholderCaster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    vm.prank(tokenHolder1);
    erc20TokenholderCaster.castDisapproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenholderCaster.castDisapproval(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    erc20TokenholderCaster.castDisapproval(actionInfo, 0, "");
    // TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.ForDoesNotSurpassAgainst.selector, 250_000e18, 500_000e18));
    erc20TokenholderCaster.submitDisapprovals(actionInfo);
  }

  function test_SubmitsDisapprovalsCorrectly() public {
    castDisapprovalsFor();

    //TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectEmit();
    emit DisapprovalsSubmitted(actionInfo.id, 750_000e18, 0, 0);
    erc20TokenholderCaster.submitDisapprovals(actionInfo);
  }
}

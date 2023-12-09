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
import {ERC20TokenHolderCaster} from "src/token-voting/ERC20TokenHolderCaster.sol";
import {TokenHolderCaster} from "src/token-voting/TokenHolderCaster.sol";

contract ERC20TokenHolderCasterTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
  uint256 constant DEFAULT_APPROVAL_THRESHOLD = 1000;

  event VoteCast(
    uint256 id, address indexed tokenHolder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event VotesSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  event VetoCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event VetosSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  ActionInfo actionInfo;
  ERC20TokenHolderCaster erc20TokenHolderCaster;
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
    (, erc20TokenHolderCaster) = _deployERC20TokenVotingModuleAndSetRole();

    // Mine block so that Token Voting Caster Role will have supply during action creation (due to past timestamp check)
    mineBlock();

    tokenVotingStrategy = _deployRelativeQuantityQuorumAndSetRolePermissionToCoreTeam(tokenVotingCasterRole);
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    // Setting ERC20TokenHolderCaster's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(erc20TokenHolderCaster)
      })
    );
  }

  function castVoteFor() public {
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function castVetosFor() public {
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");
  }
}

// contract Constructor is ERC20TokenHolderCasterTest {
//   function test_RevertsIf_InvalidLlamaCoreAddress() public {
//     // With invalid LlamaCore instance, TokenHolderActionCreator.InvalidLlamaCoreAddress is unreachable
//     vm.expectRevert();
//     new ERC20TokenHolderCaster(
//       erc20VotesToken, ILlamaCore(makeAddr("invalid-llama-core")), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidTokenAddress(address notAToken) public {
//     vm.assume(notAToken != address(0));
//     vm.assume(notAToken != address(erc20VotesToken));
//     vm.expectRevert(); // will revert with EvmError: Revert because `totalSupply` is not a function
//     new ERC20TokenHolderCaster(
//       ERC20Votes(notAToken), ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1), uint256(1)
//     );
//   }

//   function test_RevertsIf_InvalidRole(uint8 role) public {
//     role = uint8(bound(role, POLICY.numRoles(), 255));
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.RoleNotInitialized.selector, uint8(255)));
//     new ERC20TokenHolderCaster(erc20VotesToken, ILlamaCore(address(CORE)), uint8(255), uint256(1), uint256(1));
//   }

//   function test_RevertsIf_InvalidMinVotesPct() public {
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinVotesPct.selector, uint256(0)));
//     new ERC20TokenHolderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(0),
// uint256(1));
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinVotesPct.selector, uint256(10_001)));
//     new ERC20TokenHolderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(10_001),
// uint256(1));
//   }

//   function test_RevertsIf_InvalidMinVetoPct() public {
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinVetoPct.selector, uint256(0)));
//     new ERC20TokenHolderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(0));
//     vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidMinVetoPct.selector, uint256(10_001)));
//     new ERC20TokenHolderCaster(erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, uint256(1),
// uint256(10_001));
//   }

//   function test_ProperlySetsConstructorArguments() public {
//     erc20VotesToken.mint(address(this), 1_000_000e18); // we use erc20VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     erc20TokenHolderCaster = new ERC20TokenHolderCaster(
//       erc20VotesToken, ILlamaCore(address(CORE)), tokenVotingCasterRole, DEFAULT_APPROVAL_THRESHOLD,
// DEFAULT_APPROVAL_THRESHOLD
//     );

//     assertEq(address(erc20TokenHolderCaster.LLAMA_CORE()), address(CORE));
//     assertEq(address(erc20TokenHolderCaster.TOKEN()), address(erc20VotesToken));
//     assertEq(erc20TokenHolderCaster.ROLE(), tokenVotingCasterRole);
//     assertEq(erc20TokenHolderCaster.MIN_APPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//     assertEq(erc20TokenHolderCaster.MIN_DISAPPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
//   }
// }

contract CastVote is ERC20TokenHolderCasterTest {
  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenHolderCaster.castVote(notActionInfo, 1, "");
  }

  function test_RevertsIf_VotesNotEnabled() public {
    ERC20TokenHolderCaster casterWithWrongRole = ERC20TokenHolderCaster(
      Clones.cloneDeterministic(
        address(erc20TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc20VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(erc20VotesToken, CORE, madeUpRole, ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT);

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_ActionNotActive() public {
    vm.warp(block.timestamp + 1 days + 1);
    vm.expectRevert(TokenHolderCaster.ActionNotActive.selector);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_AlreadyCastVote() public {
    vm.startPrank(tokenHolder1);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");

    vm.expectRevert(TokenHolderCaster.AlreadyCastVote.selector);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidSupport.selector, uint8(3)));
    erc20TokenHolderCaster.castVote(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    vm.warp(block.timestamp + ((1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS) + 1); // 2/3 of the voting period
    vm.expectRevert(TokenHolderCaster.CastingPeriodOver.selector);
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientBalance.selector, 0));
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
  }

  function test_CastsVoteCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      support,
      erc20VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVote(actionInfo, support, "");
  }

  function test_CastsVoteCorrectly_WithReason() public {
    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "reason");
  }
}

contract CastVoteBySig is ERC20TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC20TokenHolderCasterTest.setUp();
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
    erc20TokenHolderCaster.castVoteBySig(tokenHolder1, support, _actionInfo, "", v, r, s);
  }

  function test_CastsVoteBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit VoteCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );

    castVoteBySig(actionInfo, 1, v, r, s);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(erc20TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVoteBySig.selector), 0);
    castVoteBySig(actionInfo, 1, v, r, s);
    assertEq(erc20TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVoteBySig.selector), 1);
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
    erc20TokenHolderCaster.incrementNonce(TokenHolderCaster.castVoteBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as
    // erc20VotesTokenHolder since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVoteBySig(actionInfo, 1, v, r, s);
  }
}

contract CastVeto is ERC20TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC20TokenHolderCasterTest.setUp();

    castVoteFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenHolderCaster.castVeto(notActionInfo, tokenVotingCasterRole, "");
  }

  function test_RevertsIf_VetoNotEnabled() public {
    ERC20TokenHolderCaster casterWithWrongRole = ERC20TokenHolderCaster(
      Clones.cloneDeterministic(
        address(erc20TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc20VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(erc20VotesToken, CORE, madeUpRole, ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT);

    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, tokenVotingCasterRole));
    casterWithWrongRole.castVeto(actionInfo, madeUpRole, "");
  }

  function test_RevertsIf_AlreadyCastVote() public {
    vm.startPrank(tokenHolder1);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");

    vm.expectRevert(TokenHolderCaster.AlreadyCastVeto.selector);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InvalidSupport.selector, uint8(3)));
    erc20TokenHolderCaster.castVeto(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + 2 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS); // 2/3 of the voting period
    vm.expectRevert(TokenHolderCaster.CastingPeriodOver.selector);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientBalance.selector, 0));
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");
  }

  function test_CastsVetoCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      support,
      erc20VotesToken.getPastVotes(tokenHolder1, block.timestamp - 1),
      ""
    );
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVeto(actionInfo, support, "");
  }

  function test_CastsVetoCorrectly_WithReason() public {
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      "reason"
    );
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "reason");
  }
}

contract CastVetoBySig is ERC20TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC20TokenHolderCasterTest.setUp();

    castVoteFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.submitVotes(actionInfo);
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
    erc20TokenHolderCaster.castVetoBySig(tokenHolder1, 1, _actionInfo, "", v, r, s);
  }

  function test_CastsVetoBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      ""
    );

    castVetoBySig(actionInfo, v, r, s);

    // assertEq(CORE.getAction(0).totalVetos, 1);
    // assertEq(CORE.vetos(0, disapproverDrake), true);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(erc20TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVetoBySig.selector), 0);
    castVetoBySig(actionInfo, v, r, s);
    assertEq(erc20TokenHolderCaster.nonces(tokenHolder1, TokenHolderCaster.castVetoBySig.selector), 1);
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
    erc20TokenHolderCaster.incrementNonce(TokenHolderCaster.castVetoBySig.selector);

    // Invalid Signature error since the recovered signer address during the second call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    castVetoBySig(actionInfo, v, r, s);
  }

  function test_FailsIfVetoed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    // First veto.
    vm.expectEmit();
    emit VetoCast(
      actionInfo.id,
      tokenHolder1,
      tokenVotingCasterRole,
      1,
      erc20VotesToken.getPastVotes(tokenHolder1, erc20VotesToken.clock() - 1),
      ""
    );
    castVetoBySig(actionInfo, v, r, s);
    // assertEq(CORE.getAction(actionInfo.id).totalVetos, 1);

    // Second veto.
    vm.prank(tokenHolder2);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");

    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    erc20TokenHolderCaster.submitVetos(actionInfo);

    // Assertions.
    ActionState state = ActionState(CORE.getActionState(actionInfo));
    assertEq(uint8(state), uint8(ActionState.Failed));

    vm.expectRevert(abi.encodeWithSelector(ILlamaCore.InvalidActionState.selector, ActionState.Failed));
    CORE.executeAction(actionInfo);
  }
}

contract SubmitVotes is ERC20TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC20TokenHolderCasterTest.setUp();

    castVoteFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenHolderCaster.submitVotes(notActionInfo);
  }

  function test_RevertsIf_AlreadySubmittedVotes() public {
    vm.startPrank(tokenHolder1);
    erc20TokenHolderCaster.submitVotes(actionInfo);

    vm.expectRevert(TokenHolderCaster.AlreadySubmittedVotes.selector);
    erc20TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + ((1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS) + 2); // 1/3 of the voting period
    vm.expectRevert(TokenHolderCaster.SubmissionPeriodOver.selector);
    erc20TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_InsufficientVotes() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientVotes.selector, 0, 75_000e18));
    erc20TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * ONE_THIRD_IN_BPS) / ONE_HUNDRED_IN_BPS); // 1/3 of the voting period
    vm.expectRevert(TokenHolderCaster.CantSubmitYet.selector);
    erc20TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);

    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVote(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenHolderCaster.castVote(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    erc20TokenHolderCaster.castVote(actionInfo, 0, "");

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.ForDoesNotSurpassAgainst.selector, 250_000e18, 500_000e18));
    erc20TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_SubmitsVotesCorrectly() public {
    vm.expectEmit();
    emit VotesSubmitted(actionInfo.id, 750_000e18, 0, 0);
    erc20TokenHolderCaster.submitVotes(actionInfo);
  }
}

contract SubmitVetos is ERC20TokenHolderCasterTest {
  function setUp() public virtual override {
    ERC20TokenHolderCasterTest.setUp();

    castVoteFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    erc20TokenHolderCaster.submitVotes(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    erc20TokenHolderCaster.submitVetos(notActionInfo);
  }

  function test_RevertsIf_VetoNotEnabled() public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    ERC20TokenHolderCaster casterWithWrongRole = ERC20TokenHolderCaster(
      Clones.cloneDeterministic(
        address(erc20TokenHolderCasterLogic), keccak256(abi.encodePacked(address(erc20VotesToken), msg.sender))
      )
    );
    casterWithWrongRole.initialize(erc20VotesToken, CORE, madeUpRole, ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT);
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
    erc20TokenHolderCaster.submitVetos(actionInfo);

    vm.expectRevert(TokenHolderCaster.AlreadySubmittedVetos.selector);
    erc20TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    castVetosFor();

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(TokenHolderCaster.SubmissionPeriodOver.selector);
    erc20TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_InsufficientVetos() public {
    actionInfo = _createActionWithTokenVotingStrategy(tokenVotingStrategy);
    castVoteFor();
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    erc20TokenHolderCaster.submitVotes(actionInfo);

    //TODO why add 1 here
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.InsufficientVotes.selector, 0, 75_000e18));
    erc20TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the voting period
    vm.expectRevert(TokenHolderCaster.CantSubmitYet.selector);
    erc20TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    vm.prank(tokenHolder1);
    erc20TokenHolderCaster.castVeto(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    erc20TokenHolderCaster.castVeto(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    erc20TokenHolderCaster.castVeto(actionInfo, 0, "");
    // TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenHolderCaster.ForDoesNotSurpassAgainst.selector, 250_000e18, 500_000e18));
    erc20TokenHolderCaster.submitVetos(actionInfo);
  }

  function test_SubmitsVetosCorrectly() public {
    castVetosFor();

    //TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectEmit();
    emit VetosSubmitted(actionInfo.id, 750_000e18, 0, 0);
    erc20TokenHolderCaster.submitVetos(actionInfo);
  }
}

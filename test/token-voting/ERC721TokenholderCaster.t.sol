// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {MockERC721Votes} from "test/mock/MockERC721Votes.sol";
import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {Action, ActionInfo, PermissionData} from "src/lib/Structs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaRelativeStrategyBase} from "src/interfaces/ILlamaRelativeStrategyBase.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ERC721Votes} from "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {ERC721TokenholderCaster} from "src/token-voting/ERC721TokenholderCaster.sol";
import {TokenholderCaster} from "src/token-voting/TokenholderCaster.sol";

contract ERC721TokenholderCasterTest is LlamaTokenVotingTestSetup {
  uint256 constant DEFAULT_APPROVAL_THRESHOLD = 2;
  uint16 constant ONE_HUNDRED_IN_BPS = 10_000;
  uint256 constant ONE_THIRD_IN_BPS = 3333;
  uint256 constant TWO_THIRDS_IN_BPS = 6667;
  uint8 constant CASTER_ROLE = 2;
  uint8 constant MADE_UP_ROLE = 3;

  MockERC721Votes mockErc721Votes;
  ERC721Votes token; // this is the same token as
  // mockErc721Votes, when we mint on one it will be reflected on the other

  ActionInfo actionInfo;
  ERC721TokenholderCaster caster;

  ILlamaStrategy tokenVotingStrategy;

  address tokenHolder1 = makeAddr("tokenholder-1");
  address tokenHolder2 = makeAddr("tokenholder-2");
  address tokenHolder3 = makeAddr("tokenholder-3");

  event ApprovalCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event ApprovalsSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  event DisapprovalCast(
    uint256 id, address indexed policyholder, uint8 indexed role, uint8 indexed support, uint256 quantity, string reason
  );

  event DisapprovalsSubmitted(uint256 id, uint96 quantityFor, uint96 quantityAgainst, uint96 quantityAbstain);

  // =========================
  // ======== Helpers ========
  // =========================

  function createAction(ILlamaStrategy strategy) public returns (ActionInfo memory _actionInfo) {
    bytes memory data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Action Caster")));
    vm.prank(coreTeam1);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, strategy, address(POLICY), 0, data, "");
    _actionInfo = ActionInfo(actionId, coreTeam1, CORE_TEAM_ROLE, strategy, address(POLICY), 0, data);
    vm.warp(block.timestamp + 1);
  }

  function deployRelativeQuantityQuorumAndSetRole(address _policyHolder, uint8 role)
    internal
    returns (ILlamaStrategy newStrategy)
  {
    {
      vm.prank(address(EXECUTOR));
      POLICY.setRoleHolder(role, _policyHolder, 1, type(uint64).max);
    }

    uint8[] memory forceRoles = new uint8[](0);

    ILlamaRelativeStrategyBase.Config memory strategyConfig = ILlamaRelativeStrategyBase.Config({
      approvalPeriod: 1 days,
      queuingPeriod: 1 days,
      expirationPeriod: 1 days,
      isFixedLengthApprovalPeriod: false,
      minApprovalPct: ONE_HUNDRED_IN_BPS,
      minDisapprovalPct: ONE_HUNDRED_IN_BPS,
      approvalRole: role,
      disapprovalRole: role,
      forceApprovalRoles: forceRoles,
      forceDisapprovalRoles: forceRoles
    });

    ILlamaRelativeStrategyBase.Config[] memory strategyConfigs = new ILlamaRelativeStrategyBase.Config[](1);
    strategyConfigs[0] = strategyConfig;

    vm.prank(address(EXECUTOR));

    CORE.createStrategies(RELATIVE_QUANTITY_QUORUM_LOGIC, encodeStrategyConfigs(strategyConfigs));

    newStrategy = ILlamaStrategy(
      LENS.computeLlamaStrategyAddress(
        address(RELATIVE_QUANTITY_QUORUM_LOGIC), encodeStrategy(strategyConfig), address(CORE)
      )
    );

    {
      ILlamaPolicy.PermissionData memory _permissionData =
        ILlamaPolicy.PermissionData(address(POLICY), POLICY.initializeRole.selector, address(newStrategy));
      vm.prank(address(EXECUTOR));
      POLICY.setRolePermission(CORE_TEAM_ROLE, _permissionData, true);
    }
  }

  function setUp() public virtual override {
    PeripheryTestSetup.setUp();
    vm.deal(address(this), 1 ether);
    vm.deal(address(msg.sender), 1 ether);
    vm.deal(address(EXECUTOR), 1 ether);
    vm.deal(tokenHolder1, 1 ether);
    vm.deal(tokenHolder2, 1 ether);
    vm.deal(tokenHolder3, 1 ether);

    mockErc721Votes = new MockERC721Votes();
    token = ERC721Votes(address(mockErc721Votes));

    vm.prank(address(EXECUTOR));
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Caster Role")); // initializes role 2
    vm.prank(address(EXECUTOR));
    POLICY.initializeRole(RoleDescription.wrap("Made Up Role")); // initializes role 2

    mockErc721Votes.mint(tokenHolder1, 0);
    mockErc721Votes.mint(tokenHolder2, 1);
    mockErc721Votes.mint(tokenHolder3, 2);
    vm.prank(tokenHolder1);
    mockErc721Votes.delegate(tokenHolder1);
    vm.prank(tokenHolder2);
    mockErc721Votes.delegate(tokenHolder2);
    vm.prank(tokenHolder3);
    mockErc721Votes.delegate(tokenHolder3);

    vm.warp(block.timestamp + 1);
    vm.roll(block.number + 1);

    caster = new ERC721TokenholderCaster(
      token, ILlamaCore(address(CORE)), CASTER_ROLE, DEFAULT_APPROVAL_THRESHOLD, DEFAULT_APPROVAL_THRESHOLD
    );

    tokenVotingStrategy = deployRelativeQuantityQuorumAndSetRole(address(caster), CASTER_ROLE);
    vm.warp(block.timestamp + 1);
    vm.roll(block.number + 1);

    actionInfo = createAction(tokenVotingStrategy);

    vm.warp(block.timestamp + 1);
    vm.roll(block.number + 1);
  }

  function castApprovalsFor() public {
    vm.prank(tokenHolder1);
    caster.castApproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    caster.castApproval(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    caster.castApproval(actionInfo, 1, "");
  }

  function castDisapprovalsFor() public {
    vm.prank(tokenHolder1);
    caster.castDisapproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    caster.castDisapproval(actionInfo, 1, "");
    vm.prank(tokenHolder3);
    caster.castDisapproval(actionInfo, 1, "");
  }

  function encodeStrategyConfigs(ILlamaRelativeStrategyBase.Config[] memory strategies)
    internal
    pure
    returns (bytes[] memory encoded)
  {
    encoded = new bytes[](strategies.length);
    for (uint256 i = 0; i < strategies.length; i++) {
      encoded[i] = encodeStrategy(strategies[i]);
    }
  }

  function encodeStrategy(ILlamaRelativeStrategyBase.Config memory strategy)
    internal
    pure
    returns (bytes memory encoded)
  {
    encoded = abi.encode(strategy);
  }
}

contract Constructor is ERC721TokenholderCasterTest {
  function test_RevertsIf_InvalidLlamaCoreAddress() public {
    // With invalid LlamaCore instance, TokenholderActionCreator.InvalidLlamaCoreAddress is unreachable
    vm.expectRevert();
    new ERC721TokenholderCaster(token, ILlamaCore(makeAddr("invalid-llama-core")), CASTER_ROLE, uint256(1), uint256(1));
  }

  function test_RevertsIf_InvalidTokenAddress(address notAToken) public {
    vm.assume(notAToken != address(0));
    vm.assume(notAToken != address(token));
    vm.expectRevert(); // will revert with EvmError: Revert because `totalSupply` is not a function
    new ERC721TokenholderCaster(ERC721Votes(notAToken), ILlamaCore(address(CORE)), CASTER_ROLE, uint256(1), uint256(1));
  }

  function test_RevertsIf_InvalidRole(uint8 role) public {
    role = uint8(bound(role, POLICY.numRoles(), 255));
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.RoleNotInitialized.selector, uint8(255)));
    new ERC721TokenholderCaster(token, ILlamaCore(address(CORE)), uint8(255), uint256(1), uint256(1));
  }

  function test_RevertsIf_InvalidMinApprovalPct() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinApprovalPct.selector, uint256(0)));
    new ERC721TokenholderCaster(token, ILlamaCore(address(CORE)), CASTER_ROLE, uint256(0), uint256(1));
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinApprovalPct.selector, uint256(10_001)));
    new ERC721TokenholderCaster(token, ILlamaCore(address(CORE)), CASTER_ROLE, uint256(10_001), uint256(1));
  }

  function test_RevertsIf_InvalidMinDisapprovalPct() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinDisapprovalPct.selector, uint256(0)));
    new ERC721TokenholderCaster(token, ILlamaCore(address(CORE)), CASTER_ROLE, uint256(1), uint256(0));
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidMinDisapprovalPct.selector, uint256(10_001)));
    new ERC721TokenholderCaster(token, ILlamaCore(address(CORE)), CASTER_ROLE, uint256(1), uint256(10_001));
  }

  function test_ProperlySetsConstructorArguments() public {
    mockErc721Votes.mint(address(this), 1_000_000e18); // we use mockErc721Votes because IVotesToken is an interface
    // without the `mint` function

    caster = new ERC721TokenholderCaster(
      token, ILlamaCore(address(CORE)), CASTER_ROLE, DEFAULT_APPROVAL_THRESHOLD, DEFAULT_APPROVAL_THRESHOLD
    );

    assertEq(address(caster.LLAMA_CORE()), address(CORE));
    assertEq(address(caster.TOKEN()), address(token));
    assertEq(caster.ROLE(), CASTER_ROLE);
    assertEq(caster.MIN_APPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
    assertEq(caster.MIN_DISAPPROVAL_PCT(), DEFAULT_APPROVAL_THRESHOLD);
  }
}

contract CastApproval is ERC721TokenholderCasterTest {
  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    caster.castApproval(notActionInfo, CASTER_ROLE, "");
  }

  function test_RevertsIf_ApprovalNotEnabled() public {
    TokenholderCaster casterWithWrongRole = new ERC721TokenholderCaster(
      token, ILlamaCore(address(CORE)), MADE_UP_ROLE, DEFAULT_APPROVAL_THRESHOLD, DEFAULT_APPROVAL_THRESHOLD
    );
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, CASTER_ROLE));
    casterWithWrongRole.castApproval(actionInfo, MADE_UP_ROLE, "");
  }

  function test_RevertsIf_ActionNotActive() public {
    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(TokenholderCaster.ActionNotActive.selector);
    caster.castApproval(actionInfo, 1, "");
  }

  function test_RevertsIf_AlreadyCastApproval() public {
    vm.startPrank(tokenHolder1);
    caster.castApproval(actionInfo, 1, "");

    vm.expectRevert(TokenholderCaster.AlreadyCastApproval.selector);
    caster.castApproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidSupport.selector, uint8(3)));
    caster.castApproval(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS); // 2/3 of the approval period
    vm.expectRevert(TokenholderCaster.CastingPeriodOver.selector);
    vm.prank(tokenHolder1);
    caster.castApproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientBalance.selector, 0));
    caster.castApproval(actionInfo, 1, "");
  }

  function test_CastsApprovalCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit ApprovalCast(
      actionInfo.id, tokenHolder1, CASTER_ROLE, support, token.getPastVotes(tokenHolder1, block.timestamp - 1), ""
    );
    vm.prank(tokenHolder1);
    caster.castApproval(actionInfo, support, "");
  }

  function test_CastsApprovalCorrectly_WithReason() public {
    vm.expectEmit();
    emit ApprovalCast(
      actionInfo.id, tokenHolder1, CASTER_ROLE, 1, token.getPastVotes(tokenHolder1, token.clock() - 1), "reason"
    );
    vm.prank(tokenHolder1);
    caster.castApproval(actionInfo, 1, "reason");
  }
}

contract CastDisapproval is ERC721TokenholderCasterTest {
  function setUp() public virtual override {
    ERC721TokenholderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    vm.prank(tokenHolder1);
    caster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    caster.castDisapproval(notActionInfo, CASTER_ROLE, "");
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    TokenholderCaster casterWithWrongRole = new ERC721TokenholderCaster(
      token, ILlamaCore(address(CORE)), MADE_UP_ROLE, DEFAULT_APPROVAL_THRESHOLD, DEFAULT_APPROVAL_THRESHOLD
    );
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, CASTER_ROLE));
    casterWithWrongRole.castDisapproval(actionInfo, MADE_UP_ROLE, "");
  }

  function test_RevertsIf_AlreadyCastApproval() public {
    vm.startPrank(tokenHolder1);
    caster.castDisapproval(actionInfo, 1, "");

    vm.expectRevert(TokenholderCaster.AlreadyCastDisapproval.selector);
    caster.castDisapproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InvalidSupport() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InvalidSupport.selector, uint8(3)));
    caster.castDisapproval(actionInfo, 3, "");
  }

  function test_RevertsIf_CastingPeriodOver() public {
    // TODO why do we need to add 2 here
    vm.warp(block.timestamp + 2 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS); // 2/3 of the approval period
    vm.expectRevert(TokenholderCaster.CastingPeriodOver.selector);
    caster.castDisapproval(actionInfo, 1, "");
  }

  function test_RevertsIf_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientBalance.selector, 0));
    caster.castDisapproval(actionInfo, 1, "");
  }

  function test_CastsDisapprovalCorrectly(uint8 support) public {
    support = uint8(bound(support, 0, 2));
    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id, tokenHolder1, CASTER_ROLE, support, token.getPastVotes(tokenHolder1, block.timestamp - 1), ""
    );
    vm.prank(tokenHolder1);
    caster.castDisapproval(actionInfo, support, "");
  }

  function test_CastsDisapprovalCorrectly_WithReason() public {
    vm.expectEmit();
    emit DisapprovalCast(
      actionInfo.id, tokenHolder1, CASTER_ROLE, 1, token.getPastVotes(tokenHolder1, token.clock() - 1), "reason"
    );
    vm.prank(tokenHolder1);
    caster.castDisapproval(actionInfo, 1, "reason");
  }
}

contract SubmitApprovals is ERC721TokenholderCasterTest {
  function setUp() public virtual override {
    ERC721TokenholderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    caster.submitApprovals(notActionInfo);
  }

  function test_RevertsIf_AlreadySubmittedApproval() public {
    vm.startPrank(tokenHolder1);
    caster.submitApprovals(actionInfo);

    vm.expectRevert(TokenholderCaster.AlreadySubmittedApproval.selector);
    caster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(TokenholderCaster.SubmissionPeriodOver.selector);
    caster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_InsufficientApprovals() public {
    actionInfo = createAction(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientApprovals.selector, 0, 1));
    caster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    actionInfo = createAction(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(TokenholderCaster.CantSubmitYet.selector);
    caster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_InsufficientApprovalsFor() public {
    actionInfo = createAction(tokenVotingStrategy);
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientApprovals.selector, 0, 1));
    caster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    actionInfo = createAction(tokenVotingStrategy);

    vm.prank(tokenHolder1);
    caster.castApproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    caster.castApproval(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    caster.castApproval(actionInfo, 0, "");

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    caster.submitApprovals(actionInfo);
  }

  function test_SubmitsApprovalsCorrectly() public {
    vm.expectEmit();
    emit ApprovalsSubmitted(actionInfo.id, 3, 0, 0);
    caster.submitApprovals(actionInfo);
  }
}

contract SubmitDisapprovals is ERC721TokenholderCasterTest {
  function setUp() public virtual override {
    ERC721TokenholderCasterTest.setUp();

    castApprovalsFor();

    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);

    caster.submitApprovals(actionInfo);
  }

  function test_RevertsIf_ActionInfoMismatch(ActionInfo memory notActionInfo) public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.assume(notActionInfo.id != actionInfo.id);
    vm.expectRevert();
    caster.submitDisapprovals(notActionInfo);
  }

  function test_RevertsIf_DisapprovalNotEnabled() public {
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    TokenholderCaster casterWithWrongRole = new ERC721TokenholderCaster(
      token, ILlamaCore(address(CORE)), MADE_UP_ROLE, DEFAULT_APPROVAL_THRESHOLD, DEFAULT_APPROVAL_THRESHOLD
    );
    vm.expectRevert(abi.encodeWithSelector(ILlamaRelativeStrategyBase.InvalidRole.selector, CASTER_ROLE));
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
    caster.submitDisapprovals(actionInfo);

    vm.expectRevert(TokenholderCaster.AlreadySubmittedDisapproval.selector);
    caster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_SubmissionPeriodOver() public {
    castDisapprovalsFor();

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(TokenholderCaster.SubmissionPeriodOver.selector);
    caster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_InsufficientDisapprovals() public {
    actionInfo = createAction(tokenVotingStrategy);
    castApprovalsFor();
    vm.warp(block.timestamp + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    caster.submitApprovals(actionInfo);

    //TODO why add 1 here
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.InsufficientApprovals.selector, 0, 1));
    caster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_CastingPeriodNotOver() public {
    vm.warp(block.timestamp + (1 days * 3333) / ONE_HUNDRED_IN_BPS); // 1/3 of the approval period
    vm.expectRevert(TokenholderCaster.CantSubmitYet.selector);
    caster.submitDisapprovals(actionInfo);
  }

  function test_RevertsIf_ForDoesNotSurpassAgainst() public {
    vm.prank(tokenHolder1);
    caster.castDisapproval(actionInfo, 1, "");
    vm.prank(tokenHolder2);
    caster.castDisapproval(actionInfo, 0, "");
    vm.prank(tokenHolder3);
    caster.castDisapproval(actionInfo, 0, "");
    // TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectRevert(abi.encodeWithSelector(TokenholderCaster.ForDoesNotSurpassAgainst.selector, 1, 2));
    caster.submitDisapprovals(actionInfo);
  }

  function test_SubmitsDisapprovalsCorrectly() public {
    castDisapprovalsFor();

    //TODO why add 1 here?
    vm.warp(block.timestamp + 1 + (1 days * TWO_THIRDS_IN_BPS) / ONE_HUNDRED_IN_BPS);
    vm.expectEmit();
    emit DisapprovalsSubmitted(actionInfo.id, 3, 0, 0);
    caster.submitDisapprovals(actionInfo);
  }
}

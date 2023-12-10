// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {ActionInfo} from "src/lib/Structs.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {ERC20TokenholderCaster} from "src/token-voting/ERC20TokenholderCaster.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {ERC721TokenholderCaster} from "src/token-voting/ERC721TokenholderCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract LlamaTokenVotingFactoryTest is LlamaTokenVotingTestSetup {
  event ERC20TokenholderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC721TokenholderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC20TokenholderCasterCreated(
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
  );
  event ERC721TokenholderCasterCreated(
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
  );
  event ActionThresholdSet(uint256 newThreshold);

  function setUp() public override {
    LlamaTokenVotingTestSetup.setUp();

    // Mint tokens to tokenholders so that there is an existing supply.
    erc20VotesToken.mint(tokenHolder0, ERC20_CREATION_THRESHOLD);
    erc721VotesToken.mint(tokenHolder0, 0);

    // Mine block so that the ERC20 and ERC721 supply will be available when doing a past timestamp check at initialize
    // during deployment.
    mineBlock();
  }
}

contract Constructor is LlamaTokenVotingFactoryTest {
  function test_SetsERC20TokenholderActionCreatorLogicAddress() public {
    assertEq(
      address(tokenVotingFactory.ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC()), address(erc20TokenholderActionCreatorLogic)
    );
  }

  function test_SetsERC20TokenholderCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC20_TOKENHOLDER_CASTER_LOGIC()), address(erc20TokenholderCasterLogic));
  }

  function test_SetsERC721TokenholderActionCreatorLogicAddress() public {
    assertEq(
      address(tokenVotingFactory.ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC()),
      address(erc721TokenholderActionCreatorLogic)
    );
  }

  function test_SetsERC721TokenholderCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC721_TOKENHOLDER_CASTER_LOGIC()), address(erc721TokenholderCasterLogic));
  }
}

contract DeployTokenVotingModule is LlamaTokenVotingFactoryTest {
  function _setPermissionCreateApproveAndQueueAction(bytes memory data) internal returns (ActionInfo memory actionInfo) {
    // Assign `deployTokenVotingModule` permission to the `CORE_TEAM_ROLE` role.
    ILlamaPolicy.PermissionData memory deployTokenVotingPermission = ILlamaPolicy.PermissionData(
      address(tokenVotingFactory), LlamaTokenVotingFactory.deployTokenVotingModule.selector, address(STRATEGY)
    );

    vm.prank(address(EXECUTOR));
    POLICY.setRolePermission(CORE_TEAM_ROLE, deployTokenVotingPermission, true);

    // Create an action and queue it to deploy the token voting module.
    vm.prank(coreTeam4);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(tokenVotingFactory), 0, data, "");
    actionInfo = ActionInfo(actionId, coreTeam4, CORE_TEAM_ROLE, STRATEGY, address(tokenVotingFactory), 0, data);

    vm.prank(coreTeam1);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam2);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam3);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
  }

  function test_CanDeployERC20TokenVotingModule() public {
    // Set up action to call `deployTokenVotingModule` with the ERC20 token.
    bytes memory data = abi.encodeWithSelector(
      LlamaTokenVotingFactory.deployTokenVotingModule.selector,
      CORE,
      address(erc20VotesToken),
      true,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      ERC20_MIN_APPROVAL_PCT,
      ERC20_MIN_DISAPPROVAL_PCT
    );
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    // Compute addresses of ERC20 Token Voting Module
    ERC20TokenholderActionCreator erc20TokenholderActionCreator = ERC20TokenholderActionCreator(
      Clones.predictDeterministicAddress(
        address(erc20TokenholderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    ERC20TokenholderCaster erc20TokenholderCaster = ERC20TokenholderCaster(
      Clones.predictDeterministicAddress(
        address(erc20TokenholderCasterLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit ERC20TokenholderActionCreatorCreated(address(erc20TokenholderActionCreator), address(erc20VotesToken));
    vm.expectEmit();
    emit ERC20TokenholderCasterCreated(
      address(erc20TokenholderCaster), address(erc20VotesToken), ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);

    assertEq(address(erc20TokenholderActionCreator.token()), address(erc20VotesToken));
    assertEq(address(erc20TokenholderActionCreator.llamaCore()), address(CORE));
    assertEq(erc20TokenholderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(erc20TokenholderActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(erc20TokenholderCaster.token()), address(erc20VotesToken));
    assertEq(address(erc20TokenholderCaster.llamaCore()), address(CORE));
    assertEq(erc20TokenholderCaster.role(), tokenVotingCasterRole);
    assertEq(erc20TokenholderCaster.minApprovalPct(), ERC20_MIN_APPROVAL_PCT);
    assertEq(erc20TokenholderCaster.minDisapprovalPct(), ERC20_MIN_DISAPPROVAL_PCT);
  }

  function test_CanDeployERC721TokenVotingModule() public {
    // Set up action to call `deployTokenVotingModule` with the ERC721 token.
    bytes memory data = abi.encodeWithSelector(
      LlamaTokenVotingFactory.deployTokenVotingModule.selector,
      CORE,
      address(erc721VotesToken),
      false,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC721_CREATION_THRESHOLD,
      ERC721_MIN_APPROVAL_PCT,
      ERC721_MIN_DISAPPROVAL_PCT
    );
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    // Compute addresses of ERC721 Token Voting Module
    ERC721TokenholderActionCreator erc721TokenholderActionCreator = ERC721TokenholderActionCreator(
      Clones.predictDeterministicAddress(
        address(erc721TokenholderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    ERC721TokenholderCaster erc721TokenholderCaster = ERC721TokenholderCaster(
      Clones.predictDeterministicAddress(
        address(erc721TokenholderCasterLogic),
        keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC721_CREATION_THRESHOLD);
    vm.expectEmit();
    emit ERC721TokenholderActionCreatorCreated(address(erc721TokenholderActionCreator), address(erc721VotesToken));
    vm.expectEmit();
    emit ERC721TokenholderCasterCreated(
      address(erc721TokenholderCaster), address(erc721VotesToken), ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);

    assertEq(address(erc721TokenholderActionCreator.token()), address(erc721VotesToken));
    assertEq(address(erc721TokenholderActionCreator.llamaCore()), address(CORE));
    assertEq(erc721TokenholderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(erc721TokenholderActionCreator.creationThreshold(), ERC721_CREATION_THRESHOLD);
    assertEq(address(erc721TokenholderCaster.token()), address(erc721VotesToken));
    assertEq(address(erc721TokenholderCaster.llamaCore()), address(CORE));
    assertEq(erc721TokenholderCaster.role(), tokenVotingCasterRole);
    assertEq(erc721TokenholderCaster.minApprovalPct(), ERC721_MIN_APPROVAL_PCT);
    assertEq(erc721TokenholderCaster.minDisapprovalPct(), ERC721_MIN_DISAPPROVAL_PCT);
  }

  function test_CanBeDeployedByAnyone(address randomCaller) public {
    vm.assume(randomCaller != address(0));
    vm.deal(randomCaller, 1 ether);

    ERC20TokenholderActionCreator erc20TokenholderActionCreator = ERC20TokenholderActionCreator(
      Clones.predictDeterministicAddress(
        address(erc20TokenholderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), randomCaller)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    ERC20TokenholderCaster erc20TokenholderCaster = ERC20TokenholderCaster(
      Clones.predictDeterministicAddress(
        address(erc20TokenholderCasterLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), randomCaller)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit ERC20TokenholderActionCreatorCreated(address(erc20TokenholderActionCreator), address(erc20VotesToken));
    vm.expectEmit();
    emit ERC20TokenholderCasterCreated(
      address(erc20TokenholderCaster), address(erc20VotesToken), ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT
    );

    vm.prank(randomCaller);
    tokenVotingFactory.deployTokenVotingModule(
      CORE,
      address(erc20VotesToken),
      true,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      ERC20_MIN_APPROVAL_PCT,
      ERC20_MIN_DISAPPROVAL_PCT
    );

    assertEq(address(erc20TokenholderActionCreator.token()), address(erc20VotesToken));
    assertEq(address(erc20TokenholderActionCreator.llamaCore()), address(CORE));
    assertEq(erc20TokenholderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(erc20TokenholderActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(erc20TokenholderCaster.token()), address(erc20VotesToken));
    assertEq(address(erc20TokenholderCaster.llamaCore()), address(CORE));
    assertEq(erc20TokenholderCaster.role(), tokenVotingCasterRole);
    assertEq(erc20TokenholderCaster.minApprovalPct(), ERC20_MIN_APPROVAL_PCT);
    assertEq(erc20TokenholderCaster.minDisapprovalPct(), ERC20_MIN_DISAPPROVAL_PCT);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {ActionInfo} from "src/lib/Structs.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ERC20TokenHolderActionCreator} from "src/token-voting/ERC20TokenHolderActionCreator.sol";
import {ERC20TokenHolderCaster} from "src/token-voting/ERC20TokenHolderCaster.sol";
import {ERC721TokenHolderActionCreator} from "src/token-voting/ERC721TokenHolderActionCreator.sol";
import {ERC721TokenHolderCaster} from "src/token-voting/ERC721TokenHolderCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract LlamaTokenVotingFactoryTest is LlamaTokenVotingTestSetup {
  event ERC20TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC721TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC20TokenHolderCasterCreated(address caster, address indexed token, uint256 voteQuorum, uint256 vetoQuorum);
  event ERC721TokenHolderCasterCreated(address caster, address indexed token, uint256 voteQuorum, uint256 vetoQuorum);
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
  function test_SetsERC20TokenHolderActionCreatorLogicAddress() public {
    assertEq(
      address(tokenVotingFactory.ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC()), address(erc20TokenHolderActionCreatorLogic)
    );
  }

  function test_SetsERC20TokenHolderCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC20_TOKENHOLDER_CASTER_LOGIC()), address(erc20TokenHolderCasterLogic));
  }

  function test_SetsERC721TokenHolderActionCreatorLogicAddress() public {
    assertEq(
      address(tokenVotingFactory.ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC()),
      address(erc721TokenHolderActionCreatorLogic)
    );
  }

  function test_SetsERC721TokenHolderCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC721_TOKENHOLDER_CASTER_LOGIC()), address(erc721TokenHolderCasterLogic));
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
    ERC20TokenHolderActionCreator erc20TokenHolderActionCreator = ERC20TokenHolderActionCreator(
      Clones.predictDeterministicAddress(
        address(erc20TokenHolderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    ERC20TokenHolderCaster erc20TokenHolderCaster = ERC20TokenHolderCaster(
      Clones.predictDeterministicAddress(
        address(erc20TokenHolderCasterLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit ERC20TokenHolderActionCreatorCreated(address(erc20TokenHolderActionCreator), address(erc20VotesToken));
    vm.expectEmit();
    emit ERC20TokenHolderCasterCreated(
      address(erc20TokenHolderCaster), address(erc20VotesToken), ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);

    assertEq(address(erc20TokenHolderActionCreator.token()), address(erc20VotesToken));
    assertEq(address(erc20TokenHolderActionCreator.llamaCore()), address(CORE));
    assertEq(erc20TokenHolderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(erc20TokenHolderActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(erc20TokenHolderCaster.token()), address(erc20VotesToken));
    assertEq(address(erc20TokenHolderCaster.llamaCore()), address(CORE));
    assertEq(erc20TokenHolderCaster.role(), tokenVotingCasterRole);
    assertEq(erc20TokenHolderCaster.voteQuorum(), ERC20_MIN_APPROVAL_PCT);
    assertEq(erc20TokenHolderCaster.vetoQuorum(), ERC20_MIN_DISAPPROVAL_PCT);
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
    ERC721TokenHolderActionCreator erc721TokenHolderActionCreator = ERC721TokenHolderActionCreator(
      Clones.predictDeterministicAddress(
        address(erc721TokenHolderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    ERC721TokenHolderCaster erc721TokenHolderCaster = ERC721TokenHolderCaster(
      Clones.predictDeterministicAddress(
        address(erc721TokenHolderCasterLogic),
        keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC721_CREATION_THRESHOLD);
    vm.expectEmit();
    emit ERC721TokenHolderActionCreatorCreated(address(erc721TokenHolderActionCreator), address(erc721VotesToken));
    vm.expectEmit();
    emit ERC721TokenHolderCasterCreated(
      address(erc721TokenHolderCaster), address(erc721VotesToken), ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);

    assertEq(address(erc721TokenHolderActionCreator.token()), address(erc721VotesToken));
    assertEq(address(erc721TokenHolderActionCreator.llamaCore()), address(CORE));
    assertEq(erc721TokenHolderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(erc721TokenHolderActionCreator.creationThreshold(), ERC721_CREATION_THRESHOLD);
    assertEq(address(erc721TokenHolderCaster.token()), address(erc721VotesToken));
    assertEq(address(erc721TokenHolderCaster.llamaCore()), address(CORE));
    assertEq(erc721TokenHolderCaster.role(), tokenVotingCasterRole);
    assertEq(erc721TokenHolderCaster.voteQuorum(), ERC721_MIN_APPROVAL_PCT);
    assertEq(erc721TokenHolderCaster.vetoQuorum(), ERC721_MIN_DISAPPROVAL_PCT);
  }
}

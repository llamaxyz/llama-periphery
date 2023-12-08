// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {ActionInfo} from "src/lib/Structs.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
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

  function setUp() public override {
    LlamaTokenVotingTestSetup.setUp();
  }

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
}

contract DeployTokenVotingModule is LlamaTokenVotingFactoryTest {
  function test_CanDeployERC20TokenVotingModule() public {
    // Set up action to call `deployTokenVotingModule` with the ERC20 token.
    bytes memory data = abi.encodeWithSelector(
      LlamaTokenVotingFactory.deployTokenVotingModule.selector,
      address(erc20VotesToken),
      true,
      ERC20_CREATION_THRESHOLD,
      ERC20_MIN_APPROVAL_PCT,
      ERC20_MIN_DISAPPROVAL_PCT
    );
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    // Compute addresses of ERC20 Token Voting Module
    address erc20TokenholderActionCreator = Clones.predictDeterministicAddress(
      address(erc20TokenholderActionCreatorLogic),
      keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
      address(tokenVotingFactory) // deployer
    );
    address erc20TokenholderCaster = Clones.predictDeterministicAddress(
      address(erc20TokenholderCasterLogic),
      keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
      address(tokenVotingFactory) // deployer
    );

    // Expect events to be emitted on call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ERC20TokenholderActionCreatorCreated(erc20TokenholderActionCreator, address(erc20VotesToken));
    vm.expectEmit();
    emit ERC20TokenholderCasterCreated(
      erc20TokenholderCaster, address(erc20VotesToken), ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);
  }

  function test_CanDeployERC721TokenVotingModule() public {
    // Set up action to call `deployTokenVotingModule` with the ERC721 token.
    bytes memory data = abi.encodeWithSelector(
      LlamaTokenVotingFactory.deployTokenVotingModule.selector,
      address(erc721VotesToken),
      false,
      ERC721_CREATION_THRESHOLD,
      ERC721_MIN_APPROVAL_PCT,
      ERC721_MIN_DISAPPROVAL_PCT
    );
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    // Compute addresses of ERC721 Token Voting Module
    address erc721TokenholderActionCreator = Clones.predictDeterministicAddress(
      address(erc721TokenholderActionCreatorLogic),
      keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
      address(tokenVotingFactory) // deployer
    );
    address erc721TokenholderCaster = Clones.predictDeterministicAddress(
      address(erc721TokenholderCasterLogic),
      keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
      address(tokenVotingFactory) // deployer
    );

    // Expect events to be emitted on call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ERC721TokenholderActionCreatorCreated(erc721TokenholderActionCreator, address(erc721VotesToken));
    vm.expectEmit();
    emit ERC721TokenholderCasterCreated(
      erc721TokenholderCaster, address(erc721VotesToken), ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);
  }
}

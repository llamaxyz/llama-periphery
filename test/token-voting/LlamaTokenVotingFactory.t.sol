// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {MockERC20Votes} from "test/mock/MockERC20Votes.sol";
import {MockERC721Votes} from "test/mock/MockERC721Votes.sol";
import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {Action, ActionInfo} from "src/lib/Structs.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ERC20Votes} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC721Votes} from "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Votes.sol";
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
  event RoleAssigned(address indexed policyholder, uint8 indexed role, uint64 expiration, uint96 quantity);
  event RoleInitialized(uint8 indexed role, RoleDescription description);

  uint256 public constant CREATION_THRESHOLD = 100;
  uint256 public constant MIN_APPROVAL_PCT = 1000;
  uint256 public constant MIN_DISAPPROVAL_PCT = 1000;

  LlamaTokenVotingFactory public FACTORY;
  ERC20Votes public ERC20TOKEN;
  ERC721Votes public ERC721TOKEN;

  function setUp() public override {
    PeripheryTestSetup.setUp();

    FACTORY = new LlamaTokenVotingFactory();
    MockERC20Votes mockERC20Votes = new MockERC20Votes();
    ERC20TOKEN = ERC20Votes(address(mockERC20Votes));
    MockERC721Votes mockERC721Votes = new MockERC721Votes();
    ERC721TOKEN = ERC721Votes(address(mockERC721Votes));

    mockERC20Votes.mint(coreTeam1, 100);
    mockERC20Votes.mint(coreTeam2, 100);
    mockERC20Votes.mint(coreTeam3, 100);
    mockERC20Votes.mint(coreTeam4, 100);

    mockERC721Votes.mint(coreTeam1, 0);
    mockERC721Votes.mint(coreTeam2, 1);
    mockERC721Votes.mint(coreTeam3, 2);
    mockERC721Votes.mint(coreTeam4, 3);

    ILlamaPolicy.PermissionData memory newPermission1 = ILlamaPolicy.PermissionData(
      address(FACTORY), LlamaTokenVotingFactory.deployTokenVotingModule.selector, address(STRATEGY)
    );

    vm.startPrank(address(EXECUTOR));
    POLICY.setRolePermission(CORE_TEAM_ROLE, newPermission1, true);
    vm.stopPrank();

    vm.warp(block.timestamp + 1);
  }

  function _createApproveAndQueueAction(bytes memory data) internal returns (ActionInfo memory actionInfo) {
    vm.prank(coreTeam4);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(FACTORY), 0, data, "");
    actionInfo = ActionInfo(actionId, coreTeam4, CORE_TEAM_ROLE, STRATEGY, address(FACTORY), 0, data);

    vm.prank(coreTeam1);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam2);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam3);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");

    // vm.warp(block.timestamp + 1 days);
    // CORE.queueAction(actionInfo);
    // vm.warp(block.timestamp + 5 days);
  }
}

contract DeployTokenVotingModule is LlamaTokenVotingFactoryTest {
  function test_CanDeployERC20TokenVotingModule() public {
    bytes memory data = abi.encodeWithSelector(
      LlamaTokenVotingFactory.deployTokenVotingModule.selector,
      address(ERC20TOKEN),
      true,
      CREATION_THRESHOLD,
      MIN_APPROVAL_PCT,
      MIN_DISAPPROVAL_PCT
    );

    ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

    vm.expectEmit();
    emit ERC20TokenholderActionCreatorCreated(0x104fBc016F4bb334D775a19E8A6510109AC63E00, address(ERC20TOKEN));
    vm.expectEmit();
    emit ERC20TokenholderCasterCreated(
      0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3, address(ERC20TOKEN), MIN_APPROVAL_PCT, MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);
  }

  function test_CanDeployERC721TokenVotingModule() public {
    bytes memory data = abi.encodeWithSelector(
      LlamaTokenVotingFactory.deployTokenVotingModule.selector, address(ERC721TOKEN), false, 1, 1, 1
    );

    ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

    vm.expectEmit();
    emit ERC721TokenholderActionCreatorCreated(0x104fBc016F4bb334D775a19E8A6510109AC63E00, address(ERC721TOKEN));
    vm.expectEmit();
    emit ERC721TokenholderCasterCreated(0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3, address(ERC721TOKEN), 1, 1);
    CORE.executeAction(actionInfo);
  }
}

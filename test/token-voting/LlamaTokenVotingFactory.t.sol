// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

// import {Test, console2} from "forge-std/Test.sol";

// import {MockERC20Votes} from "test/mock/MockERC20Votes.sol";
// import {LlamaTestSetup} from "test/utils/LlamaTestSetup.sol";
// import {Roles} from "test/utils/LlamaTestSetup.sol";

// import {Action, ActionInfo, PermissionData} from "src/lib/Structs.sol";
// import {RoleDescription} from "src/lib/UDVTs.sol";
// import {ERC20Votes} from "src/modules/token-voting/OZ-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
// import {ERC721Votes} from "src/modules/token-voting/OZ-contracts/contracts/token/ERC721/extensions/ERC721Votes.sol";
// import {LlamaCore} from "src/LlamaCore.sol";
// import {LlamaTokenVotingFactory} from "src/modules/token-voting/LlamaTokenVotingFactory.sol";
// import {MockERC20Votes} from "test/mock/MockERC20Votes.sol";
// import {MockERC721Votes} from "test/mock/MockERC721Votes.sol";

// contract LlamaTokenVotingFactoryTest is LlamaTestSetup {
//   event ERC20TokenholderActionCreatorCreated(address actionCreator, address indexed token);
//   event ERC721TokenholderActionCreatorCreated(address actionCreator, address indexed token);
//   event ERC20TokenholderCasterCreated(
//     address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
//   );
//   event ERC721TokenholderCasterCreated(
//     address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
//   );
//   event RoleAssigned(address indexed policyholder, uint8 indexed role, uint64 expiration, uint96 quantity);
//   event RoleInitialized(uint8 indexed role, RoleDescription description);

//   uint256 public constant CREATION_THRESHOLD = 100;
//   uint256 public constant MIN_APPROVAL_PCT = 1000;
//   uint256 public constant MIN_DISAPPROVAL_PCT = 1000;

//   LlamaTokenVotingFactory public FACTORY;
//   ERC20Votes public ERC20TOKEN;
//   ERC721Votes public ERC721TOKEN;

//   function setUp() public override {
//     super.setUp();

//     FACTORY = new LlamaTokenVotingFactory();
//     MockERC20Votes mockERC20Votes = new MockERC20Votes();
//     ERC20TOKEN = ERC20Votes(address(mockERC20Votes));
//     MockERC721Votes mockERC721Votes = new MockERC721Votes();
//     ERC721TOKEN = ERC721Votes(address(mockERC721Votes));

//     mockERC20Votes.mint(approverAdam, 100);
//     mockERC20Votes.mint(approverAlicia, 100);
//     mockERC20Votes.mint(approverAndy, 100);
//     mockERC20Votes.mint(actionCreatorAaron, 100);

//     mockERC721Votes.mint(approverAdam, 0);
//     mockERC721Votes.mint(approverAlicia, 1);
//     mockERC721Votes.mint(approverAndy, 2);
//     mockERC721Votes.mint(actionCreatorAaron, 3);

//     PermissionData memory newPermission1 =
//       PermissionData(address(FACTORY), LlamaTokenVotingFactory.deployTokenVotingModule.selector, mpStrategy1);
//     PermissionData memory newPermission2 = PermissionData(
//       address(FACTORY), LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector, mpStrategy1
//     );

//     vm.startPrank(address(mpExecutor));
//     mpPolicy.setRolePermission(uint8(Roles.ActionCreator), newPermission1, true);
//     mpPolicy.setRolePermission(uint8(Roles.ActionCreator), newPermission2, true);
//     vm.stopPrank();

//     vm.warp(block.timestamp + 1);
//   }

//   function _createApproveAndQueueAction(bytes memory data) internal returns (ActionInfo memory actionInfo) {
//     vm.prank(actionCreatorAaron);
//     uint256 actionId = mpCore.createAction(uint8(Roles.ActionCreator), mpStrategy1, address(FACTORY), 0, data, "");
//     actionInfo =
//       ActionInfo(actionId, actionCreatorAaron, uint8(Roles.ActionCreator), mpStrategy1, address(FACTORY), 0, data);

//     vm.prank(approverAdam);
//     mpCore.castApproval(uint8(Roles.Approver), actionInfo, "");
//     vm.prank(approverAlicia);
//     mpCore.castApproval(uint8(Roles.Approver), actionInfo, "");
//     vm.prank(approverAndy);
//     mpCore.castApproval(uint8(Roles.Approver), actionInfo, "");

//     vm.warp(block.timestamp + 6 days);
//     mpCore.queueAction(actionInfo);
//     vm.warp(block.timestamp + 5 days);
//   }
// }

// contract DeployTokenVotingModule is LlamaTokenVotingFactoryTest {
//   function test_CanDeployERC20TokenVotingModule() public {
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.deployTokenVotingModule.selector,
//       address(ERC20TOKEN),
//       true,
//       true,
//       true,
//       CREATION_THRESHOLD,
//       MIN_APPROVAL_PCT,
//       MIN_DISAPPROVAL_PCT
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC20TokenholderActionCreatorCreated(0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2, address(ERC20TOKEN));
//     vm.expectEmit();
//     emit ERC20TokenholderCasterCreated(
//       0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9, address(ERC20TOKEN), MIN_APPROVAL_PCT, MIN_DISAPPROVAL_PCT
//     );
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployERC721TokenVotingModule() public {
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.deployTokenVotingModule.selector, address(ERC721TOKEN), false, true, true, 1, 1, 1
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC721TokenholderActionCreatorCreated(0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2, address(ERC721TOKEN));
//     vm.expectEmit();
//     emit ERC721TokenholderCasterCreated(0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9, address(ERC721TOKEN), 1, 1);
//     mpCore.executeAction(actionInfo);
//   }

//   function test_RevertsIfNoModulesDeployed() public {
//     vm.expectRevert(LlamaTokenVotingFactory.NoModulesDeployed.selector);
//     vm.prank(address(mpExecutor));
//     FACTORY.deployTokenVotingModule(address(ERC20TOKEN), true, false, false, 1, 1, 1);
//   }

//   function test_CanDeployCreatorOnly_ERC20() public {
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.deployTokenVotingModule.selector,
//       address(ERC20TOKEN),
//       true,
//       true,
//       false,
//       CREATION_THRESHOLD,
//       MIN_APPROVAL_PCT,
//       MIN_DISAPPROVAL_PCT
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC20TokenholderActionCreatorCreated(0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2, address(ERC20TOKEN));
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployCasterOnly_ERC20() public {
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.deployTokenVotingModule.selector,
//       address(ERC20TOKEN),
//       true,
//       false,
//       true,
//       CREATION_THRESHOLD,
//       MIN_APPROVAL_PCT,
//       MIN_DISAPPROVAL_PCT
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     emit ERC20TokenholderCasterCreated(
//       0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9, address(ERC20TOKEN), MIN_APPROVAL_PCT, MIN_DISAPPROVAL_PCT
//     );
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployCreatorOnly_ERC721() public {
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.deployTokenVotingModule.selector, address(ERC721TOKEN), false, true, false, 1, 1, 1
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC721TokenholderActionCreatorCreated(0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2, address(ERC721TOKEN));
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployCasterOnly_ERC721() public {
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.deployTokenVotingModule.selector, address(ERC721TOKEN), false, false, true, 1, 1, 1
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC721TokenholderCasterCreated(0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2, address(ERC721TOKEN), 1, 1);
//     mpCore.executeAction(actionInfo);
//   }
// }

// contract DelegateCallDeployTokenVotingModuleWithRoles is LlamaTokenVotingFactoryTest {
//   function authorizeScript() internal {
//     vm.prank(address(mpExecutor));
//     mpCore.setScriptAuthorization(address(FACTORY), true);
//   }

//   function test_CanDeployERC20TokenVotingModule() public {
//     authorizeScript();
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector,
//       address(ERC20TOKEN),
//       true,
//       true,
//       true,
//       CREATION_THRESHOLD,
//       MIN_APPROVAL_PCT,
//       MIN_DISAPPROVAL_PCT
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC20TokenholderActionCreatorCreated(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, address(ERC20TOKEN));
//     vm.expectEmit();
//     emit ERC20TokenholderCasterCreated(
//       0x1d2Fdf27Cbc73084b71477AA7290AAAC9715aD2c, address(ERC20TOKEN), MIN_APPROVAL_PCT, MIN_DISAPPROVAL_PCT
//     );
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployERC721TokenVotingModule() public {
//     authorizeScript();
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector,
//       address(ERC721TOKEN),
//       false,
//       true,
//       true,
//       1,
//       1,
//       1
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC721TokenholderActionCreatorCreated(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, address(ERC721TOKEN));
//     vm.expectEmit();
//     emit ERC721TokenholderCasterCreated(0x1d2Fdf27Cbc73084b71477AA7290AAAC9715aD2c, address(ERC721TOKEN), 1, 1);
//     vm.expectEmit();
//     emit RoleAssigned(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, 9, type(uint64).max, 1);
//     vm.expectEmit();
//     emit RoleAssigned(0x1d2Fdf27Cbc73084b71477AA7290AAAC9715aD2c, 10, type(uint64).max, 1);

//     mpCore.executeAction(actionInfo);
//   }

//   function test_RevertsIfNoModulesDeployed() public {
//     authorizeScript();
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector,
//       address(ERC20TOKEN),
//       true,
//       false,
//       false,
//       1,
//       1,
//       1
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectRevert(
//       abi.encodeWithSelector(
//         LlamaCore.FailedActionExecution.selector,
//         abi.encodeWithSelector(LlamaTokenVotingFactory.NoModulesDeployed.selector)
//       )
//     );
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployCreatorOnly_ERC20() public {
//     authorizeScript();
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector,
//       address(ERC20TOKEN),
//       true,
//       true,
//       false,
//       CREATION_THRESHOLD,
//       MIN_APPROVAL_PCT,
//       MIN_DISAPPROVAL_PCT
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC20TokenholderActionCreatorCreated(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, address(ERC20TOKEN));
//     vm.expectEmit();
//     emit RoleAssigned(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, 9, type(uint64).max, 1);
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployCasterOnly_ERC20() public {
//     authorizeScript();
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector,
//       address(ERC20TOKEN),
//       true,
//       false,
//       true,
//       CREATION_THRESHOLD,
//       MIN_APPROVAL_PCT,
//       MIN_DISAPPROVAL_PCT
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     emit ERC20TokenholderCasterCreated(
//       0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, address(ERC20TOKEN), MIN_APPROVAL_PCT, MIN_DISAPPROVAL_PCT
//     );
//     vm.expectEmit();
//     emit RoleAssigned(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, 9, type(uint64).max, 1);
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployCreatorOnly_ERC721() public {
//     authorizeScript();
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector,
//       address(ERC721TOKEN),
//       false,
//       true,
//       false,
//       1,
//       1,
//       1
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC721TokenholderActionCreatorCreated(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, address(ERC721TOKEN));
//     vm.expectEmit();
//     emit RoleAssigned(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, 9, type(uint64).max, 1);
//     mpCore.executeAction(actionInfo);
//   }

//   function test_CanDeployCasterOnly_ERC721() public {
//     authorizeScript();
//     bytes memory data = abi.encodeWithSelector(
//       LlamaTokenVotingFactory.delegateCallDeployTokenVotingModuleWithRoles.selector,
//       address(ERC721TOKEN),
//       false,
//       false,
//       true,
//       1,
//       1,
//       1
//     );

//     ActionInfo memory actionInfo = _createApproveAndQueueAction(data);

//     vm.expectEmit();
//     emit ERC721TokenholderCasterCreated(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, address(ERC721TOKEN), 1, 1);
//     vm.expectEmit();
//     emit RoleAssigned(0xaE207F1b391B8D25f7645F7AB2B10F0d0dDd5A81, 9, type(uint64).max, 1);
//     mpCore.executeAction(actionInfo);
//   }
// }

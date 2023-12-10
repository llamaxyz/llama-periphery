// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {ActionInfo} from "src/lib/Structs.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {LlamaERC20TokenHolderActionCreator} from "src/token-voting/LlamaERC20TokenHolderActionCreator.sol";
import {LlamaERC20TokenHolderCaster} from "src/token-voting/LlamaERC20TokenHolderCaster.sol";
import {LlamaERC721TokenHolderActionCreator} from "src/token-voting/LlamaERC721TokenHolderActionCreator.sol";
import {LlamaERC721TokenHolderCaster} from "src/token-voting/LlamaERC721TokenHolderCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract LlamaTokenVotingFactoryTest is LlamaTokenVotingTestSetup {
  event LlamaERC20TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event LlamaERC721TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event LlamaERC20TokenHolderCasterCreated(
    address caster, address indexed token, uint256 voteQuorumPct, uint256 vetoQuorumPct
  );
  event LlamaERC721TokenHolderCasterCreated(
    address caster, address indexed token, uint256 voteQuorumPct, uint256 vetoQuorumPct
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
  function test_SetsLlamaERC20TokenHolderActionCreatorLogicAddress() public {
    assertEq(
      address(tokenVotingFactory.ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC()),
      address(llamaERC20TokenHolderActionCreatorLogic)
    );
  }

  function test_SetsLlamaERC20TokenHolderCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC20_TOKENHOLDER_CASTER_LOGIC()), address(llamaERC20TokenHolderCasterLogic));
  }

  function test_SetsLlamaERC721TokenHolderActionCreatorLogicAddress() public {
    assertEq(
      address(tokenVotingFactory.ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC()),
      address(llamaERC721TokenHolderActionCreatorLogic)
    );
  }

  function test_SetsLlamaERC721TokenHolderCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC721_TOKENHOLDER_CASTER_LOGIC()), address(llamaERC721TokenHolderCasterLogic));
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
    CORE.castVote(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam2);
    CORE.castVote(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam3);
    CORE.castVote(CORE_TEAM_ROLE, actionInfo, "");
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
    LlamaERC20TokenHolderActionCreator llamaERC20TokenHolderActionCreator = LlamaERC20TokenHolderActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenHolderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    LlamaERC20TokenHolderCaster llamaERC20TokenHolderCaster = LlamaERC20TokenHolderCaster(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenHolderCasterLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit LlamaERC20TokenHolderActionCreatorCreated(
      address(llamaERC20TokenHolderActionCreator), address(erc20VotesToken)
    );
    vm.expectEmit();
    emit LlamaERC20TokenHolderCasterCreated(
      address(llamaERC20TokenHolderCaster), address(erc20VotesToken), ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC20TokenHolderActionCreator.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenHolderActionCreator.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenHolderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC20TokenHolderActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenHolderCaster.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenHolderCaster.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenHolderCaster.role(), tokenVotingCasterRole);
    assertEq(llamaERC20TokenHolderCaster.voteQuorumPct(), ERC20_MIN_APPROVAL_PCT);
    assertEq(llamaERC20TokenHolderCaster.vetoQuorumPct(), ERC20_MIN_DISAPPROVAL_PCT);
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
    LlamaERC721TokenHolderActionCreator llamaERC721TokenHolderActionCreator = LlamaERC721TokenHolderActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaERC721TokenHolderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    LlamaERC721TokenHolderCaster llamaERC721TokenHolderCaster = LlamaERC721TokenHolderCaster(
      Clones.predictDeterministicAddress(
        address(llamaERC721TokenHolderCasterLogic),
        keccak256(abi.encodePacked(address(erc721VotesToken), address(EXECUTOR))), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC721_CREATION_THRESHOLD);
    vm.expectEmit();
    emit LlamaERC721TokenHolderActionCreatorCreated(
      address(llamaERC721TokenHolderActionCreator), address(erc721VotesToken)
    );
    vm.expectEmit();
    emit LlamaERC721TokenHolderCasterCreated(
      address(llamaERC721TokenHolderCaster),
      address(erc721VotesToken),
      ERC721_MIN_APPROVAL_PCT,
      ERC721_MIN_DISAPPROVAL_PCT
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC721TokenHolderActionCreator.token()), address(erc721VotesToken));
    assertEq(address(llamaERC721TokenHolderActionCreator.llamaCore()), address(CORE));
    assertEq(llamaERC721TokenHolderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC721TokenHolderActionCreator.creationThreshold(), ERC721_CREATION_THRESHOLD);
    assertEq(address(llamaERC721TokenHolderCaster.token()), address(erc721VotesToken));
    assertEq(address(llamaERC721TokenHolderCaster.llamaCore()), address(CORE));
    assertEq(llamaERC721TokenHolderCaster.role(), tokenVotingCasterRole);
    assertEq(llamaERC721TokenHolderCaster.voteQuorumPct(), ERC721_MIN_APPROVAL_PCT);
    assertEq(llamaERC721TokenHolderCaster.vetoQuorumPct(), ERC721_MIN_DISAPPROVAL_PCT);
  }

  function test_CanBeDeployedByAnyone(address randomCaller) public {
    vm.assume(randomCaller != address(0));
    vm.deal(randomCaller, 1 ether);

    LlamaERC20TokenHolderActionCreator llamaERC20TokenHolderActionCreator = LlamaERC20TokenHolderActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenHolderActionCreatorLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), randomCaller)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    LlamaERC20TokenHolderCaster llamaERC20TokenHolderCaster = LlamaERC20TokenHolderCaster(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenHolderCasterLogic),
        keccak256(abi.encodePacked(address(erc20VotesToken), randomCaller)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit LlamaERC20TokenHolderActionCreatorCreated(
      address(llamaERC20TokenHolderActionCreator), address(erc20VotesToken)
    );
    vm.expectEmit();
    emit LlamaERC20TokenHolderCasterCreated(
      address(llamaERC20TokenHolderCaster), address(erc20VotesToken), ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT
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

    assertEq(address(llamaERC20TokenHolderActionCreator.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenHolderActionCreator.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenHolderActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC20TokenHolderActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenHolderCaster.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenHolderCaster.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenHolderCaster.role(), tokenVotingCasterRole);
    assertEq(llamaERC20TokenHolderCaster.voteQuorumPct(), ERC20_MIN_APPROVAL_PCT);
    assertEq(llamaERC20TokenHolderCaster.vetoQuorumPct(), ERC20_MIN_DISAPPROVAL_PCT);
  }
}

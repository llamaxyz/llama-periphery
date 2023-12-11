// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {ActionInfo} from "src/lib/Structs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {LlamaERC20TokenActionCreator} from "src/token-voting/LlamaERC20TokenActionCreator.sol";
import {LlamaERC20TokenCaster} from "src/token-voting/LlamaERC20TokenCaster.sol";
import {LlamaERC721TokenActionCreator} from "src/token-voting/LlamaERC721TokenActionCreator.sol";
import {LlamaERC721TokenCaster} from "src/token-voting/LlamaERC721TokenCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract LlamaTokenVotingFactoryTest is LlamaTokenVotingTestSetup {
  event LlamaTokenVotingInstanceCreated(
    address indexed deployer,
    ILlamaCore indexed llamaCore,
    address indexed token,
    bool isERC20,
    uint8 actionCreatorRole,
    uint8 casterRole,
    address llamaTokenActionCreator,
    address llamaTokenCaster,
    uint256 chainId
  );
  event ActionThresholdSet(uint256 newThreshold);
  event QuorumSet(uint256 voteQuorumPct, uint256 vetoQuorumPct);

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
  function test_SetsLlamaERC20TokenActionCreatorLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC20_TOKEN_ACTION_CREATOR_LOGIC()), address(llamaERC20TokenActionCreatorLogic));
  }

  function test_SetsLlamaERC20TokenCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC20_TOKEN_CASTER_LOGIC()), address(llamaERC20TokenCasterLogic));
  }

  function test_SetsLlamaERC721TokenActionCreatorLogicAddress() public {
    assertEq(
      address(tokenVotingFactory.ERC721_TOKEN_ACTION_CREATOR_LOGIC()), address(llamaERC721TokenActionCreatorLogic)
    );
  }

  function test_SetsLlamaERC721TokenCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.ERC721_TOKEN_CASTER_LOGIC()), address(llamaERC721TokenCasterLogic));
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
      ERC20_VOTE_QUORUM_PCT,
      ERC20_VETO_QUORUM_PCT
    );
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    // Compute addresses of ERC20 Token Voting Module
    LlamaERC20TokenActionCreator llamaERC20TokenActionCreator = LlamaERC20TokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenActionCreatorLogic),
        tokenVotingFactory.getNextSalt(address(EXECUTOR), address(CORE), address(erc20VotesToken)), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    LlamaERC20TokenCaster llamaERC20TokenCaster = LlamaERC20TokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenCasterLogic),
        tokenVotingFactory.getNextSalt(address(EXECUTOR), address(CORE), address(erc20VotesToken)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    uint256 initialNonce = tokenVotingFactory.nonces(address(EXECUTOR), address(CORE), address(erc20VotesToken));

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit QuorumSet(ERC20_VOTE_QUORUM_PCT, ERC20_VETO_QUORUM_PCT);
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc20VotesToken),
      true,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      address(llamaERC20TokenActionCreator),
      address(llamaERC20TokenCaster),
      block.chainid
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC20TokenActionCreator.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenActionCreator.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC20TokenActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenCaster.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenCaster.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenCaster.role(), tokenVotingCasterRole);
    assertEq(llamaERC20TokenCaster.voteQuorumPct(), ERC20_VOTE_QUORUM_PCT);
    assertEq(llamaERC20TokenCaster.vetoQuorumPct(), ERC20_VETO_QUORUM_PCT);
    assertEq(tokenVotingFactory.nonces(address(EXECUTOR), address(CORE), address(erc20VotesToken)), initialNonce + 1);
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
      ERC721_VOTE_QUORUM_PCT,
      ERC721_VETO_QUORUM_PCT
    );
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    // Compute addresses of ERC721 Token Voting Module
    LlamaERC721TokenActionCreator llamaERC721TokenActionCreator = LlamaERC721TokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaERC721TokenActionCreatorLogic),
        tokenVotingFactory.getNextSalt(address(EXECUTOR), address(CORE), address(erc721VotesToken)), // salt
        address(tokenVotingFactory) // deployer
      )
    );
    LlamaERC721TokenCaster llamaERC721TokenCaster = LlamaERC721TokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaERC721TokenCasterLogic),
        tokenVotingFactory.getNextSalt(address(EXECUTOR), address(CORE), address(erc721VotesToken)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    uint256 initialNonce = tokenVotingFactory.nonces(address(EXECUTOR), address(CORE), address(erc721VotesToken));

    // Execute call to `deployTokenVotingModule`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC721_CREATION_THRESHOLD);
    vm.expectEmit();
    emit QuorumSet(ERC721_VOTE_QUORUM_PCT, ERC721_VETO_QUORUM_PCT);
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc721VotesToken),
      false,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      address(llamaERC721TokenActionCreator),
      address(llamaERC721TokenCaster),
      block.chainid
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC721TokenActionCreator.token()), address(erc721VotesToken));
    assertEq(address(llamaERC721TokenActionCreator.llamaCore()), address(CORE));
    assertEq(llamaERC721TokenActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC721TokenActionCreator.creationThreshold(), ERC721_CREATION_THRESHOLD);
    assertEq(address(llamaERC721TokenCaster.token()), address(erc721VotesToken));
    assertEq(address(llamaERC721TokenCaster.llamaCore()), address(CORE));
    assertEq(llamaERC721TokenCaster.role(), tokenVotingCasterRole);
    assertEq(llamaERC721TokenCaster.voteQuorumPct(), ERC721_VOTE_QUORUM_PCT);
    assertEq(llamaERC721TokenCaster.vetoQuorumPct(), ERC721_VETO_QUORUM_PCT);
    assertEq(tokenVotingFactory.nonces(address(EXECUTOR), address(CORE), address(erc721VotesToken)), initialNonce + 1);
  }

  function test_CanBeDeployedByAnyone(address randomCaller) public {
    vm.assume(randomCaller != address(0));
    vm.deal(randomCaller, 1 ether);

    LlamaERC20TokenActionCreator llamaERC20TokenActionCreator = LlamaERC20TokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenActionCreatorLogic),
        tokenVotingFactory.getNextSalt(randomCaller, address(CORE), address(erc20VotesToken)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    LlamaERC20TokenCaster llamaERC20TokenCaster = LlamaERC20TokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaERC20TokenCasterLogic),
        tokenVotingFactory.getNextSalt(randomCaller, address(CORE), address(erc20VotesToken)), // salt
        address(tokenVotingFactory) // deployer
      )
    );

    uint256 initialNonce = tokenVotingFactory.nonces(randomCaller, address(CORE), address(erc20VotesToken));

    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit QuorumSet(ERC20_VOTE_QUORUM_PCT, ERC20_VETO_QUORUM_PCT);
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      randomCaller,
      CORE,
      address(erc20VotesToken),
      true,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      address(llamaERC20TokenActionCreator),
      address(llamaERC20TokenCaster),
      block.chainid
    );

    vm.prank(randomCaller);
    tokenVotingFactory.deployTokenVotingModule(
      CORE,
      address(erc20VotesToken),
      true,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      ERC20_VOTE_QUORUM_PCT,
      ERC20_VETO_QUORUM_PCT
    );

    assertEq(address(llamaERC20TokenActionCreator.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenActionCreator.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC20TokenActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenCaster.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenCaster.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenCaster.role(), tokenVotingCasterRole);
    assertEq(llamaERC20TokenCaster.voteQuorumPct(), ERC20_VOTE_QUORUM_PCT);
    assertEq(llamaERC20TokenCaster.vetoQuorumPct(), ERC20_VETO_QUORUM_PCT);
    assertEq(tokenVotingFactory.nonces(randomCaller, address(CORE), address(erc20VotesToken)), initialNonce + 1);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {ActionInfo, CasterConfig} from "src/lib/Structs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {LlamaTokenAdapterVotesTimestamp} from "src/token-voting/token-adapters/LlamaTokenAdapterVotesTimestamp.sol";
import {LlamaTokenActionCreator} from "src/token-voting/LlamaTokenActionCreator.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract LlamaTokenVotingFactoryTest is LlamaTokenVotingTestSetup {
  event LlamaTokenVotingInstanceCreated(
    address indexed deployer,
    ILlamaCore indexed llamaCore,
    address indexed token,
    ILlamaTokenAdapter tokenAdapterLogic,
    ILlamaTokenAdapter tokenAdapter,
    uint256 nonce,
    uint8 actionCreatorRole,
    uint8 casterRole,
    LlamaTokenActionCreator llamaTokenActionCreator,
    LlamaTokenCaster llamaTokenCaster,
    uint256 chainId
  );
  event ActionThresholdSet(uint256 newThreshold);
  event QuorumPctSet(uint16 voteQuorumPct, uint16 vetoQuorumPct);

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
    assertEq(address(tokenVotingFactory.LLAMA_TOKEN_ACTION_CREATOR_LOGIC()), address(llamaTokenActionCreatorLogic));
  }

  function test_SetsLlamaERC20TokenCasterLogicAddress() public {
    assertEq(address(tokenVotingFactory.LLAMA_TOKEN_CASTER_LOGIC()), address(llamaTokenCasterLogic));
  }
}

contract DeployTokenVotingModule is LlamaTokenVotingFactoryTest {
  function _setPermissionCreateApproveAndQueueAction(bytes memory data) internal returns (ActionInfo memory actionInfo) {
    // Assign `deploy` permission to the `CORE_TEAM_ROLE` role.
    ILlamaPolicy.PermissionData memory deployTokenVotingPermission = ILlamaPolicy.PermissionData(
      address(tokenVotingFactory), LlamaTokenVotingFactory.deploy.selector, address(STRATEGY)
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
    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    LlamaTokenVotingFactory.LlamaTokenVotingConfig memory config = LlamaTokenVotingFactory.LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC20 token.
    bytes memory data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    bytes32 salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(0)));

    // Compute addresses of ERC20 Token Voting Module
    LlamaTokenActionCreator llamaERC20TokenActionCreator = LlamaTokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaTokenActionCreatorLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );
    LlamaTokenCaster llamaERC20TokenCaster = LlamaTokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaTokenCasterLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );
    ILlamaTokenAdapter llamaERC20TokenAdapter = ILlamaTokenAdapter(
      Clones.predictDeterministicAddress(
        address(llamaTokenAdapterTimestampLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deploy`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit QuorumPctSet(ERC20_VOTE_QUORUM_PCT, ERC20_VETO_QUORUM_PCT);
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc20VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC20TokenAdapter,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      llamaERC20TokenActionCreator,
      llamaERC20TokenCaster,
      block.chainid
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenActionCreator.llamaCore()), address(CORE));
    (uint16 voteQuorumPct, uint16 vetoQuorumPct) = llamaERC20TokenCaster.getQuorum();
    assertEq(ERC20_VOTE_QUORUM_PCT, voteQuorumPct);
    assertEq(ERC20_VETO_QUORUM_PCT, vetoQuorumPct);
    assertEq(llamaERC20TokenActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC20TokenActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenCaster.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenCaster.role(), tokenVotingCasterRole);
  }

  function test_CanDeployERC721TokenVotingModule() public {
    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc721VotesToken)));
    LlamaTokenVotingFactory.LlamaTokenVotingConfig memory config = LlamaTokenVotingFactory.LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC721_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC721 token.
    bytes memory data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    bytes32 salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(0)));

    // Compute addresses of ERC721 Token Voting Module
    LlamaTokenActionCreator llamaERC721TokenActionCreator = LlamaTokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaTokenActionCreatorLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );
    LlamaTokenCaster llamaERC721TokenCaster = LlamaTokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaTokenCasterLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );
    ILlamaTokenAdapter llamaERC721TokenAdapter = ILlamaTokenAdapter(
      Clones.predictDeterministicAddress(
        address(llamaTokenAdapterTimestampLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deploy`.
    vm.expectEmit();
    emit ActionThresholdSet(ERC721_CREATION_THRESHOLD);
    vm.expectEmit();
    emit QuorumPctSet(ERC721_VOTE_QUORUM_PCT, ERC721_VETO_QUORUM_PCT);
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc721VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC721TokenAdapter,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      llamaERC721TokenActionCreator,
      llamaERC721TokenCaster,
      block.chainid
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC721TokenAdapter.token()), address(erc721VotesToken));
    assertEq(address(llamaERC721TokenActionCreator.llamaCore()), address(CORE));
    (uint16 voteQuorumPct, uint16 vetoQuorumPct) = llamaERC721TokenCaster.getQuorum();
    assertEq(ERC721_VOTE_QUORUM_PCT, voteQuorumPct);
    assertEq(ERC721_VETO_QUORUM_PCT, vetoQuorumPct);
    assertEq(llamaERC721TokenActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC721TokenActionCreator.creationThreshold(), ERC721_CREATION_THRESHOLD);
    assertEq(address(llamaERC721TokenAdapter.token()), address(erc721VotesToken));
    assertEq(address(llamaERC721TokenCaster.llamaCore()), address(CORE));
    assertEq(llamaERC721TokenCaster.role(), tokenVotingCasterRole);
  }

  function test_CanBeDeployedByAnyone(address randomCaller) public {
    vm.assume(randomCaller != address(0));
    vm.deal(randomCaller, 1 ether);

    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    bytes32 salt = keccak256(abi.encodePacked(randomCaller, address(CORE), adapterConfig, uint256(0)));

    LlamaTokenActionCreator llamaERC20TokenActionCreator = LlamaTokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaTokenActionCreatorLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );

    LlamaTokenCaster llamaERC20TokenCaster = LlamaTokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaTokenCasterLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );
    ILlamaTokenAdapter llamaERC20TokenAdapter = ILlamaTokenAdapter(
      Clones.predictDeterministicAddress(
        address(llamaTokenAdapterTimestampLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );

    vm.expectEmit();
    emit ActionThresholdSet(ERC20_CREATION_THRESHOLD);
    vm.expectEmit();
    emit QuorumPctSet(ERC20_VOTE_QUORUM_PCT, ERC20_VETO_QUORUM_PCT);
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      randomCaller,
      CORE,
      address(erc20VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC20TokenAdapter,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      llamaERC20TokenActionCreator,
      llamaERC20TokenCaster,
      block.chainid
    );

    LlamaTokenVotingFactory.LlamaTokenVotingConfig memory config = LlamaTokenVotingFactory.LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    vm.prank(randomCaller);
    tokenVotingFactory.deploy(config);

    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenActionCreator.llamaCore()), address(CORE));
    (uint16 voteQuorumPct, uint16 vetoQuorumPct) = llamaERC20TokenCaster.getQuorum();
    assertEq(ERC20_VOTE_QUORUM_PCT, voteQuorumPct);
    assertEq(ERC20_VETO_QUORUM_PCT, vetoQuorumPct);
    assertEq(llamaERC20TokenActionCreator.role(), tokenVotingActionCreatorRole);
    assertEq(llamaERC20TokenActionCreator.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenCaster.llamaCore()), address(CORE));
    assertEq(llamaERC20TokenCaster.role(), tokenVotingCasterRole);
  }

  function test_CanBeDeployedMoreThanOnceBySameDeployer() public {
    /////////////////////
    // First deployment//
    /////////////////////

    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    LlamaTokenVotingFactory.LlamaTokenVotingConfig memory config = LlamaTokenVotingFactory.LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC20 token.
    bytes memory data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);

    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    bytes32 salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(0)));

    // Compute addresses of ERC20 Token Voting Module
    LlamaTokenActionCreator llamaERC20TokenActionCreator = LlamaTokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaTokenActionCreatorLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );
    LlamaTokenCaster llamaERC20TokenCaster = LlamaTokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaTokenCasterLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );
    ILlamaTokenAdapter llamaERC20TokenAdapter = ILlamaTokenAdapter(
      Clones.predictDeterministicAddress(
        address(llamaTokenAdapterTimestampLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deploy`.
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc20VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC20TokenAdapter,
      0,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      llamaERC20TokenActionCreator,
      llamaERC20TokenCaster,
      block.chainid
    );
    CORE.executeAction(actionInfo);

    //////////////////////
    // Second deployment//
    //////////////////////

    adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    config = LlamaTokenVotingFactory.LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      1,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC20 token.
    data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);

    actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(1)));

    // Compute addresses of ERC20 Token Voting Module
    llamaERC20TokenActionCreator = LlamaTokenActionCreator(
      Clones.predictDeterministicAddress(
        address(llamaTokenActionCreatorLogic),
        salt, // salt
        address(tokenVotingFactory) // deployer
      )
    );
    llamaERC20TokenCaster = LlamaTokenCaster(
      Clones.predictDeterministicAddress(
        address(llamaTokenCasterLogic),
        salt, // salt
        address(tokenVotingFactory) // deployer
      )
    );
    llamaERC20TokenAdapter = ILlamaTokenAdapter(
      Clones.predictDeterministicAddress(
        address(llamaTokenAdapterTimestampLogic),
        salt,
        address(tokenVotingFactory) // deployer
      )
    );

    // Execute call to `deploy`.
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc20VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC20TokenAdapter,
      1,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      llamaERC20TokenActionCreator,
      llamaERC20TokenCaster,
      block.chainid
    );
    CORE.executeAction(actionInfo);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";

import {ActionInfo, LlamaTokenVotingConfig} from "src/lib/Structs.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {LlamaDeployTokenGovernorWithRoleScript} from
  "src/token-voting/llama-scripts/LlamaDeployTokenGovernorWithRoleScript.sol";
import {LlamaTokenAdapterVotesTimestamp} from "src/token-voting/token-adapters/LlamaTokenAdapterVotesTimestamp.sol";
import {LlamaTokenGovernor} from "src/token-voting/LlamaTokenGovernor.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract LlamaTokenVotingFactoryTest is LlamaTokenVotingTestSetup {
  event LlamaTokenVotingInstanceCreated(
    address indexed deployer,
    ILlamaCore indexed llamaCore,
    address indexed token,
    ILlamaTokenAdapter tokenAdapterLogic,
    ILlamaTokenAdapter tokenAdapter,
    uint256 nonce,
    uint8 governorRole,
    LlamaTokenGovernor llamaTokenGovernor,
    uint256 chainId
  );
  event ActionThresholdSet(uint256 newThreshold);
  event PeriodPctSet(uint16 delayPeriodPct, uint16 castingPeriodPct, uint16 submissionPeriodPct);
  event QuorumPctSet(uint16 voteQuorumPct, uint16 vetoQuorumPct);
  event RoleAssigned(address indexed policyholder, uint8 indexed role, uint64 expiration, uint96 quantity);
  event RoleInitialized(uint8 indexed role, RoleDescription description);

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
  function test_SetsLlamaERC20TokenGovernorLogicAddress() public {
    assertEq(address(tokenVotingFactory.LLAMA_TOKEN_GOVERNOR_LOGIC()), address(llamaTokenGovernorLogic));
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
    LlamaTokenVotingConfig memory config = LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingGovernorRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC20 token.
    bytes memory data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    bytes32 salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(0)));

    // Compute addresses of ERC20 Token Voting Module
    LlamaTokenGovernor llamaERC20TokenGovernor = LlamaTokenGovernor(
      Clones.predictDeterministicAddress(
        address(llamaTokenGovernorLogic),
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
    emit PeriodPctSet(uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS));
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc20VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC20TokenAdapter,
      0,
      tokenVotingGovernorRole,
      llamaERC20TokenGovernor,
      block.chainid
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenGovernor.llamaCore()), address(CORE));
    (uint16 voteQuorumPct, uint16 vetoQuorumPct) = llamaERC20TokenGovernor.getQuorum();
    assertEq(ERC20_VOTE_QUORUM_PCT, voteQuorumPct);
    assertEq(ERC20_VETO_QUORUM_PCT, vetoQuorumPct);
    assertEq(llamaERC20TokenGovernor.role(), tokenVotingGovernorRole);
    assertEq(llamaERC20TokenGovernor.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
  }

  function test_CanDeployERC721TokenVotingModule() public {
    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc721VotesToken)));
    LlamaTokenVotingConfig memory config = LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingGovernorRole,
      ERC721_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC721 token.
    bytes memory data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);
    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    bytes32 salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(0)));

    // Compute addresses of ERC721 Token Voting Module
    LlamaTokenGovernor llamaERC721TokenGovernor = LlamaTokenGovernor(
      Clones.predictDeterministicAddress(
        address(llamaTokenGovernorLogic),
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
    emit PeriodPctSet(uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS));
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc721VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC721TokenAdapter,
      0,
      tokenVotingGovernorRole,
      llamaERC721TokenGovernor,
      block.chainid
    );
    CORE.executeAction(actionInfo);

    assertEq(address(llamaERC721TokenAdapter.token()), address(erc721VotesToken));
    assertEq(address(llamaERC721TokenGovernor.llamaCore()), address(CORE));
    (uint16 voteQuorumPct, uint16 vetoQuorumPct) = llamaERC721TokenGovernor.getQuorum();
    assertEq(ERC721_VOTE_QUORUM_PCT, voteQuorumPct);
    assertEq(ERC721_VETO_QUORUM_PCT, vetoQuorumPct);
    assertEq(llamaERC721TokenGovernor.role(), tokenVotingGovernorRole);
    assertEq(llamaERC721TokenGovernor.creationThreshold(), ERC721_CREATION_THRESHOLD);
    assertEq(address(llamaERC721TokenAdapter.token()), address(erc721VotesToken));
  }

  function test_CanBeDeployedByAnyone(address randomCaller) public {
    vm.assume(randomCaller != address(0));
    vm.deal(randomCaller, 1 ether);

    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    bytes32 salt = keccak256(abi.encodePacked(randomCaller, address(CORE), adapterConfig, uint256(0)));

    LlamaTokenGovernor llamaERC20TokenGovernor = LlamaTokenGovernor(
      Clones.predictDeterministicAddress(
        address(llamaTokenGovernorLogic),
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
    emit PeriodPctSet(uint16(ONE_QUARTER_IN_BPS), uint16(TWO_QUARTERS_IN_BPS), uint16(ONE_QUARTER_IN_BPS));
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      randomCaller,
      CORE,
      address(erc20VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC20TokenAdapter,
      0,
      tokenVotingGovernorRole,
      llamaERC20TokenGovernor,
      block.chainid
    );

    LlamaTokenVotingConfig memory config = LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingGovernorRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    vm.prank(randomCaller);
    tokenVotingFactory.deploy(config);

    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
    assertEq(address(llamaERC20TokenGovernor.llamaCore()), address(CORE));
    (uint16 voteQuorumPct, uint16 vetoQuorumPct) = llamaERC20TokenGovernor.getQuorum();
    assertEq(ERC20_VOTE_QUORUM_PCT, voteQuorumPct);
    assertEq(ERC20_VETO_QUORUM_PCT, vetoQuorumPct);
    assertEq(llamaERC20TokenGovernor.role(), tokenVotingGovernorRole);
    assertEq(llamaERC20TokenGovernor.creationThreshold(), ERC20_CREATION_THRESHOLD);
    assertEq(address(llamaERC20TokenAdapter.token()), address(erc20VotesToken));
  }

  function test_CanBeDeployedMoreThanOnceBySameDeployer() public {
    /////////////////////
    // First deployment//
    /////////////////////

    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    LlamaTokenVotingConfig memory config = LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      0,
      tokenVotingGovernorRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC20 token.
    bytes memory data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);

    ActionInfo memory actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    bytes32 salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(0)));

    // Compute addresses of ERC20 Token Voting Module
    LlamaTokenGovernor llamaERC20TokenGovernor = LlamaTokenGovernor(
      Clones.predictDeterministicAddress(
        address(llamaTokenGovernorLogic),
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
      tokenVotingGovernorRole,
      llamaERC20TokenGovernor,
      block.chainid
    );
    CORE.executeAction(actionInfo);

    //////////////////////
    // Second deployment//
    //////////////////////

    adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    config = LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      1,
      tokenVotingGovernorRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );

    // Set up action to call `deploy` with the ERC20 token.
    data = abi.encodeWithSelector(LlamaTokenVotingFactory.deploy.selector, config);

    actionInfo = _setPermissionCreateApproveAndQueueAction(data);

    salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(1)));

    // Compute addresses of ERC20 Token Voting Module
    llamaERC20TokenGovernor = LlamaTokenGovernor(
      Clones.predictDeterministicAddress(
        address(llamaTokenGovernorLogic),
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
      tokenVotingGovernorRole,
      llamaERC20TokenGovernor,
      block.chainid
    );
    CORE.executeAction(actionInfo);
  }
}

contract LlamaDeployTokenGovernorWithRole is LlamaTokenVotingFactoryTest {
  function test_run() public {
    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    bytes32 salt = keccak256(abi.encodePacked(address(EXECUTOR), address(CORE), adapterConfig, uint256(0)));
    tokenVotingGovernorRole = POLICY.numRoles() + 1;
    LlamaTokenVotingConfig memory tokenVotingConfig = LlamaTokenVotingConfig(
      CORE,
      llamaTokenAdapterTimestampLogic,
      abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken))),
      0,
      tokenVotingGovernorRole,
      ERC20_CREATION_THRESHOLD,
      defaultCasterConfig
    );
    RoleDescription description = RoleDescription.wrap("Token Voting Governor Role");
    LlamaDeployTokenGovernorWithRoleScript llamaDeployTokenGovernorWithRoleScript =
      new LlamaDeployTokenGovernorWithRoleScript(tokenVotingFactory);
    bytes memory data =
      abi.encodeWithSelector(llamaDeployTokenGovernorWithRoleScript.run.selector, tokenVotingConfig, description);

    LlamaTokenGovernor llamaERC20TokenGovernor = LlamaTokenGovernor(
      Clones.predictDeterministicAddress(
        address(llamaTokenGovernorLogic),
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
    vm.startPrank(address(EXECUTOR));
    // part #1: authorize script
    CORE.setScriptAuthorization(address(llamaDeployTokenGovernorWithRoleScript), true);

    // part #2: permission the script
    POLICY.setRolePermission(
      CORE_TEAM_ROLE,
      ILlamaPolicy.PermissionData(
        address(llamaDeployTokenGovernorWithRoleScript),
        llamaDeployTokenGovernorWithRoleScript.run.selector,
        address(STRATEGY)
      ),
      true
    );
    vm.stopPrank();

    // part #3: create, approve, and execute action
    vm.prank(coreTeam4);
    uint256 actionId =
      CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(llamaDeployTokenGovernorWithRoleScript), 0, data, "");
    ActionInfo memory actionInfo = ActionInfo(
      actionId, coreTeam4, CORE_TEAM_ROLE, STRATEGY, address(llamaDeployTokenGovernorWithRoleScript), 0, data
    );

    vm.prank(coreTeam1);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam2);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam3);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");

    vm.expectEmit();
    emit RoleInitialized(tokenVotingGovernorRole, description);
    vm.expectEmit();
    emit LlamaTokenVotingInstanceCreated(
      address(EXECUTOR),
      CORE,
      address(erc20VotesToken),
      llamaTokenAdapterTimestampLogic,
      llamaERC20TokenAdapter,
      0,
      tokenVotingGovernorRole,
      llamaERC20TokenGovernor,
      block.chainid
    );
    vm.expectEmit();
    emit RoleAssigned(address(llamaERC20TokenGovernor), tokenVotingGovernorRole, type(uint64).max, 1);
    CORE.executeAction(actionInfo);
  }
}

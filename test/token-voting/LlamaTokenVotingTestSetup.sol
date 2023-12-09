// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {MockERC20Votes} from "test/mock/MockERC20Votes.sol";
import {MockERC721Votes} from "test/mock/MockERC721Votes.sol";
import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";

import {DeployLlamaTokenVotingFactory} from "script/DeployLlamaTokenVotingFactory.s.sol";

import {Action, ActionInfo, PermissionData} from "src/lib/Structs.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ILlamaRelativeStrategyBase} from "src/interfaces/ILlamaRelativeStrategyBase.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {ERC20TokenholderCaster} from "src/token-voting/ERC20TokenholderCaster.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {ERC721TokenholderCaster} from "src/token-voting/ERC721TokenholderCaster.sol";

contract LlamaTokenVotingTestSetup is LlamaPeripheryTestSetup, DeployLlamaTokenVotingFactory {
  // Percentages
  uint16 internal constant ONE_HUNDRED_IN_BPS = 10_000;
  uint256 internal constant ONE_THIRD_IN_BPS = 3333;
  uint256 internal constant TWO_THIRDS_IN_BPS = 6667;

  // ERC20 Token Voting Constants.
  uint256 public constant ERC20_CREATION_THRESHOLD = 500_000e18;
  uint256 public constant ERC20_MIN_APPROVAL_PCT = 1000;
  uint256 public constant ERC20_MIN_DISAPPROVAL_PCT = 1000;

  // ERC721 Token Voting Constants.
  uint256 public constant ERC721_CREATION_THRESHOLD = 1;
  uint256 public constant ERC721_MIN_APPROVAL_PCT = 1000;
  uint256 public constant ERC721_MIN_DISAPPROVAL_PCT = 1000;

  // Votes Tokens
  MockERC20Votes public erc20VotesToken;
  MockERC721Votes public erc721VotesToken;

  // Token Voting Roles
  uint8 tokenVotingActionCreatorRole;
  uint8 tokenVotingCasterRole;
  uint8 madeUpRole;

  // Token holders.
  address tokenHolder0;
  uint256 tokenHolder0PrivateKey;
  address tokenHolder1;
  uint256 tokenHolder1PrivateKey;
  address tokenHolder2;
  uint256 tokenHolder2PrivateKey;
  address tokenHolder3;
  uint256 tokenHolder3PrivateKey;
  address notTokenHolder;
  uint256 notTokenHolderPrivateKey;

  function setUp() public virtual override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the Llama Token Voting factory and logic contracts.
    DeployLlamaTokenVotingFactory.run();

    // Deploy the ERC20 and ERC721 tokens.
    erc20VotesToken = new MockERC20Votes();
    erc721VotesToken = new MockERC721Votes();

    // Setting up tokenholder addresses and private keys.
    (tokenHolder0, tokenHolder0PrivateKey) = makeAddrAndKey("tokenHolder0");
    (tokenHolder1, tokenHolder1PrivateKey) = makeAddrAndKey("tokenHolder1");
    (tokenHolder2, tokenHolder2PrivateKey) = makeAddrAndKey("tokenHolder2");
    (tokenHolder3, tokenHolder3PrivateKey) = makeAddrAndKey("tokenHolder3");
    (notTokenHolder, notTokenHolderPrivateKey) = makeAddrAndKey("notTokenHolder");

    // Initialize required roles.
    vm.startPrank(address(EXECUTOR));
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
    tokenVotingActionCreatorRole = POLICY.numRoles();
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Caster Role"));
    tokenVotingCasterRole = POLICY.numRoles();
    POLICY.initializeRole(RoleDescription.wrap("Made Up Role"));
    madeUpRole = POLICY.numRoles();
    vm.stopPrank();
  }

  // =========================
  // ======== Helpers ========
  // =========================

  function _deployERC20TokenVotingModuleAndSetRole()
    internal
    returns (ERC20TokenholderActionCreator, ERC20TokenholderCaster)
  {
    vm.startPrank(address(EXECUTOR));
    // Deploy Token Voting Module
    (address erc20TokenholderActionCreator, address erc20TokenholderCaster) = tokenVotingFactory.deployTokenVotingModule(
      address(erc20VotesToken),
      true,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC20_CREATION_THRESHOLD,
      ERC20_MIN_APPROVAL_PCT,
      ERC20_MIN_DISAPPROVAL_PCT
    );
    // Assign roles to Token Voting Modules
    POLICY.setRoleHolder(
      tokenVotingActionCreatorRole, erc20TokenholderActionCreator, DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION
    );
    POLICY.setRoleHolder(tokenVotingCasterRole, erc20TokenholderCaster, DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION);
    vm.stopPrank();

    return
      (ERC20TokenholderActionCreator(erc20TokenholderActionCreator), ERC20TokenholderCaster(erc20TokenholderCaster));
  }

  function _deployERC721TokenVotingModuleAndSetRole()
    internal
    returns (ERC721TokenholderActionCreator, ERC721TokenholderCaster)
  {
    vm.startPrank(address(EXECUTOR));
    // Deploy Token Voting Module
    (address erc721TokenholderActionCreator, address erc721TokenholderCaster) = tokenVotingFactory
      .deployTokenVotingModule(
      address(erc721VotesToken),
      false,
      tokenVotingActionCreatorRole,
      tokenVotingCasterRole,
      ERC721_CREATION_THRESHOLD,
      ERC721_MIN_APPROVAL_PCT,
      ERC721_MIN_DISAPPROVAL_PCT
    );
    // Assign roles to Token Voting Modules
    POLICY.setRoleHolder(
      tokenVotingActionCreatorRole, erc721TokenholderActionCreator, DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION
    );
    POLICY.setRoleHolder(tokenVotingCasterRole, erc721TokenholderCaster, DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION);
    vm.stopPrank();

    return
      (ERC721TokenholderActionCreator(erc721TokenholderActionCreator), ERC721TokenholderCaster(erc721TokenholderCaster));
  }

  function _setRolePermissionToTokenholderActionCreator() internal {
    // Assign permission for `MockProtocol.pause` to the TokenholderActionCreator.
    vm.prank(address(EXECUTOR));
    POLICY.setRolePermission(
      tokenVotingActionCreatorRole,
      ILlamaPolicy.PermissionData(address(mockProtocol), PAUSE_SELECTOR, address(STRATEGY)),
      true
    );
    vm.stopPrank();
  }

  function _deployRelativeQuantityQuorumAndSetRolePermissionToCoreTeam(uint8 _tokenVotingCasterRole)
    internal
    returns (ILlamaStrategy newStrategy)
  {
    uint8[] memory forceRoles = new uint8[](0);

    ILlamaRelativeStrategyBase.Config memory strategyConfig = ILlamaRelativeStrategyBase.Config({
      approvalPeriod: 1 days,
      queuingPeriod: 1 days,
      expirationPeriod: 1 days,
      isFixedLengthApprovalPeriod: false,
      minApprovalPct: ONE_HUNDRED_IN_BPS,
      minDisapprovalPct: ONE_HUNDRED_IN_BPS,
      approvalRole: _tokenVotingCasterRole,
      disapprovalRole: _tokenVotingCasterRole,
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
      vm.prank(address(EXECUTOR));
      POLICY.setRolePermission(
        CORE_TEAM_ROLE, ILlamaPolicy.PermissionData(address(mockProtocol), PAUSE_SELECTOR, address(newStrategy)), true
      );
    }
  }

  function _createActionWithTokenVotingStrategy(ILlamaStrategy _tokenVotingStrategy)
    public
    returns (ActionInfo memory _actionInfo)
  {
    bytes memory data = abi.encodeCall(mockProtocol.pause, (true));
    vm.prank(coreTeam1);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, _tokenVotingStrategy, address(mockProtocol), 0, data, "");
    _actionInfo = ActionInfo(actionId, coreTeam1, CORE_TEAM_ROLE, _tokenVotingStrategy, address(mockProtocol), 0, data);
  }
}

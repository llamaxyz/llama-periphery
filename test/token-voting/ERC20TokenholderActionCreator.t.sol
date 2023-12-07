// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {ERC20Votes} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";

import {Action, ActionInfo} from "src/lib/Structs.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {TokenholderActionCreator} from "src/token-voting/TokenholderActionCreator.sol";

import {MockERC20Votes} from "test/mock/MockERC20Votes.sol";
import {PeripheryTestSetup} from "test/PeripheryTestSetup.sol";
import {LlamaCoreSigUtils} from "test/utils/LlamaCoreSigUtils.sol";

contract ERC20TokenholderActionCreatorTest is PeripheryTestSetup {
  event ActionCreated(
    uint256 id,
    address indexed creator,
    uint8 role,
    ILlamaStrategy indexed strategy,
    address indexed target,
    uint256 value,
    bytes data,
    string description
  );

  event ActionCanceled(uint256 id, address indexed creator);

  event ActionThresholdSet(uint256 newThreshold);

  MockERC20Votes mockErc20Votes;
  ERC20Votes token;
  address tokenHolder1 = makeAddr("tokenHolder1");
  address tokenHolder2 = makeAddr("tokenHolder2");
  address tokenHolder3 = makeAddr("tokenHolder3");
  address notATokenHolder = makeAddr("notATokenHolder");

  function setUp() public virtual override {
    PeripheryTestSetup.setUp();
    vm.deal(address(this), 1 ether);
    vm.deal(address(msg.sender), 1 ether);

    mockErc20Votes = new MockERC20Votes();
    token = ERC20Votes(address(mockErc20Votes));
  }
}

contract Constructor is ERC20TokenholderActionCreatorTest {
  function test_RevertsIf_InvalidLlamaCore() public {
    // With invalid LlamaCore instance, TokenholderActionCreator.InvalidLlamaCoreAddress is unreachable
    vm.expectRevert();
    new ERC20TokenholderActionCreator(token, ILlamaCore(makeAddr("invalid-llama-core")), uint256(0));
  }

  function test_RevertsIf_InvalidTokenAddress() public {
    vm.expectRevert(); // will EvmError: Revert vecause totalSupply fn does not exist
    new ERC20TokenholderActionCreator(ERC20Votes(makeAddr("invalid-token")), CORE, uint256(0));
  }

  function test_RevertsIf_CreationThresholdExceedsTotalSupply() public {
    mockErc20Votes.mint(tokenHolder1, 1_000_000e18); // we use mockErc20Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
    new ERC20TokenholderActionCreator(token, CORE, 17_000_000_000_000_000_000_000_000);
  }

  function test_ProperlySetsConstructorArguments() public {
    uint256 threshold = 500_000e18;
    mockErc20Votes.mint(tokenHolder1, 1_000_000e18); // we use mockErc20Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC20TokenholderActionCreator actionCreator = new ERC20TokenholderActionCreator(token, CORE, threshold);
    assertEq(address(actionCreator.TOKEN()), address(token));
    assertEq(address(actionCreator.LLAMA_CORE()), address(CORE));
    assertEq(actionCreator.creationThreshold(), threshold);
  }
}

contract TokenHolderCreateAction is ERC20TokenholderActionCreatorTest {
  bytes data = abi.encodeCall(
    POLICY.setRoleHolder, (CORE_TEAM_ROLE, address(0xdeadbeef), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION)
  );
  uint256 threshold = 500_000e18;

  function test_RevertsIf_InsufficientBalance() public {
    mockErc20Votes.mint(tokenHolder1, 1_000_000e18); // we use mockErc20Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC20TokenholderActionCreator actionCreator = new ERC20TokenholderActionCreator(token, CORE, threshold);

    vm.prank(notATokenHolder);
    vm.expectRevert(abi.encodeWithSelector(TokenholderActionCreator.InsufficientBalance.selector, 0));
    actionCreator.createAction(CORE_TEAM_ROLE, STRATEGY, address(POLICY), 0, data, "");
  }

  function test_RevertsIf_TokenholderActionCreatorDoesNotHavePermission() public {
    mockErc20Votes.mint(tokenHolder1, threshold); // we use mockErc20Votes because IVotesToken is an
    // interface without the `mint` function
    vm.prank(tokenHolder1);
    mockErc20Votes.delegate(tokenHolder1); // we use mockErc20Votes because IVotesToken is an interface without
    // the `delegate` function

    vm.warp(block.timestamp + 1);

    ERC20TokenholderActionCreator actionCreator = new ERC20TokenholderActionCreator(token, CORE, threshold);
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    token.getPastVotes(tokenHolder1, block.timestamp - 1);

    vm.expectRevert(ILlamaCore.PolicyholderDoesNotHavePermission.selector);
    vm.prank(tokenHolder1);
    actionCreator.createAction(CORE_TEAM_ROLE, STRATEGY, address(POLICY), 0, data, "");
  }

  function test_ProperlyCreatesAction() public {
    mockErc20Votes.mint(tokenHolder1, threshold); // we use mockErc20Votes because IVotesToken is an
    // interface without the `delegate` function
    vm.prank(tokenHolder1);
    mockErc20Votes.delegate(tokenHolder1); // we use mockErc20Votes because IVotesToken is an interface without
    // the `delegate` function

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    ERC20TokenholderActionCreator actionCreator = new ERC20TokenholderActionCreator(token, CORE, threshold);

    vm.startPrank(address(EXECUTOR)); // init role, assign policy, and assign permission to setRoleHolder to the token
      // voting action creator
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
    uint8 actionCreatorRole = 2;
    POLICY.setRoleHolder(actionCreatorRole, coreTeam1, DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION);
    POLICY.setRolePermission(
      actionCreatorRole,
      ILlamaPolicy.PermissionData(address(POLICY), POLICY.setRoleHolder.selector, address(STRATEGY)),
      true
    );
    vm.stopPrank();

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    data = abi.encodeCall(
      POLICY.setRoleHolder, (actionCreatorRole, address(0xdeadbeef), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION)
    );

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(actionCount, address(tokenHolder1), actionCreatorRole, STRATEGY, address(POLICY), 0, data, "");

    vm.prank(tokenHolder1);

    uint256 actionId = actionCreator.createAction(actionCreatorRole, STRATEGY, address(POLICY), 0, data, "");

    Action memory action = CORE.getAction(actionId);

    assertEq(actionId, actionCount);
    assertEq(action.creationTime, block.timestamp);
  }
}

contract CancelAction is ERC20TokenholderActionCreatorTest {
  uint8 actionCreatorRole = 2;
  bytes data = abi.encodeCall(
    POLICY.setRoleHolder, (actionCreatorRole, address(0xdeadbeef), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION)
  );
  uint256 threshold = 500_000e18;
  uint256 actionId;
  ERC20TokenholderActionCreator actionCreator;
  ActionInfo actionInfo;

  function setUp() public virtual override {
    ERC20TokenholderActionCreatorTest.setUp();
    mockErc20Votes.mint(tokenHolder1, threshold); // we use mockErc20Votes because IVotesToken is an
    // interface without the `delegate` function
    vm.prank(tokenHolder1);
    mockErc20Votes.delegate(tokenHolder1); // we use mockErc20Votes because IVotesToken is an interface without
    // the `delegate` function

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    actionCreator = new ERC20TokenholderActionCreator(token, CORE, threshold);

    vm.startPrank(address(EXECUTOR)); // init role, assign policy, and assign permission to setRoleHolder to the token
      // voting action creator
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
    POLICY.setRoleHolder(actionCreatorRole, coreTeam1, DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION);
    POLICY.setRolePermission(
      actionCreatorRole,
      ILlamaPolicy.PermissionData(address(POLICY), POLICY.setRoleHolder.selector, address(STRATEGY)),
      true
    );
    vm.stopPrank();

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    vm.prank(tokenHolder1);
    actionId = actionCreator.createAction(actionCreatorRole, STRATEGY, address(POLICY), 0, data, "");

    actionInfo = ActionInfo(actionId, coreTeam1, actionCreatorRole, STRATEGY, address(POLICY), 0, data);
  }

  function test_PassesIf_CallerIsActionCreator() public {
    vm.expectEmit();
    emit ActionCanceled(actionId, tokenHolder1);
    vm.prank(tokenHolder1);
    actionCreator.cancelAction(actionInfo);
  }

  function test_RevertsIf_CallerIsNotActionCreator(address notCreator) public {
    vm.assume(notCreator != tokenHolder1);
    vm.expectRevert(TokenholderActionCreator.OnlyActionCreator.selector);
    vm.prank(notCreator);
    actionCreator.cancelAction(actionInfo);
  }
}

contract SetActionThreshold is ERC20TokenholderActionCreatorTest {
  function test_SetsCreationThreshold() public {
    uint256 threshold = 500_000e18;
    mockErc20Votes.mint(address(this), 1_000_000e18); // we use mockErc20Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC20TokenholderActionCreator actionCreator = new ERC20TokenholderActionCreator(token, CORE, 1_000_000e18);

    assertEq(actionCreator.creationThreshold(), 1_000_000e18);

    vm.expectEmit();
    emit ActionThresholdSet(threshold);
    vm.prank(address(EXECUTOR));
    actionCreator.setActionThreshold(threshold);
  }

  function test_RevertsIf_CreationThresholdExceedsTotalSupply() public {
    uint256 threshold = 1_000_000e18;
    mockErc20Votes.mint(address(this), 500_000e18); // we use mockErc20Votes because IVotesToken is an interface
    // without the `mint` function

    ERC20TokenholderActionCreator actionCreator = new ERC20TokenholderActionCreator(token, CORE, 500_000e18);

    vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
    vm.prank(address(EXECUTOR));
    actionCreator.setActionThreshold(threshold);
  }

  function test_RevertsIf_CalledByNotLlamaExecutor(address notLlamaExecutor) public {
    vm.assume(notLlamaExecutor != address(EXECUTOR));
    uint256 threshold = 500_000e18;
    mockErc20Votes.mint(address(this), 1_000_000e18); // we use mockErc20Votes because IVotesToken is an interface
    // without the `mint` function

    ERC20TokenholderActionCreator actionCreator = new ERC20TokenholderActionCreator(token, CORE, 1_000_000e18);

    vm.expectRevert(TokenholderActionCreator.OnlyLlamaExecutor.selector);
    vm.prank(notLlamaExecutor);
    actionCreator.setActionThreshold(threshold);
  }
}

contract CreateActionBySig is ERC20TokenholderActionCreatorTest, LlamaCoreSigUtils {
  ERC20TokenholderActionCreator actionCreator;
  uint8 actionCreatorRole;

  function setUp() public virtual override {
    ERC20TokenholderActionCreatorTest.setUp();
    mockErc20Votes.mint(tokenHolder, 1000); // we use mockErc20Votes because IVotesToken is an
      // interface without the `delegate` function
    vm.prank(tokenHolder);
    mockErc20Votes.delegate(tokenHolder); // we use mockErc20Votes because IVotesToken is an interface without
      // the `delegate` function

    actionCreator = new ERC20TokenholderActionCreator(token, CORE, 1000);

    // Setting Mock Protocol Core's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(actionCreator)
      })
    );

    vm.startPrank(address(EXECUTOR)); // init role, assign policy, and assign permission to setRoleHolder to the token
      // voting action creator
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
    actionCreatorRole = 2;
    POLICY.setRoleHolder(actionCreatorRole, address(actionCreator), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION);
    POLICY.setRolePermission(
      actionCreatorRole,
      ILlamaPolicy.PermissionData(address(POLICY), POLICY.initializeRole.selector, address(STRATEGY)),
      true
    );
    vm.stopPrank();

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);
  }

  function createOffchainSignature(uint256 privateKey) internal view returns (uint8 v, bytes32 r, bytes32 s) {
    (v, r, s) = createOffchainSignatureWithDescription(privateKey, "");
  }

  function createOffchainSignatureWithDescription(uint256 privateKey, string memory description)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CreateActionBySig memory _createAction = LlamaCoreSigUtils.CreateActionBySig({
      role: actionCreatorRole,
      strategy: address(STRATEGY),
      target: address(POLICY),
      value: 0,
      data: abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role"))),
      description: description,
      tokenHolder: tokenHolder,
      nonce: 0
    });
    bytes32 digest = getCreateActionBySigTypedDataHash(_createAction);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function createActionBySig(uint8 v, bytes32 r, bytes32 s) internal returns (uint256 actionId) {
    actionId = actionCreator.createActionBySig(
      tokenHolder,
      actionCreatorRole,
      STRATEGY,
      address(POLICY),
      0,
      abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role"))),
      "",
      v,
      r,
      s
    );
  }

  function test_CreatesActionBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolderPrivateKey);
    bytes memory data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role")));

    // vm.expectEmit();
    // emit ActionCreated(0, tokenHolder, CORE_TEAM_ROLE, STRATEGY, address(POLICY), 0, data, "");

    uint256 actionId = createActionBySig(v, r, s);
    Action memory action = CORE.getAction(actionId);

    // assertEq(actionId, 0);
    // assertEq(CORE.actionsCount(), 1);
    assertEq(action.creationTime, block.timestamp);
  }

  // function test_CreatesActionBySigWithDescription() public {
  //   (uint8 v, bytes32 r, bytes32 s) =
  //     createOffchainSignatureWithDescription(tokenHolderPrivateKey, "# Action 0 \n This is my action.");
  //   bytes memory data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role")));

  //   vm.expectEmit();
  //   emit ActionCreated(
  //     0, tokenHolder, CORE_TEAM_ROLE, STRATEGY, address(POLICY), 0, data, "# Action 0 \n This is my action."
  //   );

  //   uint256 actionId = actionCreator.createActionBySig(
  //     coreTeam1,
  //     CORE_TEAM_ROLE,
  //     STRATEGY,
  //     address(POLICY),
  //     0,
  //     abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role"))),
  //     "# Action 0 \n This is my action.",
  //     v,
  //     r,
  //     s
  //   );
  //   Action memory action = CORE.getAction(actionId);

  //   // assertEq(actionId, 0);
  //   // assertEq(CORE.actionsCount(), 1);
  //   assertEq(action.creationTime, block.timestamp);
  // }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolderPrivateKey);
    assertEq(actionCreator.nonces(coreTeam1, ILlamaCore.createActionBySig.selector), 0);
    createActionBySig(v, r, s);
    assertEq(actionCreator.nonces(coreTeam1, ILlamaCore.createActionBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolderPrivateKey);
    createActionBySig(v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // policyholder since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }

  function test_RevertIf_SignerIsNotPolicyHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the policyholder passed in as
    // parameter.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolderPrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    createActionBySig((v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolderPrivateKey);

    vm.prank(coreTeam1);
    actionCreator.incrementNonce(ILlamaCore.createActionBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }
}

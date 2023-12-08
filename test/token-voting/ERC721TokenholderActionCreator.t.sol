// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {ERC721Votes} from "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {MockERC721Votes} from "test/mock/MockERC721Votes.sol";
import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";
import {LlamaCoreSigUtils} from "test/utils/LlamaCoreSigUtils.sol";

import {ActionState} from "src/lib/Enums.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {TokenholderActionCreator} from "src/token-voting/TokenholderActionCreator.sol";

contract ERC721TokenholderActionCreatorTest is LlamaTokenVotingTestSetup {
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

  MockERC721Votes mockErc721Votes;
  ERC721Votes token;
  address tokenHolder1 = makeAddr("tokenHolder1");
  address tokenHolder2 = makeAddr("tokenHolder2");
  address tokenHolder3 = makeAddr("tokenHolder3");
  address notATokenHolder = makeAddr("notATokenHolder");

  function setUp() public virtual override {
    LlamaTokenVotingTestSetup.setUp();
    vm.deal(address(this), 1 ether);
    vm.deal(address(msg.sender), 1 ether);

    mockErc721Votes = new MockERC721Votes();
    token = ERC721Votes(address(mockErc721Votes));
  }
}

contract Constructor is ERC721TokenholderActionCreatorTest {
  function test_RevertsIf_InvalidLlamaCore() public {
    // With invalid LlamaCore instance, TokenholderActionCreator.InvalidLlamaCoreAddress is unreachable
    vm.expectRevert();
    new ERC721TokenholderActionCreator(token, ILlamaCore(makeAddr("invalid-llama-core")), uint256(0));
  }

  function test_RevertsIf_InvalidTokenAddress() public {
    vm.expectRevert(); // will EvmError: Revert vecause totalSupply fn does not exist
    new ERC721TokenholderActionCreator(ERC721Votes(makeAddr("invalid-token")), ILlamaCore(address(CORE)), uint256(0));
  }

  function test_RevertsIf_CreationThresholdExceedsTotalSupply(uint8 num) public {
    vm.assume(num > 1);
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
    new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), num);
  }

  function test_ProperlySetsConstructorArguments() public {
    uint256 threshold = 1;
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC721TokenholderActionCreator actionCreator =
      new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), threshold);
    assertEq(address(actionCreator.TOKEN()), address(token));
    assertEq(address(actionCreator.LLAMA_CORE()), address(CORE));
    assertEq(actionCreator.creationThreshold(), threshold);
  }
}

contract TokenHolderCreateAction is ERC721TokenholderActionCreatorTest {
  bytes data = abi.encodeCall(
    POLICY.setRoleHolder, (CORE_TEAM_ROLE, address(0xdeadbeef), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION)
  );
  uint256 threshold = 1;

  function test_RevertsIf_InsufficientBalance() public {
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC721TokenholderActionCreator actionCreator =
      new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), threshold);

    vm.prank(notATokenHolder);
    vm.expectRevert(abi.encodeWithSelector(TokenholderActionCreator.InsufficientBalance.selector, 0));
    actionCreator.createAction(CORE_TEAM_ROLE, STRATEGY, address(POLICY), 0, data, "");
  }

  function test_RevertsIf_TokenholderActionCreatorDoesNotHavePermission() public {
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an
    // interface without the `mint` function
    vm.prank(tokenHolder1);
    mockErc721Votes.delegate(tokenHolder1); // we use mockErc721Votes because IVotesToken is an interface without
    // the `delegate` function

    vm.warp(block.timestamp + 1);

    ERC721TokenholderActionCreator actionCreator =
      new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), threshold);
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    token.getPastVotes(tokenHolder1, block.timestamp - 1);

    vm.expectRevert(ILlamaCore.PolicyholderDoesNotHavePermission.selector);
    vm.prank(tokenHolder1);
    actionCreator.createAction(CORE_TEAM_ROLE, STRATEGY, address(POLICY), 0, data, "");
  }

  function test_ProperlyCreatesAction() public {
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an
    // interface without the `delegate` function
    vm.prank(tokenHolder1);
    mockErc721Votes.delegate(tokenHolder1); // we use mockErc721Votes because IVotesToken is an interface without
    // the `delegate` function

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    ERC721TokenholderActionCreator actionCreator =
      new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), threshold);

    vm.startPrank(address(EXECUTOR)); // init role, assign policy, and assign permission to setRoleHolder to the token
      // voting action creator
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
    uint8 actionCreatorRole = 2;
    POLICY.setRoleHolder(actionCreatorRole, address(actionCreator), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION);
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

contract CancelAction is ERC721TokenholderActionCreatorTest {
  uint8 actionCreatorRole = 2;
  bytes data = abi.encodeCall(
    POLICY.setRoleHolder, (actionCreatorRole, address(0xdeadbeef), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION)
  );
  uint256 threshold = 1;
  uint256 actionId;
  ERC721TokenholderActionCreator actionCreator;
  ActionInfo actionInfo;

  function setUp() public virtual override {
    ERC721TokenholderActionCreatorTest.setUp();
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an
    // interface without the `delegate` function
    vm.prank(tokenHolder1);
    mockErc721Votes.delegate(tokenHolder1); // we use mockErc721Votes because IVotesToken is an interface without
    // the `delegate` function

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    actionCreator = new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), threshold);

    vm.startPrank(address(EXECUTOR)); // init role, assign policy, and assign permission to setRoleHolder to the token
      // voting action creator
    POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
    POLICY.setRoleHolder(actionCreatorRole, address(actionCreator), DEFAULT_ROLE_QTY, DEFAULT_ROLE_EXPIRATION);
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

    actionInfo = ActionInfo(actionId, address(actionCreator), actionCreatorRole, STRATEGY, address(POLICY), 0, data);
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

contract SetActionThreshold is ERC721TokenholderActionCreatorTest {
  function test_SetsCreationThreshold() public {
    uint256 threshold = 1;
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC721TokenholderActionCreator actionCreator =
      new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), threshold);

    assertEq(actionCreator.creationThreshold(), threshold);

    vm.expectEmit();
    emit ActionThresholdSet(threshold);
    vm.prank(address(EXECUTOR));
    actionCreator.setActionThreshold(threshold);
  }

  function test_RevertsIf_CreationThresholdExceedsTotalSupply(uint8 num) public {
    vm.assume(num > 1);
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC721TokenholderActionCreator actionCreator =
      new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), 1);

    vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
    vm.prank(address(EXECUTOR));
    actionCreator.setActionThreshold(num);
  }

  function test_RevertsIf_CalledByNotLlamaExecutor(address notLlamaExecutor) public {
    vm.assume(notLlamaExecutor != address(EXECUTOR));
    uint256 threshold = 1;
    mockErc721Votes.mint(tokenHolder1, 0); // we use mockErc721Votes because IVotesToken is an interface
    // without the `mint` function

    vm.warp(block.timestamp + 1);

    ERC721TokenholderActionCreator actionCreator =
      new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), threshold);

    vm.expectRevert(TokenholderActionCreator.OnlyLlamaExecutor.selector);
    vm.prank(notLlamaExecutor);
    actionCreator.setActionThreshold(threshold);
  }
}

contract CreateActionBySig is ERC721TokenholderActionCreatorTest, LlamaCoreSigUtils {
  ERC721TokenholderActionCreator actionCreator;
  uint8 actionCreatorRole;

  function setUp() public virtual override {
    ERC721TokenholderActionCreatorTest.setUp();
    mockErc721Votes.mint(tokenHolder, 0); // we use mockErc721Votes because IVotesToken is an
      // interface without the `delegate` function
    vm.prank(tokenHolder);
    mockErc721Votes.delegate(tokenHolder); // we use mockErc721Votes because IVotesToken is an interface without
      // the `delegate` function

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    actionCreator = new ERC721TokenholderActionCreator(token, CORE, 1);

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

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(actionCount, tokenHolder, actionCreatorRole, STRATEGY, address(POLICY), 0, data, "");

    uint256 actionId = createActionBySig(v, r, s);
    Action memory action = CORE.getAction(actionId);

    assertEq(actionId, actionCount);
    assertEq(CORE.actionsCount() - 1, actionCount);
    assertEq(action.creationTime, block.timestamp);
  }

  function test_CreatesActionBySigWithDescription() public {
    (uint8 v, bytes32 r, bytes32 s) =
      createOffchainSignatureWithDescription(tokenHolderPrivateKey, "# Action 0 \n This is my action.");
    bytes memory data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role")));

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(
      actionCount,
      tokenHolder,
      actionCreatorRole,
      STRATEGY,
      address(POLICY),
      0,
      data,
      "# Action 0 \n This is my action."
    );

    uint256 actionId = actionCreator.createActionBySig(
      tokenHolder,
      actionCreatorRole,
      STRATEGY,
      address(POLICY),
      0,
      abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role"))),
      "# Action 0 \n This is my action.",
      v,
      r,
      s
    );
    Action memory action = CORE.getAction(actionId);

    assertEq(actionId, actionCount);
    assertEq(CORE.actionsCount() - 1, actionCount);
    assertEq(action.creationTime, block.timestamp);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolderPrivateKey);
    assertEq(actionCreator.nonces(tokenHolder, ILlamaCore.createActionBySig.selector), 0);
    createActionBySig(v, r, s);
    assertEq(actionCreator.nonces(tokenHolder, ILlamaCore.createActionBySig.selector), 1);
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

    vm.prank(tokenHolder);
    actionCreator.incrementNonce(ILlamaCore.createActionBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }
}

contract CancelActionBySig is ERC721TokenholderActionCreatorTest, LlamaCoreSigUtils {
  bytes data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role")));
  uint256 actionId;
  ERC721TokenholderActionCreator actionCreator;
  ActionInfo actionInfo;
  uint8 actionCreatorRole;

  function setUp() public virtual override {
    ERC721TokenholderActionCreatorTest.setUp();
    mockErc721Votes.mint(address(tokenHolder), 0); // we use mockErc721Votes because IVotesToken is an
      // interface without the `delegate` function
    vm.prank(tokenHolder);
    mockErc721Votes.delegate(tokenHolder); // we use mockErc721Votes because IVotesToken is an interface without
      // the `delegate` function

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);

    actionCreator = new ERC721TokenholderActionCreator(token, ILlamaCore(address(CORE)), 1);

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

    vm.expectEmit();
    emit ActionCreated(CORE.actionsCount(), tokenHolder, actionCreatorRole, STRATEGY, address(POLICY), 0, data, "");
    vm.prank(tokenHolder);
    actionId = actionCreator.createAction(actionCreatorRole, STRATEGY, address(POLICY), 0, data, "");

    actionInfo = ActionInfo(actionId, address(actionCreator), actionCreatorRole, STRATEGY, address(POLICY), 0, data);

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CancelActionBySig memory cancelAction = LlamaCoreSigUtils.CancelActionBySig({
      tokenHolder: tokenHolder,
      actionInfo: _actionInfo,
      nonce: actionCreator.nonces(tokenHolder, ILlamaCore.cancelActionBySig.selector)
    });
    bytes32 digest = getCancelActionBySigTypedDataHash(cancelAction);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function cancelActionBySig(ActionInfo memory _actionInfo, uint8 v, bytes32 r, bytes32 s) internal {
    actionCreator.cancelActionBySig(tokenHolder, _actionInfo, v, r, s);
  }

  function test_CancelActionBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);

    // vm.expectEmit();
    // emit ActionCanceled(actionInfo.id, tokenHolder);

    cancelActionBySig(actionInfo, v, r, s);

    uint256 state = uint256(CORE.getActionState(actionInfo));
    uint256 canceled = uint256(ActionState.Canceled);
    assertEq(state, canceled);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);

    assertEq(actionCreator.nonces(tokenHolder, ILlamaCore.cancelActionBySig.selector), 0);
    cancelActionBySig(actionInfo, v, r, s);
    assertEq(actionCreator.nonces(tokenHolder, ILlamaCore.cancelActionBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);
    cancelActionBySig(actionInfo, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    cancelActionBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsNotTokenHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the policyholder passed in as
    // parameter.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    cancelActionBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    cancelActionBySig(actionInfo, (v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);

    vm.prank(tokenHolder);
    actionCreator.incrementNonce(ILlamaCore.cancelActionBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    cancelActionBySig(actionInfo, v, r, s);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";
import {LlamaCoreSigUtils} from "test/utils/LlamaCoreSigUtils.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ActionState} from "src/lib/Enums.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {TokenholderActionCreator} from "src/token-voting/TokenholderActionCreator.sol";

contract ERC721TokenholderActionCreatorTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
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

  ERC721TokenholderActionCreator erc721TokenholderActionCreator;

  function setUp() public virtual override {
    LlamaTokenVotingTestSetup.setUp();

    // Mint tokens to tokenholders so that there is an existing supply.
    erc721VotesToken.mint(tokenHolder0, 0);

    // Mine block so that the ERC20 and ERC721 supply will be available when doing a past timestamp check at initialize
    // during deployment.
    mineBlock();

    // Deploy ERC20 Token Voting Module.
    (erc721TokenholderActionCreator,) = _deployERC721TokenVotingModuleAndSetRole();

    // Setting ERC20TokenHolderActionCreator's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(erc721TokenholderActionCreator)
      })
    );
  }
}

// contract Constructor is ERC721TokenholderActionCreatorTest {
//   function test_RevertsIf_InvalidLlamaCore() public {
//     // With invalid LlamaCore instance, TokenholderActionCreator.InvalidLlamaCoreAddress is unreachable
//     vm.expectRevert();
//     new ERC721TokenholderActionCreator(erc721VotesToken, ILlamaCore(makeAddr("invalid-llama-core")), uint256(0));
//   }

//   function test_RevertsIf_InvalidTokenAddress() public {
//     vm.expectRevert(); // will EvmError: Revert vecause totalSupply fn does not exist
//     new ERC721TokenholderActionCreator(ERC20Votes(makeAddr("invalid-erc721VotesToken")), CORE, uint256(0));
//   }

//   function test_RevertsIf_CreationThresholdExceedsTotalSupply() public {
//     erc721VotesToken.mint(tokenHolder1, 1_000_000e18); // we use erc721VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     vm.warp(block.timestamp + 1);

//     vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
//     new ERC721TokenholderActionCreator(erc721VotesToken, CORE, 17_000_000_000_000_000_000_000_000);
//   }

//   function test_ProperlySetsConstructorArguments() public {
//     uint256 threshold = 500_000e18;
//     erc721VotesToken.mint(tokenHolder1, 1_000_000e18); // we use erc721VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     vm.warp(block.timestamp + 1);

//     ERC721TokenholderActionCreator erc721TokenholderActionCreator = new
// ERC721TokenholderActionCreator(erc721VotesToken,
// CORE,
// threshold);
//     assertEq(address(erc721TokenholderActionCreator.TOKEN()), address(erc721VotesToken));
//     assertEq(address(erc721TokenholderActionCreator.LLAMA_CORE()), address(CORE));
//     assertEq(erc721TokenholderActionCreator.creationThreshold(), threshold);
//   }
// }

contract CreateAction is ERC721TokenholderActionCreatorTest {
  bytes data = abi.encodeCall(mockProtocol.pause, (true));

  function test_RevertsIf_InsufficientBalance() public {
    erc721VotesToken.mint(tokenHolder1, ERC721_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc721VotesToken.delegate(tokenHolder1);

    mineBlock();

    vm.expectRevert(abi.encodeWithSelector(TokenholderActionCreator.InsufficientBalance.selector, 0));
    vm.prank(notTokenHolder);
    erc721TokenholderActionCreator.createAction(STRATEGY, address(mockProtocol), 0, data, "");
  }

  function test_RevertsIf_TokenholderActionCreatorDoesNotHavePermission() public {
    erc721VotesToken.mint(tokenHolder1, ERC721_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc721VotesToken.delegate(tokenHolder1);

    mineBlock();

    vm.expectRevert(ILlamaCore.PolicyholderDoesNotHavePermission.selector);
    vm.prank(tokenHolder1);
    erc721TokenholderActionCreator.createAction(STRATEGY, address(mockProtocol), 0, data, "");
  }

  function test_ProperlyCreatesAction() public {
    // Assigns Permission to TokenholderActionCreator.
    _setRolePermissionToTokenholderActionCreator();

    // Mint tokens to tokenholder so that they can create action.
    erc721VotesToken.mint(tokenHolder1, ERC721_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc721VotesToken.delegate(tokenHolder1);

    // Mine block so that the ERC20 supply will be available when doing a past timestamp check at createAction.
    mineBlock();

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(
      actionCount, address(tokenHolder1), tokenVotingActionCreatorRole, STRATEGY, address(mockProtocol), 0, data, ""
    );
    vm.prank(tokenHolder1);
    uint256 actionId = erc721TokenholderActionCreator.createAction(STRATEGY, address(mockProtocol), 0, data, "");

    Action memory action = CORE.getAction(actionId);
    assertEq(actionId, actionCount);
    assertEq(action.creationTime, block.timestamp);
  }
}

contract CreateActionBySig is ERC721TokenholderActionCreatorTest {
  function setUp() public virtual override {
    ERC721TokenholderActionCreatorTest.setUp();

    // Assigns Permission to TokenholderActionCreator.
    _setRolePermissionToTokenholderActionCreator();

    // Mint tokens to tokenholder so that they can create action.
    erc721VotesToken.mint(tokenHolder1, ERC721_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc721VotesToken.delegate(tokenHolder1);

    // Mine block so that the ERC20 supply will be available when doing a past timestamp check at createAction.
    mineBlock();
  }

  function createOffchainSignature(uint256 privateKey) internal view returns (uint8 v, bytes32 r, bytes32 s) {
    (v, r, s) = createOffchainSignatureWithDescription(privateKey, "");
  }

  function createOffchainSignatureWithDescription(uint256 privateKey, string memory description)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CreateAction memory _createAction = LlamaCoreSigUtils.CreateAction({
      tokenHolder: tokenHolder1,
      strategy: address(STRATEGY),
      target: address(mockProtocol),
      value: 0,
      data: abi.encodeCall(mockProtocol.pause, (true)),
      description: description,
      nonce: 0
    });
    bytes32 digest = getCreateActionTypedDataHash(_createAction);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function createActionBySig(uint8 v, bytes32 r, bytes32 s) internal returns (uint256 actionId) {
    actionId = erc721TokenholderActionCreator.createActionBySig(
      tokenHolder1, STRATEGY, address(mockProtocol), 0, abi.encodeCall(mockProtocol.pause, (true)), "", v, r, s
    );
  }

  function test_CreatesActionBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
    bytes memory data = abi.encodeCall(mockProtocol.pause, (true));

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(
      actionCount, tokenHolder1, tokenVotingActionCreatorRole, STRATEGY, address(mockProtocol), 0, data, ""
    );

    uint256 actionId = createActionBySig(v, r, s);
    Action memory action = CORE.getAction(actionId);

    assertEq(actionId, actionCount);
    assertEq(CORE.actionsCount() - 1, actionCount);
    assertEq(action.creationTime, block.timestamp);
  }

  function test_CreatesActionBySigWithDescription() public {
    (uint8 v, bytes32 r, bytes32 s) =
      createOffchainSignatureWithDescription(tokenHolder1PrivateKey, "# Action 0 \n This is my action.");
    bytes memory data = abi.encodeCall(mockProtocol.pause, (true));

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(
      actionCount,
      tokenHolder1,
      tokenVotingActionCreatorRole,
      STRATEGY,
      address(mockProtocol),
      0,
      data,
      "# Action 0 \n This is my action."
    );

    uint256 actionId = erc721TokenholderActionCreator.createActionBySig(
      tokenHolder1,
      STRATEGY,
      address(mockProtocol),
      0,
      abi.encodeCall(mockProtocol.pause, (true)),
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
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
    assertEq(
      erc721TokenholderActionCreator.nonces(tokenHolder1, TokenholderActionCreator.createActionBySig.selector), 0
    );
    createActionBySig(v, r, s);
    assertEq(
      erc721TokenholderActionCreator.nonces(tokenHolder1, TokenholderActionCreator.createActionBySig.selector), 1
    );
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
    createActionBySig(v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as
    // policyholder since nonce has increased.
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }

  function test_RevertIf_SignerIsNotPolicyHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the policyholder passed in as
    // parameter.
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    createActionBySig((v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    erc721TokenholderActionCreator.incrementNonce(TokenholderActionCreator.createActionBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }
}

contract CancelAction is ERC721TokenholderActionCreatorTest {
  uint256 actionId;
  ActionInfo actionInfo;

  function setUp() public virtual override {
    ERC721TokenholderActionCreatorTest.setUp();

    // Assigns Permission to TokenholderActionCreator.
    _setRolePermissionToTokenholderActionCreator();

    // Mint tokens to tokenholder so that they can create action.
    erc721VotesToken.mint(tokenHolder1, ERC721_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc721VotesToken.delegate(tokenHolder1);

    // Mine block so that the ERC20 supply will be available when doing a past timestamp check at createAction.
    mineBlock();

    bytes memory data = abi.encodeCall(mockProtocol.pause, (true));

    vm.prank(tokenHolder1);
    actionId = erc721TokenholderActionCreator.createAction(STRATEGY, address(mockProtocol), 0, data, "");

    actionInfo = ActionInfo(
      actionId,
      address(erc721TokenholderActionCreator),
      tokenVotingActionCreatorRole,
      STRATEGY,
      address(mockProtocol),
      0,
      data
    );
  }

  function test_PassesIf_CallerIsActionCreator() public {
    vm.expectEmit();
    emit ActionCanceled(actionId, tokenHolder1);
    vm.prank(tokenHolder1);
    erc721TokenholderActionCreator.cancelAction(actionInfo);
  }

  function test_RevertsIf_CallerIsNotActionCreator(address notCreator) public {
    vm.assume(notCreator != tokenHolder1);
    vm.expectRevert(TokenholderActionCreator.OnlyActionCreator.selector);
    vm.prank(notCreator);
    erc721TokenholderActionCreator.cancelAction(actionInfo);
  }
}

contract CancelActionBySig is ERC721TokenholderActionCreatorTest {
  uint256 actionId;
  ActionInfo actionInfo;

  function setUp() public virtual override {
    ERC721TokenholderActionCreatorTest.setUp();

    // Assigns Permission to TokenholderActionCreator.
    _setRolePermissionToTokenholderActionCreator();

    // Mint tokens to tokenholder so that they can create action.
    erc721VotesToken.mint(tokenHolder1, ERC721_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc721VotesToken.delegate(tokenHolder1);

    // Mine block so that the ERC20 supply will be available when doing a past timestamp check at createAction.
    mineBlock();

    bytes memory data = abi.encodeCall(mockProtocol.pause, (true));

    vm.prank(tokenHolder1);
    actionId = erc721TokenholderActionCreator.createAction(STRATEGY, address(mockProtocol), 0, data, "");

    actionInfo = ActionInfo(
      actionId,
      address(erc721TokenholderActionCreator),
      tokenVotingActionCreatorRole,
      STRATEGY,
      address(mockProtocol),
      0,
      data
    );
  }

  function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    LlamaCoreSigUtils.CancelAction memory cancelAction = LlamaCoreSigUtils.CancelAction({
      tokenHolder: tokenHolder1,
      actionInfo: _actionInfo,
      nonce: erc721TokenholderActionCreator.nonces(tokenHolder1, TokenholderActionCreator.cancelActionBySig.selector)
    });
    bytes32 digest = getCancelActionTypedDataHash(cancelAction);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function cancelActionBySig(ActionInfo memory _actionInfo, uint8 v, bytes32 r, bytes32 s) internal {
    erc721TokenholderActionCreator.cancelActionBySig(tokenHolder1, _actionInfo, v, r, s);
  }

  function test_CancelActionBySig() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.expectEmit();
    emit ActionCanceled(actionId, tokenHolder1);
    cancelActionBySig(actionInfo, v, r, s);

    uint256 state = uint256(CORE.getActionState(actionInfo));
    uint256 canceled = uint256(ActionState.Canceled);
    assertEq(state, canceled);
  }

  function test_CheckNonceIncrements() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    assertEq(
      erc721TokenholderActionCreator.nonces(tokenHolder1, TokenholderActionCreator.cancelActionBySig.selector), 0
    );
    cancelActionBySig(actionInfo, v, r, s);
    assertEq(
      erc721TokenholderActionCreator.nonces(tokenHolder1, TokenholderActionCreator.cancelActionBySig.selector), 1
    );
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    cancelActionBySig(actionInfo, v, r, s);
    // Invalid Signature error since the recovered signer address during the second call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    cancelActionBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsNotTokenHolder() public {
    (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
    // Invalid Signature error since the recovered signer address is not the same as the policyholder passed in as
    // parameter.
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    cancelActionBySig(actionInfo, v, r, s);
  }

  function test_RevertIf_SignerIsZeroAddress() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    cancelActionBySig(actionInfo, (v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    erc721TokenholderActionCreator.incrementNonce(TokenholderActionCreator.cancelActionBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(TokenholderActionCreator.InvalidSignature.selector);
    cancelActionBySig(actionInfo, v, r, s);
  }
}

contract SetActionThreshold is ERC721TokenholderActionCreatorTest {
  function testFuzz_SetsCreationThreshold(uint256 threshold) public {
    threshold = bound(threshold, 0, erc721VotesToken.getPastTotalSupply(block.timestamp - 1));

    assertEq(erc721TokenholderActionCreator.creationThreshold(), ERC721_CREATION_THRESHOLD);

    vm.expectEmit();
    emit ActionThresholdSet(threshold);
    vm.prank(address(EXECUTOR));
    erc721TokenholderActionCreator.setActionThreshold(threshold);

    assertEq(erc721TokenholderActionCreator.creationThreshold(), threshold);
  }

  function testFuzz_RevertsIf_CreationThresholdExceedsTotalSupply(uint256 threshold) public {
    vm.assume(threshold > erc721VotesToken.getPastTotalSupply(block.timestamp - 1));

    vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
    vm.prank(address(EXECUTOR));
    erc721TokenholderActionCreator.setActionThreshold(threshold);
  }

  function testFuzz_RevertsIf_CalledByNotLlamaExecutor(address notLlamaExecutor) public {
    vm.assume(notLlamaExecutor != address(EXECUTOR));

    vm.expectRevert(TokenholderActionCreator.OnlyLlamaExecutor.selector);
    vm.prank(notLlamaExecutor);
    erc721TokenholderActionCreator.setActionThreshold(ERC721_CREATION_THRESHOLD);
  }
}

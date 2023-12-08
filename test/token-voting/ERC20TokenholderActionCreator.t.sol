// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";
import {LlamaCoreSigUtils} from "test/utils/LlamaCoreSigUtils.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ActionState} from "src/lib/Enums.sol";
import {Action, ActionInfo} from "src/lib/Structs.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {TokenholderActionCreator} from "src/token-voting/TokenholderActionCreator.sol";

contract ERC20TokenholderActionCreatorTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
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

  ERC20TokenholderActionCreator erc20TokenholderActionCreator;
  uint8 erc20TokenholderActionCreatorRole;

  function setUp() public virtual override {
    LlamaTokenVotingTestSetup.setUp();
    vm.deal(address(this), 1 ether);
    vm.deal(address(msg.sender), 1 ether);

    // Mint tokens to tokenholders so that there is an existing supply.
    erc20VotesToken.mint(tokenHolder0, ERC20_CREATION_THRESHOLD);
    erc721VotesToken.mint(tokenHolder0, 0);

    // Mine block so that the ERC20 and ERC721 supply will be available when doing a past timestamp check at initialize
    // during deployment.
    mineBlock();

    // Deploy ERC20 Token Voting Module.
    (erc20TokenholderActionCreator,) = _deployERC20TokenVotingModule();

    // Setting ERC20TokenHolderActionCreator's EIP-712 Domain Hash
    setDomainHash(
      LlamaCoreSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(erc20TokenholderActionCreator)
      })
    );
  }

  function _initRoleSetRoleHolderSetRolePermissionToTokenholderActionCreator() internal {
    // Init role, assign policy, and assign permission for `setRoleHolder` to the TokenholderActionCreator.
    vm.startPrank(address(EXECUTOR));
    POLICY.initializeRole(TOKEN_VOTING_ACTION_CREATOR_ROLE_DESC);
    erc20TokenholderActionCreatorRole = POLICY.numRoles();
    POLICY.setRoleHolder(
      erc20TokenholderActionCreatorRole,
      address(erc20TokenholderActionCreator),
      DEFAULT_ROLE_QTY,
      DEFAULT_ROLE_EXPIRATION
    );
    POLICY.setRolePermission(
      erc20TokenholderActionCreatorRole,
      ILlamaPolicy.PermissionData(address(mockProtocol), PAUSE_SELECTOR, address(STRATEGY)),
      true
    );
    vm.stopPrank();
  }
}

// contract Constructor is ERC20TokenholderActionCreatorTest {
//   function test_RevertsIf_InvalidLlamaCore() public {
//     // With invalid LlamaCore instance, TokenholderActionCreator.InvalidLlamaCoreAddress is unreachable
//     vm.expectRevert();
//     new ERC20TokenholderActionCreator(erc20VotesToken, ILlamaCore(makeAddr("invalid-llama-core")), uint256(0));
//   }

//   function test_RevertsIf_InvalidTokenAddress() public {
//     vm.expectRevert(); // will EvmError: Revert vecause totalSupply fn does not exist
//     new ERC20TokenholderActionCreator(ERC20Votes(makeAddr("invalid-erc20VotesToken")), CORE, uint256(0));
//   }

//   function test_RevertsIf_CreationThresholdExceedsTotalSupply() public {
//     erc20VotesToken.mint(tokenHolder1, 1_000_000e18); // we use erc20VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     vm.warp(block.timestamp + 1);

//     vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
//     new ERC20TokenholderActionCreator(erc20VotesToken, CORE, 17_000_000_000_000_000_000_000_000);
//   }

//   function test_ProperlySetsConstructorArguments() public {
//     uint256 threshold = 500_000e18;
//     erc20VotesToken.mint(tokenHolder1, 1_000_000e18); // we use erc20VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     vm.warp(block.timestamp + 1);

//     ERC20TokenholderActionCreator erc20TokenholderActionCreator = new ERC20TokenholderActionCreator(erc20VotesToken,
// CORE,
// threshold);
//     assertEq(address(erc20TokenholderActionCreator.TOKEN()), address(erc20VotesToken));
//     assertEq(address(erc20TokenholderActionCreator.LLAMA_CORE()), address(CORE));
//     assertEq(erc20TokenholderActionCreator.creationThreshold(), threshold);
//   }
// }

contract CreateAction is ERC20TokenholderActionCreatorTest {
  bytes data = abi.encodeCall(mockProtocol.pause, (true));

  function test_RevertsIf_InsufficientBalance() public {
    erc20VotesToken.mint(tokenHolder1, ERC20_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc20VotesToken.delegate(tokenHolder1);

    mineBlock();

    vm.expectRevert(abi.encodeWithSelector(TokenholderActionCreator.InsufficientBalance.selector, 0));
    vm.prank(notTokenHolder);
    erc20TokenholderActionCreator.createAction(
      erc20TokenholderActionCreatorRole, STRATEGY, address(mockProtocol), 0, data, ""
    );
  }

  function test_RevertsIf_TokenholderActionCreatorDoesNotHavePermission() public {
    erc20VotesToken.mint(tokenHolder1, ERC20_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc20VotesToken.delegate(tokenHolder1);

    mineBlock();

    vm.expectRevert(ILlamaCore.PolicyholderDoesNotHavePermission.selector);
    vm.prank(tokenHolder1);
    erc20TokenholderActionCreator.createAction(
      erc20TokenholderActionCreatorRole, STRATEGY, address(mockProtocol), 0, data, ""
    );
  }

  function test_ProperlyCreatesAction() public {
    // Assigns Policy to TokenholderActionCreator.
    _initRoleSetRoleHolderSetRolePermissionToTokenholderActionCreator();

    // Mint tokens to tokenholder so that they can create action.
    erc20VotesToken.mint(tokenHolder1, ERC20_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc20VotesToken.delegate(tokenHolder1);

    // Mine block so that the ERC20 supply will be available when doing a past timestamp check at createAction.
    mineBlock();

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(
      actionCount,
      address(tokenHolder1),
      erc20TokenholderActionCreatorRole,
      STRATEGY,
      address(mockProtocol),
      0,
      data,
      ""
    );
    vm.prank(tokenHolder1);
    uint256 actionId = erc20TokenholderActionCreator.createAction(
      erc20TokenholderActionCreatorRole, STRATEGY, address(mockProtocol), 0, data, ""
    );

    Action memory action = CORE.getAction(actionId);
    assertEq(actionId, actionCount);
    assertEq(action.creationTime, block.timestamp);
  }
}

contract CreateActionBySig is ERC20TokenholderActionCreatorTest {
  function setUp() public virtual override {
    ERC20TokenholderActionCreatorTest.setUp();

    // Assigns Policy to TokenholderActionCreator.
    _initRoleSetRoleHolderSetRolePermissionToTokenholderActionCreator();

    // Mint tokens to tokenholder so that they can create action.
    erc20VotesToken.mint(tokenHolder1, ERC20_CREATION_THRESHOLD);
    vm.prank(tokenHolder1);
    erc20VotesToken.delegate(tokenHolder1);

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
    LlamaCoreSigUtils.CreateActionBySig memory _createAction = LlamaCoreSigUtils.CreateActionBySig({
      role: erc20TokenholderActionCreatorRole,
      strategy: address(STRATEGY),
      target: address(POLICY),
      value: 0,
      data: abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role"))),
      description: description,
      tokenHolder: tokenHolder1,
      nonce: 0
    });
    bytes32 digest = getCreateActionBySigTypedDataHash(_createAction);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function createActionBySig(uint8 v, bytes32 r, bytes32 s) internal returns (uint256 actionId) {
    actionId = erc20TokenholderActionCreator.createActionBySig(
      tokenHolder1,
      erc20TokenholderActionCreatorRole,
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
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
    bytes memory data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role")));

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(
      actionCount, tokenHolder1, erc20TokenholderActionCreatorRole, STRATEGY, address(POLICY), 0, data, ""
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
    bytes memory data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role")));

    uint256 actionCount = CORE.actionsCount();

    vm.expectEmit();
    emit ActionCreated(
      actionCount,
      tokenHolder1,
      erc20TokenholderActionCreatorRole,
      STRATEGY,
      address(POLICY),
      0,
      data,
      "# Action 0 \n This is my action."
    );

    uint256 actionId = erc20TokenholderActionCreator.createActionBySig(
      tokenHolder1,
      erc20TokenholderActionCreatorRole,
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
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
    assertEq(erc20TokenholderActionCreator.nonces(tokenHolder1, ILlamaCore.createActionBySig.selector), 0);
    createActionBySig(v, r, s);
    assertEq(erc20TokenholderActionCreator.nonces(tokenHolder1, ILlamaCore.createActionBySig.selector), 1);
  }

  function test_OperationCannotBeReplayed() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
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
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);
    // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
    // (v,r,s).
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    createActionBySig((v + 1), r, s);
  }

  function test_RevertIf_PolicyholderIncrementsNonce() public {
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(tokenHolder1PrivateKey);

    vm.prank(tokenHolder1);
    erc20TokenholderActionCreator.incrementNonce(ILlamaCore.createActionBySig.selector);

    // Invalid Signature error since the recovered signer address during the call is not the same as policyholder
    // since nonce has increased.
    vm.expectRevert(ILlamaCore.InvalidSignature.selector);
    createActionBySig(v, r, s);
  }
}

// contract CancelAction is ERC20TokenholderActionCreatorTest {
//   uint8 erc20TokenholderActionCreatorRole = 2;
//   bytes data = abi.encodeCall(
//     POLICY.setRoleHolder, (erc20TokenholderActionCreatorRole, address(0xdeadbeef), DEFAULT_ROLE_QTY,
// DEFAULT_ROLE_EXPIRATION)
//   );
//   uint256 threshold = 500_000e18;
//   uint256 actionId;
//   ERC20TokenholderActionCreator erc20TokenholderActionCreator;
//   ActionInfo actionInfo;

//   function setUp() public virtual override {
//     ERC20TokenholderActionCreatorTest.setUp();
//     erc20VotesToken.mint(tokenHolder1, threshold); // we use erc20VotesToken because IVotesToken is an
//     // interface without the `delegate` function
//     vm.prank(tokenHolder1);
//     erc20VotesToken.delegate(tokenHolder1); // we use erc20VotesToken because IVotesToken is an interface without
//     // the `delegate` function

//     vm.roll(block.number + 1);
//     vm.warp(block.timestamp + 1);

//     erc20TokenholderActionCreator = new ERC20TokenholderActionCreator(erc20VotesToken, CORE, threshold);

//     vm.startPrank(address(EXECUTOR)); // init role, assign policy, and assign permission to setRoleHolder to the
//       // erc20VotesToken
//       // voting action creator
//     POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
//     POLICY.setRoleHolder(
//       erc20TokenholderActionCreatorRole, address(erc20TokenholderActionCreator), DEFAULT_ROLE_QTY,
// DEFAULT_ROLE_EXPIRATION
//     );
//     POLICY.setRolePermission(
//       erc20TokenholderActionCreatorRole,
//       ILlamaPolicy.PermissionData(address(POLICY), POLICY.setRoleHolder.selector, address(STRATEGY)),
//       true
//     );
//     vm.stopPrank();

//     vm.roll(block.number + 1);
//     vm.warp(block.timestamp + 1);

//     vm.prank(tokenHolder1);
//     actionId = erc20TokenholderActionCreator.createAction(erc20TokenholderActionCreatorRole, STRATEGY,
// address(POLICY),
// 0, data, "");

//     actionInfo =
//       ActionInfo(actionId, address(erc20TokenholderActionCreator), erc20TokenholderActionCreatorRole, STRATEGY,
// address(POLICY), 0,
// data);
//   }

//   function test_PassesIf_CallerIsActionCreator() public {
//     vm.expectEmit();
//     emit ActionCanceled(actionId, tokenHolder1);
//     vm.prank(tokenHolder1);
//     erc20TokenholderActionCreator.cancelAction(actionInfo);
//   }

//   function test_RevertsIf_CallerIsNotActionCreator(address notCreator) public {
//     vm.assume(notCreator != tokenHolder1);
//     vm.expectRevert(TokenholderActionCreator.OnlyActionCreator.selector);
//     vm.prank(notCreator);
//     erc20TokenholderActionCreator.cancelAction(actionInfo);
//   }
// }

// contract SetActionThreshold is ERC20TokenholderActionCreatorTest {
//   function test_SetsCreationThreshold() public {
//     uint256 threshold = 500_000e18;
//     erc20VotesToken.mint(address(this), 1_000_000e18); // we use erc20VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     vm.warp(block.timestamp + 1);

//     ERC20TokenholderActionCreator erc20TokenholderActionCreator =
//       new ERC20TokenholderActionCreator(erc20VotesToken, CORE, 1_000_000e18);

//     assertEq(erc20TokenholderActionCreator.creationThreshold(), 1_000_000e18);

//     vm.expectEmit();
//     emit ActionThresholdSet(threshold);
//     vm.prank(address(EXECUTOR));
//     erc20TokenholderActionCreator.setActionThreshold(threshold);
//   }

//   function test_RevertsIf_CreationThresholdExceedsTotalSupply() public {
//     uint256 threshold = 1_000_000e18;
//     erc20VotesToken.mint(address(this), 500_000e18); // we use erc20VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     ERC20TokenholderActionCreator erc20TokenholderActionCreator =
//       new ERC20TokenholderActionCreator(erc20VotesToken, CORE, 500_000e18);

//     vm.expectRevert(TokenholderActionCreator.InvalidCreationThreshold.selector);
//     vm.prank(address(EXECUTOR));
//     erc20TokenholderActionCreator.setActionThreshold(threshold);
//   }

//   function test_RevertsIf_CalledByNotLlamaExecutor(address notLlamaExecutor) public {
//     vm.assume(notLlamaExecutor != address(EXECUTOR));
//     uint256 threshold = 500_000e18;
//     erc20VotesToken.mint(address(this), 1_000_000e18); // we use erc20VotesToken because IVotesToken is an interface
//     // without the `mint` function

//     ERC20TokenholderActionCreator erc20TokenholderActionCreator =
//       new ERC20TokenholderActionCreator(erc20VotesToken, CORE, 1_000_000e18);

//     vm.expectRevert(TokenholderActionCreator.OnlyLlamaExecutor.selector);
//     vm.prank(notLlamaExecutor);
//     erc20TokenholderActionCreator.setActionThreshold(threshold);
//   }
// }

// contract CancelActionBySig is ERC20TokenholderActionCreatorTest, LlamaCoreSigUtils {
//   bytes data = abi.encodeCall(POLICY.initializeRole, (RoleDescription.wrap("Test Role")));
//   uint256 actionId;
//   ERC20TokenholderActionCreator erc20TokenholderActionCreator;
//   ActionInfo actionInfo;
//   uint8 erc20TokenholderActionCreatorRole;

//   function setUp() public virtual override {
//     ERC20TokenholderActionCreatorTest.setUp();
//     erc20VotesToken.mint(address(tokenHolder), 1000); // we use erc20VotesToken because IVotesToken is an
//       // interface without the `delegate` function
//     vm.prank(tokenHolder);
//     erc20VotesToken.delegate(tokenHolder); // we use erc20VotesToken because IVotesToken is an interface without
//       // the `delegate` function

//     erc20TokenholderActionCreator = new ERC20TokenholderActionCreator(erc20VotesToken, ILlamaCore(address(CORE)),
// 1000);

//     setDomainHash(
//       LlamaCoreSigUtils.EIP712Domain({
//         name: CORE.name(),
//         version: "1",
//         chainId: block.chainid,
//         verifyingContract: address(erc20TokenholderActionCreator)
//       })
//     );

//     vm.startPrank(address(EXECUTOR)); // init role, assign policy, and assign permission to setRoleHolder to the
//       // erc20VotesToken
//       // voting action creator
//     POLICY.initializeRole(RoleDescription.wrap("Token Voting Action Creator Role"));
//     erc20TokenholderActionCreatorRole = 2;
//     POLICY.setRoleHolder(
//       erc20TokenholderActionCreatorRole, address(erc20TokenholderActionCreator), DEFAULT_ROLE_QTY,
// DEFAULT_ROLE_EXPIRATION
//     );
//     POLICY.setRolePermission(
//       erc20TokenholderActionCreatorRole,
//       ILlamaPolicy.PermissionData(address(POLICY), POLICY.initializeRole.selector, address(STRATEGY)),
//       true
//     );
//     vm.stopPrank();

//     vm.roll(block.number + 1);
//     vm.warp(block.timestamp + 1);

//     vm.expectEmit();
//     emit ActionCreated(CORE.actionsCount(), tokenHolder, erc20TokenholderActionCreatorRole, STRATEGY,
// address(POLICY),
// 0, data, "");
//     vm.prank(tokenHolder);
//     actionId = erc20TokenholderActionCreator.createAction(erc20TokenholderActionCreatorRole, STRATEGY,
// address(POLICY),
// 0, data, "");

//     actionInfo =
//       ActionInfo(actionId, address(erc20TokenholderActionCreator), erc20TokenholderActionCreatorRole, STRATEGY,
// address(POLICY), 0,
// data);

//     vm.roll(block.number + 1);
//     vm.warp(block.timestamp + 1);
//   }

//   function createOffchainSignature(ActionInfo memory _actionInfo, uint256 privateKey)
//     internal
//     view
//     returns (uint8 v, bytes32 r, bytes32 s)
//   {
//     LlamaCoreSigUtils.CancelActionBySig memory cancelAction = LlamaCoreSigUtils.CancelActionBySig({
//       tokenHolder: tokenHolder,
//       actionInfo: _actionInfo,
//       nonce: erc20TokenholderActionCreator.nonces(tokenHolder, ILlamaCore.cancelActionBySig.selector)
//     });
//     bytes32 digest = getCancelActionBySigTypedDataHash(cancelAction);
//     (v, r, s) = vm.sign(privateKey, digest);
//   }

//   function cancelActionBySig(ActionInfo memory _actionInfo, uint8 v, bytes32 r, bytes32 s) internal {
//     erc20TokenholderActionCreator.cancelActionBySig(tokenHolder, _actionInfo, v, r, s);
//   }

//   function test_CancelActionBySig() public {
//     (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);

//     // vm.expectEmit();
//     // emit ActionCanceled(actionInfo.id, tokenHolder);

//     cancelActionBySig(actionInfo, v, r, s);

//     uint256 state = uint256(CORE.getActionState(actionInfo));
//     uint256 canceled = uint256(ActionState.Canceled);
//     assertEq(state, canceled);
//   }

//   function test_CheckNonceIncrements() public {
//     (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);

//     assertEq(erc20TokenholderActionCreator.nonces(tokenHolder, ILlamaCore.cancelActionBySig.selector), 0);
//     cancelActionBySig(actionInfo, v, r, s);
//     assertEq(erc20TokenholderActionCreator.nonces(tokenHolder, ILlamaCore.cancelActionBySig.selector), 1);
//   }

//   function test_OperationCannotBeReplayed() public {
//     (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);
//     cancelActionBySig(actionInfo, v, r, s);
//     // Invalid Signature error since the recovered signer address during the second call is not the same as
// policyholder
//     // since nonce has increased.
//     vm.expectRevert(ILlamaCore.InvalidSignature.selector);
//     cancelActionBySig(actionInfo, v, r, s);
//   }

//   function test_RevertIf_SignerIsNotTokenHolder() public {
//     (, uint256 randomSignerPrivateKey) = makeAddrAndKey("randomSigner");
//     (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, randomSignerPrivateKey);
//     // Invalid Signature error since the recovered signer address is not the same as the policyholder passed in as
//     // parameter.
//     vm.expectRevert(ILlamaCore.InvalidSignature.selector);
//     cancelActionBySig(actionInfo, v, r, s);
//   }

//   function test_RevertIf_SignerIsZeroAddress() public {
//     (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);
//     // Invalid Signature error since the recovered signer address is zero address due to invalid signature values
//     // (v,r,s).
//     vm.expectRevert(ILlamaCore.InvalidSignature.selector);
//     cancelActionBySig(actionInfo, (v + 1), r, s);
//   }

//   function test_RevertIf_PolicyholderIncrementsNonce() public {
//     (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(actionInfo, tokenHolderPrivateKey);

//     vm.prank(tokenHolder);
//     erc20TokenholderActionCreator.incrementNonce(ILlamaCore.cancelActionBySig.selector);

//     // Invalid Signature error since the recovered signer address during the call is not the same as policyholder
//     // since nonce has increased.
//     vm.expectRevert(ILlamaCore.InvalidSignature.selector);
//     cancelActionBySig(actionInfo, v, r, s);
//   }
// }

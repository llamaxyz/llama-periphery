// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Vm} from "forge-std/Vm.sol";

import {LlamaSigUtils} from "test/utils/LlamaSigUtils.sol";

import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";

contract LlamaSignatureTest is Test, LlamaSigUtils {
  string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL"); // can't use constant here

  // Llama Test's Llama instance.
  ILlamaCore constant CORE = ILlamaCore(0xc68046794327490F953EA15522367FFBA0b64f86);
  ILlamaExecutor constant EXECUTOR = ILlamaExecutor(0xe2C1C4FD76694ffb25524FC429d6d92d755D9f71);
  ILlamaPolicy constant POLICY = ILlamaPolicy(0x6f5dfB0eaF832fF0D4204EC85184b634C7946457);

  // Llama policyholder.
  address dummyPolicyholder = 0x4c22FCD2881b94c2A9eE43f0C4433Bf759A2C525;

  function setUp() public virtual {
    vm.createSelectFork(SEPOLIA_RPC_URL, 5_233_667);
  }
}

contract CreateActionBySig is LlamaSignatureTest {
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

  uint8 testRole = 0;
  address testStrategy = 0xaeb1f51ed335116F2Ef311f8c6FeA6B7aFE2B047;
  address testTarget = 0xA8BF95A14b3dE7bB20d39CBBDa5B25c524Dd402A;
  uint256 testValue = 0;
  bytes testData =
    hex"a2bc4cef000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000b7bd14e2497cdc57675e896af84ecb652d294ad1";
  string testDescription = "# yeah\n\n";
  uint256 testNonce = 0;

  function setUp() public virtual override {
    LlamaSignatureTest.setUp();

    // Setting LlamaCore's EIP-712 Domain Hash
    setDomainHash(
      LlamaSigUtils.EIP712Domain({
        name: CORE.name(),
        version: "1",
        chainId: block.chainid,
        verifyingContract: address(CORE)
      })
    );
  }

  function createOffchainSignature(uint256 privateKey) internal view returns (uint8 v, bytes32 r, bytes32 s) {
    LlamaSigUtils.CreateAction memory createAction = LlamaSigUtils.CreateAction({
      policyholder: dummyPolicyholder,
      role: testRole,
      strategy: testStrategy,
      target: testTarget,
      value: testValue,
      data: testData,
      description: testDescription,
      nonce: testNonce
    });
    bytes32 digest = getCreateActionTypedDataHash(createAction);
    (v, r, s) = vm.sign(privateKey, digest);
  }

  function createActionBySig(uint8 v, bytes32 r, bytes32 s) internal returns (uint256 actionId) {
    actionId = CORE.createActionBySig(
      dummyPolicyholder,
      testRole,
      ILlamaStrategy(testStrategy),
      testTarget,
      testValue,
      testData,
      testDescription,
      v,
      r,
      s
    );
  }

  function test_Signature() public {
    uint256 dummyPolicyholderPrivateKey = vm.envUint("POLICYHOLDER_PRIVATE_KEY");
    (uint8 v, bytes32 r, bytes32 s) = createOffchainSignature(dummyPolicyholderPrivateKey);

    vm.expectEmit();
    emit ActionCreated(
      365, dummyPolicyholder, testRole, ILlamaStrategy(testStrategy), testTarget, testValue, testData, testDescription
    );

    createActionBySig(v, r, s);
  }
}

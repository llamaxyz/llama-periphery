// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {LlamaRewardsClaimTestSetup} from "test/rewards-claimer/LlamaRewardsClaimTestSetup.sol";

contract LlamaRewardsClaimStorageTest is LlamaRewardsClaimTestSetup {
  function setUp() public override {
    LlamaRewardsClaimTestSetup.setUp();
  }
}

contract Constructor is LlamaRewardsClaimStorageTest {
  function test_SetsLlamaExecutor() public {
    assertEq(address(rewardsClaimStorage.LLAMA_EXECUTOR()), address(EXECUTOR));
  }

  function test_TargetSelectorAuthorization() public {
    assertTrue(rewardsClaimStorage.authorizedTargetSelectors(address(0xdeadbeef), bytes4(keccak256("withdraw()"))));
  }
}

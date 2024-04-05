// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {LlamaRewardsClaimTestSetup} from "test/rewards-claimer/LlamaRewardsClaimTestSetup.sol";

import {LlamaRewardsClaimStorage} from "src/rewards-claimer/LlamaRewardsClaimStorage.sol";

contract LlamaRewardsClaimStorageTest is LlamaRewardsClaimTestSetup {
  event TargetSelectorAuthorized(address indexed target, bytes4 indexed selector, bool isAuthorized);

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

contract SetAuthorizedTargetSelectors is LlamaRewardsClaimStorageTest {
  function test_RevertIf_CallerIsNotLlama() public {
    LlamaRewardsClaimStorage.TargetSelectorAuthorization[] memory data =
      new LlamaRewardsClaimStorage.TargetSelectorAuthorization[](1);
    data[0] =
      LlamaRewardsClaimStorage.TargetSelectorAuthorization(address(0xdeadbeef), bytes4(keccak256("withdraw()")), false);

    vm.expectRevert(LlamaRewardsClaimStorage.OnlyLlama.selector);
    rewardsClaimStorage.setAuthorizedTargetSelectors(data);
  }

  function test_SetAuthorizedTargetSelectors() public {
    LlamaRewardsClaimStorage.TargetSelectorAuthorization[] memory data =
      new LlamaRewardsClaimStorage.TargetSelectorAuthorization[](1);
    data[0] =
      LlamaRewardsClaimStorage.TargetSelectorAuthorization(address(0xdeadbeef), bytes4(keccak256("withdraw()")), false);

    assertTrue(rewardsClaimStorage.authorizedTargetSelectors(address(0xdeadbeef), bytes4(keccak256("withdraw()"))));

    vm.prank(address(EXECUTOR));
    vm.expectEmit();
    emit TargetSelectorAuthorized(address(0xdeadbeef), bytes4(keccak256("withdraw()")), false);
    rewardsClaimStorage.setAuthorizedTargetSelectors(data);

    assertFalse(rewardsClaimStorage.authorizedTargetSelectors(address(0xdeadbeef), bytes4(keccak256("withdraw()"))));
  }
}

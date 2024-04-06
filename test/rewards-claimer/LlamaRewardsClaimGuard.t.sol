// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {LlamaRewardsClaimTestSetup} from "test/rewards-claimer/LlamaRewardsClaimTestSetup.sol";

import {LlamaRewardsClaimGuard} from "src/rewards-claimer/LlamaRewardsClaimGuard.sol";

contract LlamaRewardsClaimGuardTest is LlamaRewardsClaimTestSetup {
  function setUp() public override {
    LlamaRewardsClaimTestSetup.setUp();
  }
}

contract Constructor is LlamaRewardsClaimGuardTest {
  function test_SetsRewardsClaimer() public {
    assertEq(address(rewardsClaimGuard.REWARDS_CLAIMER()), address(rewardsClaimAccountExtension));
  }
}

contract ValidateActionCreation is LlamaRewardsClaimGuardTest {}

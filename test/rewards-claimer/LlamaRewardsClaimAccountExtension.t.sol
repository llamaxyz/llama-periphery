// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {MockRewardsContract} from "test/mock/MockRewardsContract.sol";
import {LlamaRewardsClaimTestSetup} from "test/rewards-claimer/LlamaRewardsClaimTestSetup.sol";

import {ILlamaAccount} from "src/interfaces/ILlamaAccount.sol";
import {LlamaRewardsClaimAccountExtension} from "src/rewards-claimer/LlamaRewardsClaimAccountExtension.sol";
import {LlamaRewardsClaimGuard} from "src/rewards-claimer/LlamaRewardsClaimGuard.sol";

contract LlamaRewardsClaimAccountExtensionTest is LlamaRewardsClaimTestSetup {
  function setUp() public override {
    LlamaRewardsClaimTestSetup.setUp();
  }
}

contract Constructor is LlamaRewardsClaimAccountExtensionTest {
  function test_SetsRewardsClaimStorage() public {
    assertEq(address(rewardsClaimAccountExtension.REWARDS_CLAIM_STORAGE()), address(rewardsClaimStorage));
  }
}

contract ClaimRewards is LlamaRewardsClaimAccountExtensionTest {}

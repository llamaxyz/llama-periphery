// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";

import {DeployLlamaRewardsClaimer} from "script/DeployLlamaRewardsClaimer.s.sol";

contract LlamaRewardsClaimTestSetup is LlamaPeripheryTestSetup, DeployLlamaRewardsClaimer {
  function setUp() public virtual override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the Llama Token Voting factory and logic contracts.
    DeployLlamaRewardsClaimer.run("mockRewardsClaimerConfig.json");
  }

  // =========================
  // ======== Helpers ========
  // =========================
}

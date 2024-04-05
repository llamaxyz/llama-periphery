// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";
import {MockRewardsContract} from "test/mock/MockRewardsContract.sol";

import {DeployLlamaRewardsClaimer} from "script/DeployLlamaRewardsClaimer.s.sol";

contract LlamaRewardsClaimTestSetup is LlamaPeripheryTestSetup, DeployLlamaRewardsClaimer {
  IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

  function setUp() public virtual override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the Llama rewards claim contracts.
    DeployLlamaRewardsClaimer.run("mockRewardsClaimerConfig.json");

    // Deploy the mock rewards contracts and set LlamaAccount as the reward claimer.
    // Deal ETH and UNI to the rewards contracts.
    MockRewardsContract rewardsContract1 = new MockRewardsContract(address(ACCOUNT));
    vm.deal(address(rewardsContract1), 1 ether);
    deal(address(USDC), address(rewardsContract1), 1 ether);

    MockRewardsContract rewardsContract2 = new MockRewardsContract(address(ACCOUNT));
    vm.deal(address(rewardsContract2), 1 ether);
    deal(address(USDC), address(rewardsContract2), 1 ether);

    MockRewardsContract rewardsContract3 = new MockRewardsContract(address(ACCOUNT));
    vm.deal(address(rewardsContract3), 1 ether);
    deal(address(USDC), address(rewardsContract3), 1 ether);

    MockRewardsContract rewardsContract4 = new MockRewardsContract(address(ACCOUNT));
    vm.deal(address(rewardsContract4), 1 ether);
    deal(address(USDC), address(rewardsContract4), 1 ether);

    MockRewardsContract rewardsContract5 = new MockRewardsContract(address(ACCOUNT));
    vm.deal(address(rewardsContract5), 1 ether);
    deal(address(USDC), address(rewardsContract5), 1 ether);
  }
}

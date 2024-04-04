// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";
import {LlamaRewardsClaimAccountExtension} from "src/rewards-claimer/LlamaRewardsClaimAccountExtension.sol";
import {LlamaRewardsClaimGuard} from "src/rewards-claimer/LlamaRewardsClaimGuard.sol";
import {LlamaRewardsClaimStorage} from "src/rewards-claimer/LlamaRewardsClaimStorage.sol";

contract DeployLlamaRewardsClaimer is Script {
  // Rewards claim contracts.
  LlamaRewardsClaimStorage rewardsClaimStorage;
  LlamaRewardsClaimAccountExtension rewardsClaimAccountExtension;
  LlamaRewardsClaimGuard rewardsClaimGuard;

  function run() public {
    DeployUtils.print(string.concat("Deploying Llama rewards claimer contracts to chain:", vm.toString(block.chainid)));

    vm.broadcast();
    rewardsClaimStorage =
      new LlamaRewardsClaimStorage(address(0), new LlamaRewardsClaimStorage.TargetSelectorAuthorization[](0));
    DeployUtils.print(string.concat("  LlamaRewardsClaimStorage: ", vm.toString(address(rewardsClaimStorage))));

    vm.broadcast();
    rewardsClaimAccountExtension = new LlamaRewardsClaimAccountExtension(rewardsClaimStorage);
    DeployUtils.print(
      string.concat("  LlamaRewardsClaimAccountExtension: ", vm.toString(address(rewardsClaimAccountExtension)))
    );

    vm.broadcast();
    rewardsClaimGuard = new LlamaRewardsClaimGuard(rewardsClaimAccountExtension);
    DeployUtils.print(string.concat("  LlamaRewardsClaimGuard: ", vm.toString(address(rewardsClaimGuard))));
  }
}

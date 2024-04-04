// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, stdJson} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";

import {LlamaRewardsClaimAccountExtension} from "src/rewards-claimer/LlamaRewardsClaimAccountExtension.sol";
import {LlamaRewardsClaimGuard} from "src/rewards-claimer/LlamaRewardsClaimGuard.sol";
import {LlamaRewardsClaimStorage} from "src/rewards-claimer/LlamaRewardsClaimStorage.sol";

contract DeployLlamaRewardsClaimer is Script {
  using stdJson for string;

  struct TargetSelectorAuthorizationInputs {
    // Attributes need to be in alphabetical order so JSON decodes properly.
    string comment;
    bool isAuthorized;
    bytes selector;
    address target;
  }

  // Rewards claim contracts.
  LlamaRewardsClaimStorage rewardsClaimStorage;
  LlamaRewardsClaimAccountExtension rewardsClaimAccountExtension;
  LlamaRewardsClaimGuard rewardsClaimGuard;

  function run(string memory configFile) public {
    string memory jsonInput = DeployUtils.readScriptInput(configFile);

    address llamaExecutor = jsonInput.readAddress(".llamaExecutor");
    LlamaRewardsClaimStorage.TargetSelectorAuthorization[] memory data = readTargetSelectorAuthorizations(jsonInput);

    DeployUtils.print(string.concat("Deploying Llama rewards claimer contracts to chain:", vm.toString(block.chainid)));

    vm.broadcast();
    rewardsClaimStorage = new LlamaRewardsClaimStorage(llamaExecutor, data);
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

  function readTargetSelectorAuthorizations(string memory jsonInput)
    internal
    pure
    returns (LlamaRewardsClaimStorage.TargetSelectorAuthorization[] memory)
  {
    bytes memory data = jsonInput.parseRaw(".initialTargetSelectorAuthorizations");

    TargetSelectorAuthorizationInputs[] memory rawConfigs = abi.decode(data, (TargetSelectorAuthorizationInputs[]));

    LlamaRewardsClaimStorage.TargetSelectorAuthorization[] memory configs =
      new LlamaRewardsClaimStorage.TargetSelectorAuthorization[](rawConfigs.length);

    for (uint256 i = 0; i < rawConfigs.length; i++) {
      configs[i].target = rawConfigs[i].target;
      configs[i].selector = bytes4(rawConfigs[i].selector);
      configs[i].isAuthorized = rawConfigs[i].isAuthorized;
    }

    return configs;
  }
}

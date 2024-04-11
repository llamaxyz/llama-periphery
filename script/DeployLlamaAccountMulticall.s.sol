// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, stdJson} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";

import {LlamaAccountMulticallExtension} from "src/account-multicall/LlamaAccountMulticallExtension.sol";
import {LlamaAccountMulticallGuard} from "src/account-multicall/LlamaAccountMulticallGuard.sol";
import {LlamaAccountMulticallStorage} from "src/account-multicall/LlamaAccountMulticallStorage.sol";

contract DeployLlamaAccountMulticall is Script {
  using stdJson for string;

  struct TargetSelectorAuthorizationInputs {
    // Attributes need to be in alphabetical order so JSON decodes properly.
    string comment;
    bytes selector;
    address target;
  }

  // Account multicall contracts.
  LlamaAccountMulticallStorage accountMulticallStorage;
  LlamaAccountMulticallExtension accountMulticallExtension;
  LlamaAccountMulticallGuard accountMulticallGuard;

  function run(string memory configFile) public {
    string memory jsonInput = DeployUtils.readScriptInput(configFile);

    address llamaExecutor = jsonInput.readAddress(".llamaExecutor");
    LlamaAccountMulticallStorage.TargetSelectorAuthorization[] memory data = readTargetSelectorAuthorizations(jsonInput);

    DeployUtils.print(string.concat("Deploying Llama rewards claimer contracts to chain:", vm.toString(block.chainid)));

    vm.broadcast();
    accountMulticallStorage = new LlamaAccountMulticallStorage(llamaExecutor, data);
    DeployUtils.print(string.concat("  LlamaAccountMulticallStorage: ", vm.toString(address(accountMulticallStorage))));

    vm.broadcast();
    accountMulticallExtension = new LlamaAccountMulticallExtension(accountMulticallStorage);
    DeployUtils.print(
      string.concat("  LlamaAccountMulticallExtension: ", vm.toString(address(accountMulticallExtension)))
    );

    vm.broadcast();
    accountMulticallGuard = new LlamaAccountMulticallGuard(accountMulticallExtension);
    DeployUtils.print(string.concat("  LlamaAccountMulticallGuard: ", vm.toString(address(accountMulticallGuard))));
  }

  function readTargetSelectorAuthorizations(string memory jsonInput)
    internal
    pure
    returns (LlamaAccountMulticallStorage.TargetSelectorAuthorization[] memory)
  {
    bytes memory data = jsonInput.parseRaw(".initialTargetSelectorAuthorizations");

    TargetSelectorAuthorizationInputs[] memory rawConfigs = abi.decode(data, (TargetSelectorAuthorizationInputs[]));

    LlamaAccountMulticallStorage.TargetSelectorAuthorization[] memory configs =
      new LlamaAccountMulticallStorage.TargetSelectorAuthorization[](rawConfigs.length);

    for (uint256 i = 0; i < rawConfigs.length; i++) {
      configs[i].target = rawConfigs[i].target;
      configs[i].selector = bytes4(rawConfigs[i].selector);
      configs[i].isAuthorized = true;
    }

    return configs;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract DeployLlamaFactory is Script {
  LlamaTokenVotingFactory tokenVotingFactory;

  function run() public {
    DeployUtils.print(string.concat("Deploying Llama token voting factory to chain:", vm.toString(block.chainid)));

    vm.broadcast();
    tokenVotingFactory = new LlamaTokenVotingFactory();
    DeployUtils.print(string.concat("  LlamaTokenVotingFactory: ", vm.toString(address(tokenVotingFactory))));
  }
}

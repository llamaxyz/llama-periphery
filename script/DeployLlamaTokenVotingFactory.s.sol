// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";
import {LlamaTokenActionCreator} from "src/token-voting/LlamaTokenActionCreator.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";
import {LlamaTokenAdapterVotesTimestamp} from "src/token-voting/token-adapters/LlamaTokenAdapterVotesTimestamp.sol";

contract DeployLlamaTokenVotingFactory is Script {
  // Logic contracts.
  LlamaTokenActionCreator llamaTokenActionCreatorLogic;
  LlamaTokenCaster llamaTokenCasterLogic;
  LlamaTokenAdapterVotesTimestamp llamaTokenAdapterTimestampLogic;

  // Factory contracts.
  LlamaTokenVotingFactory tokenVotingFactory;

  function run() public {
    DeployUtils.print(
      string.concat("Deploying Llama token voting factory and logic contracts to chain:", vm.toString(block.chainid))
    );

    vm.broadcast();
    llamaTokenActionCreatorLogic = new LlamaTokenActionCreator();
    DeployUtils.print(
      string.concat("  LlamaTokenActionCreatorLogic: ", vm.toString(address(llamaTokenActionCreatorLogic)))
    );

    vm.broadcast();
    llamaTokenCasterLogic = new LlamaTokenCaster();
    DeployUtils.print(string.concat("  LlamaTokenCasterLogic: ", vm.toString(address(llamaTokenCasterLogic))));

    vm.broadcast();
    tokenVotingFactory = new LlamaTokenVotingFactory(llamaTokenActionCreatorLogic, llamaTokenCasterLogic);
    DeployUtils.print(string.concat("  LlamaTokenVotingFactory: ", vm.toString(address(tokenVotingFactory))));

    vm.broadcast();
    llamaTokenAdapterTimestampLogic = new LlamaTokenAdapterVotesTimestamp();
    DeployUtils.print(
      string.concat("  LlamaTokenAdapterVotesTimestamp: ", vm.toString(address(llamaTokenAdapterTimestampLogic)))
    );
  }
}

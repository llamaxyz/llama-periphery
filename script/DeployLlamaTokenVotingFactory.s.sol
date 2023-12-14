// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";
import {LlamaERC20TokenActionCreator} from "src/token-voting/LlamaERC20TokenActionCreator.sol";
import {LlamaERC20TokenCaster} from "src/token-voting/LlamaERC20TokenCaster.sol";
import {LlamaERC721TokenActionCreator} from "src/token-voting/LlamaERC721TokenActionCreator.sol";
import {LlamaERC721TokenCaster} from "src/token-voting/LlamaERC721TokenCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract DeployLlamaTokenVotingFactory is Script {
  // Logic contracts.
  LlamaERC20TokenActionCreator llamaERC20TokenActionCreatorLogic;
  LlamaERC20TokenCaster llamaERC20TokenCasterLogic;
  LlamaERC721TokenActionCreator llamaERC721TokenActionCreatorLogic;
  LlamaERC721TokenCaster llamaERC721TokenCasterLogic;

  // Factory contracts.
  LlamaTokenVotingFactory tokenVotingFactory;

  function run() public {
    DeployUtils.print(
      string.concat("Deploying Llama token voting factory and logic contracts to chain:", vm.toString(block.chainid))
    );

    vm.broadcast();
    llamaERC20TokenActionCreatorLogic = new LlamaERC20TokenActionCreator();
    DeployUtils.print(
      string.concat("  LlamaERC20TokenActionCreatorLogic: ", vm.toString(address(llamaERC20TokenActionCreatorLogic)))
    );

    vm.broadcast();
    llamaERC20TokenCasterLogic = new LlamaERC20TokenCaster();
    DeployUtils.print(string.concat("  LlamaERC20TokenCasterLogic: ", vm.toString(address(llamaERC20TokenCasterLogic))));

    vm.broadcast();
    llamaERC721TokenActionCreatorLogic = new LlamaERC721TokenActionCreator();
    DeployUtils.print(
      string.concat("  LlamaERC721TokenActionCreatorLogic: ", vm.toString(address(llamaERC721TokenActionCreatorLogic)))
    );

    vm.broadcast();
    llamaERC721TokenCasterLogic = new LlamaERC721TokenCaster();
    DeployUtils.print(
      string.concat("  LlamaERC721TokenCasterLogic: ", vm.toString(address(llamaERC721TokenCasterLogic)))
    );

    vm.broadcast();
    tokenVotingFactory = new LlamaTokenVotingFactory(
      llamaERC20TokenActionCreatorLogic,
      llamaERC20TokenCasterLogic,
      llamaERC721TokenActionCreatorLogic,
      llamaERC721TokenCasterLogic
    );
    DeployUtils.print(string.concat("  LlamaTokenVotingFactory: ", vm.toString(address(tokenVotingFactory))));

    // Deploy the timestamp managers here when we develop them.
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";
import {LlamaERC20TokenHolderActionCreator} from "src/token-voting/LlamaERC20TokenHolderActionCreator.sol";
import {LlamaERC20TokenHolderCaster} from "src/token-voting/LlamaERC20TokenHolderCaster.sol";
import {LlamaERC721TokenHolderActionCreator} from "src/token-voting/LlamaERC721TokenHolderActionCreator.sol";
import {LlamaERC721TokenHolderCaster} from "src/token-voting/LlamaERC721TokenHolderCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract DeployLlamaTokenVotingFactory is Script {
  // Logic contracts.
  LlamaERC20TokenHolderActionCreator llamaERC20TokenHolderActionCreatorLogic;
  LlamaERC20TokenHolderCaster llamaERC20TokenHolderCasterLogic;
  LlamaERC721TokenHolderActionCreator llamaERC721TokenHolderActionCreatorLogic;
  LlamaERC721TokenHolderCaster llamaERC721TokenHolderCasterLogic;

  // Factory contracts.
  LlamaTokenVotingFactory tokenVotingFactory;

  function run() public {
    DeployUtils.print(
      string.concat("Deploying Llama token voting factory and logic contracts to chain:", vm.toString(block.chainid))
    );

    vm.broadcast();
    llamaERC20TokenHolderActionCreatorLogic = new LlamaERC20TokenHolderActionCreator();
    DeployUtils.print(
      string.concat(
        "  LlamaERC20TokenHolderActionCreatorLogic: ", vm.toString(address(llamaERC20TokenHolderActionCreatorLogic))
      )
    );

    vm.broadcast();
    llamaERC20TokenHolderCasterLogic = new LlamaERC20TokenHolderCaster();
    DeployUtils.print(
      string.concat("  LlamaERC20TokenHolderCasterLogic: ", vm.toString(address(llamaERC20TokenHolderCasterLogic)))
    );

    vm.broadcast();
    llamaERC721TokenHolderActionCreatorLogic = new LlamaERC721TokenHolderActionCreator();
    DeployUtils.print(
      string.concat(
        "  LlamaERC721TokenHolderActionCreatorLogic: ", vm.toString(address(llamaERC721TokenHolderActionCreatorLogic))
      )
    );

    vm.broadcast();
    llamaERC721TokenHolderCasterLogic = new LlamaERC721TokenHolderCaster();
    DeployUtils.print(
      string.concat("  LlamaERC721TokenHolderCasterLogic: ", vm.toString(address(llamaERC721TokenHolderCasterLogic)))
    );

    vm.broadcast();
    tokenVotingFactory = new LlamaTokenVotingFactory(
      llamaERC20TokenHolderActionCreatorLogic,
      llamaERC20TokenHolderCasterLogic,
      llamaERC721TokenHolderActionCreatorLogic,
      llamaERC721TokenHolderCasterLogic
    );
    DeployUtils.print(string.concat("  LlamaTokenVotingFactory: ", vm.toString(address(tokenVotingFactory))));
  }
}

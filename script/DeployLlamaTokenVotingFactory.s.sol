// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";
import {ERC20TokenHolderActionCreator} from "src/token-voting/ERC20TokenHolderActionCreator.sol";
import {ERC20TokenHolderCaster} from "src/token-voting/ERC20TokenHolderCaster.sol";
import {ERC721TokenHolderActionCreator} from "src/token-voting/ERC721TokenHolderActionCreator.sol";
import {ERC721TokenHolderCaster} from "src/token-voting/ERC721TokenHolderCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract DeployLlamaTokenVotingFactory is Script {
  // Logic contracts.
  ERC20TokenHolderActionCreator erc20TokenHolderActionCreatorLogic;
  ERC20TokenHolderCaster erc20TokenHolderCasterLogic;
  ERC721TokenHolderActionCreator erc721TokenHolderActionCreatorLogic;
  ERC721TokenHolderCaster erc721TokenHolderCasterLogic;

  // Factory contracts.
  LlamaTokenVotingFactory tokenVotingFactory;

  function run() public {
    DeployUtils.print(
      string.concat("Deploying Llama token voting factory and logic contracts to chain:", vm.toString(block.chainid))
    );

    vm.broadcast();
    erc20TokenHolderActionCreatorLogic = new ERC20TokenHolderActionCreator();
    DeployUtils.print(
      string.concat("  ERC20TokenHolderActionCreatorLogic: ", vm.toString(address(erc20TokenHolderActionCreatorLogic)))
    );

    vm.broadcast();
    erc20TokenHolderCasterLogic = new ERC20TokenHolderCaster();
    DeployUtils.print(
      string.concat("  ERC20TokenHolderCasterLogic: ", vm.toString(address(erc20TokenHolderCasterLogic)))
    );

    vm.broadcast();
    erc721TokenHolderActionCreatorLogic = new ERC721TokenHolderActionCreator();
    DeployUtils.print(
      string.concat(
        "  ERC721TokenHolderActionCreatorLogic: ", vm.toString(address(erc721TokenHolderActionCreatorLogic))
      )
    );

    vm.broadcast();
    erc721TokenHolderCasterLogic = new ERC721TokenHolderCaster();
    DeployUtils.print(
      string.concat("  ERC721TokenHolderCasterLogic: ", vm.toString(address(erc721TokenHolderCasterLogic)))
    );

    vm.broadcast();
    tokenVotingFactory = new LlamaTokenVotingFactory(
      erc20TokenHolderActionCreatorLogic,
      erc20TokenHolderCasterLogic,
      erc721TokenHolderActionCreatorLogic,
      erc721TokenHolderCasterLogic
    );
    DeployUtils.print(string.concat("  LlamaTokenVotingFactory: ", vm.toString(address(tokenVotingFactory))));
  }
}

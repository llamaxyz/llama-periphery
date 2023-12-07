// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";
import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {ERC20TokenholderCaster} from "src/token-voting/ERC20TokenholderCaster.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {ERC721TokenholderCaster} from "src/token-voting/ERC721TokenholderCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

contract DeployLlamaFactory is Script {
  // Logic contracts.
  ERC20TokenholderActionCreator erc20TokenholderActionCreatorLogic;
  ERC20TokenholderCaster erc20TokenholderCasterLogic;
  ERC721TokenholderActionCreator erc721TokenholderActionCreatorLogic;
  ERC721TokenholderCaster erc721TokenholderCasterLogic;

  // Factory contracts.
  LlamaTokenVotingFactory tokenVotingFactory;

  function run() public {
    DeployUtils.print(
      string.concat("Deploying Llama token voting factory and logic contracts to chain:", vm.toString(block.chainid))
    );

    vm.broadcast();
    erc20TokenholderActionCreatorLogic = new ERC20TokenholderActionCreator();
    DeployUtils.print(
      string.concat("  ERC20TokenholderActionCreatorLogic: ", vm.toString(address(erc20TokenholderActionCreatorLogic)))
    );

    vm.broadcast();
    erc20TokenholderCasterLogic = new ERC20TokenholderCaster();
    DeployUtils.print(
      string.concat("  ERC20TokenholderCasterLogic: ", vm.toString(address(erc20TokenholderCasterLogic)))
    );

    vm.broadcast();
    erc721TokenholderActionCreatorLogic = new ERC721TokenholderActionCreator();
    DeployUtils.print(
      string.concat(
        "  ERC721TokenholderActionCreatorLogic: ", vm.toString(address(erc721TokenholderActionCreatorLogic))
      )
    );

    vm.broadcast();
    erc721TokenholderCasterLogic = new ERC721TokenholderCaster();
    DeployUtils.print(
      string.concat("  ERC721TokenholderCasterLogic: ", vm.toString(address(erc721TokenholderCasterLogic)))
    );

    vm.broadcast();
    tokenVotingFactory = new LlamaTokenVotingFactory(
      erc20TokenholderActionCreatorLogic,
      erc20TokenholderCasterLogic,
      erc721TokenholderActionCreatorLogic,
      erc721TokenholderCasterLogic
    );
    DeployUtils.print(string.concat("  LlamaTokenVotingFactory: ", vm.toString(address(tokenVotingFactory))));
  }
}

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
  LlamaERC20TokenHolderActionCreator erc20LlamaTokenHolderActionCreatorLogic;
  LlamaERC20TokenHolderCaster erc20LlamaTokenHolderCasterLogic;
  LlamaERC721TokenHolderActionCreator erc721LlamaTokenHolderActionCreatorLogic;
  LlamaERC721TokenHolderCaster erc721LlamaTokenHolderCasterLogic;

  // Factory contracts.
  LlamaTokenVotingFactory tokenVotingFactory;

  function run() public {
    DeployUtils.print(
      string.concat("Deploying Llama token voting factory and logic contracts to chain:", vm.toString(block.chainid))
    );

    vm.broadcast();
    erc20LlamaTokenHolderActionCreatorLogic = new LlamaERC20TokenHolderActionCreator();
    DeployUtils.print(
      string.concat(
        "  LlamaERC20TokenHolderActionCreatorLogic: ", vm.toString(address(erc20LlamaTokenHolderActionCreatorLogic))
      )
    );

    vm.broadcast();
    erc20LlamaTokenHolderCasterLogic = new LlamaERC20TokenHolderCaster();
    DeployUtils.print(
      string.concat("  LlamaERC20TokenHolderCasterLogic: ", vm.toString(address(erc20LlamaTokenHolderCasterLogic)))
    );

    vm.broadcast();
    erc721LlamaTokenHolderActionCreatorLogic = new LlamaERC721TokenHolderActionCreator();
    DeployUtils.print(
      string.concat(
        "  LlamaERC721TokenHolderActionCreatorLogic: ", vm.toString(address(erc721LlamaTokenHolderActionCreatorLogic))
      )
    );

    vm.broadcast();
    erc721LlamaTokenHolderCasterLogic = new LlamaERC721TokenHolderCaster();
    DeployUtils.print(
      string.concat("  LlamaERC721TokenHolderCasterLogic: ", vm.toString(address(erc721LlamaTokenHolderCasterLogic)))
    );

    vm.broadcast();
    tokenVotingFactory = new LlamaTokenVotingFactory(
      erc20LlamaTokenHolderActionCreatorLogic,
      erc20LlamaTokenHolderCasterLogic,
      erc721LlamaTokenHolderActionCreatorLogic,
      erc721LlamaTokenHolderCasterLogic
    );
    DeployUtils.print(string.concat("  LlamaTokenVotingFactory: ", vm.toString(address(tokenVotingFactory))));
  }
}

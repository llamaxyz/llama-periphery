// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {MockERC20Votes} from "test/mock/MockERC20Votes.sol";
import {MockERC721Votes} from "test/mock/MockERC721Votes.sol";
import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";

import {DeployLlamaTokenVotingFactory} from "script/DeployLlamaTokenVotingFactory.s.sol";

import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {ERC20TokenholderCaster} from "src/token-voting/ERC20TokenholderCaster.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {ERC721TokenholderCaster} from "src/token-voting/ERC721TokenholderCaster.sol";

contract LlamaTokenVotingTestSetup is LlamaPeripheryTestSetup, DeployLlamaTokenVotingFactory {
  // ERC20 Token Voting Constants.
  uint256 public constant ERC20_CREATION_THRESHOLD = 500_000e18;
  uint256 public constant ERC20_MIN_APPROVAL_PCT = 1000;
  uint256 public constant ERC20_MIN_DISAPPROVAL_PCT = 1000;

  // ERC721 Token Voting Constants.
  uint256 public constant ERC721_CREATION_THRESHOLD = 1;
  uint256 public constant ERC721_MIN_APPROVAL_PCT = 1;
  uint256 public constant ERC721_MIN_DISAPPROVAL_PCT = 1;

  // Votes Tokens
  MockERC20Votes public erc20VotesToken;
  MockERC721Votes public erc721VotesToken;

  // Token holders.
  address tokenHolder1;
  uint256 tokenHolder1PrivateKey;
  address tokenHolder2;
  uint256 tokenHolder2PrivateKey;
  address tokenHolder3;
  uint256 tokenHolder3PrivateKey;
  address notTokenHolder;
  uint256 notTokenHolderPrivateKey;

  function setUp() public virtual override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the Llama Token Voting factory and logic contracts.
    DeployLlamaTokenVotingFactory.run();

    // Deploy the ERC20 and ERC721 tokens.
    erc20VotesToken = new MockERC20Votes();
    erc721VotesToken = new MockERC721Votes();

    // Setting up tokenholder addresses and private keys.
    (tokenHolder1, tokenHolder1PrivateKey) = makeAddrAndKey("tokenHolder1");
    (tokenHolder2, tokenHolder2PrivateKey) = makeAddrAndKey("tokenHolder2");
    (tokenHolder3, tokenHolder3PrivateKey) = makeAddrAndKey("tokenHolder3");
    (notTokenHolder, notTokenHolderPrivateKey) = makeAddrAndKey("notTokenHolder");

    // Mint tokens to core team members.
    erc20VotesToken.mint(tokenHolder1, ERC20_CREATION_THRESHOLD);
    erc20VotesToken.mint(tokenHolder2, ERC20_CREATION_THRESHOLD);
    erc20VotesToken.mint(tokenHolder3, ERC20_CREATION_THRESHOLD);
    erc721VotesToken.mint(tokenHolder1, 0);
    erc721VotesToken.mint(tokenHolder2, 1);
    erc721VotesToken.mint(tokenHolder3, 2);

    // Mine block so that the ERC20 and ERC721 supply will be available when doing a past timestamp check at initialize
    // during deployment.
    mineBlock();
  }

  // =========================
  // ======== Helpers ========
  // =========================

  function _deployERC20TokenVotingModule() internal returns (ERC20TokenholderActionCreator, ERC20TokenholderCaster) {
    vm.prank(address(EXECUTOR));
    (address erc20TokenholderActionCreator, address erc20TokenholderCaster) = tokenVotingFactory.deployTokenVotingModule(
      address(erc20VotesToken), true, ERC20_CREATION_THRESHOLD, ERC20_MIN_APPROVAL_PCT, ERC20_MIN_DISAPPROVAL_PCT
    );
    return
      (ERC20TokenholderActionCreator(erc20TokenholderActionCreator), ERC20TokenholderCaster(erc20TokenholderCaster));
  }

  function _deployERC721TokenVotingModule() internal returns (ERC721TokenholderActionCreator, ERC721TokenholderCaster) {
    vm.prank(address(EXECUTOR));
    (address erc721TokenholderActionCreator, address erc721TokenholderCaster) = tokenVotingFactory
      .deployTokenVotingModule(
      address(erc721VotesToken), false, ERC721_CREATION_THRESHOLD, ERC721_MIN_APPROVAL_PCT, ERC721_MIN_DISAPPROVAL_PCT
    );
    return
      (ERC721TokenholderActionCreator(erc721TokenholderActionCreator), ERC721TokenholderCaster(erc721TokenholderCaster));
  }
}

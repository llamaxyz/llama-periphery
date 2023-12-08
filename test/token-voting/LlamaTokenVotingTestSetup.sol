// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {MockERC20Votes} from "test/mock/MockERC20Votes.sol";
import {MockERC721Votes} from "test/mock/MockERC721Votes.sol";
import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";

import {DeployLlamaTokenVotingFactory} from "script/DeployLlamaTokenVotingFactory.s.sol";

contract LlamaTokenVotingTestSetup is LlamaPeripheryTestSetup, DeployLlamaTokenVotingFactory {
  // ERC20 Token Voting Constants.
  uint256 public constant ERC20_CREATION_THRESHOLD = 100;
  uint256 public constant ERC20_MIN_APPROVAL_PCT = 1000;
  uint256 public constant ERC20_MIN_DISAPPROVAL_PCT = 1000;

  // ERC721 Token Voting Constants.
  uint256 public constant ERC721_CREATION_THRESHOLD = 1;
  uint256 public constant ERC721_MIN_APPROVAL_PCT = 1;
  uint256 public constant ERC721_MIN_DISAPPROVAL_PCT = 1;

  // Votes Tokens
  MockERC20Votes public erc20VotesToken;
  MockERC721Votes public erc721VotesToken;

  function setUp() public virtual override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the Llama Token Voting factory and logic contracts.
    DeployLlamaTokenVotingFactory.run();

    // Deploy the ERC20 and ERC721 tokens.
    erc20VotesToken = new MockERC20Votes();
    erc721VotesToken = new MockERC721Votes();

    // Mint tokens to core team members.
    erc20VotesToken.mint(coreTeam1, 100);
    erc20VotesToken.mint(coreTeam2, 100);
    erc20VotesToken.mint(coreTeam3, 100);
    erc20VotesToken.mint(coreTeam4, 100);
    erc721VotesToken.mint(coreTeam1, 0);
    erc721VotesToken.mint(coreTeam2, 1);
    erc721VotesToken.mint(coreTeam3, 2);
    erc721VotesToken.mint(coreTeam4, 3);

    // Mine block so that the ERC20 and ERC721 supply will be available when doing a past timestamp check at initialize.
    mineBlock();
  }
}

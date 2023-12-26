// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";

import {LlamaTokenVotingTestSetup} from "test/token-voting/LlamaTokenVotingTestSetup.sol";
import {LlamaCoreSigUtils} from "test/utils/LlamaCoreSigUtils.sol";

import {LlamaTokenAdapterVotesTimestamp} from "src/token-voting/token-adapters/LlamaTokenAdapterVotesTimestamp.sol";

contract LlamaTokenAdapterVotesTimestampTest is LlamaTokenVotingTestSetup, LlamaCoreSigUtils {
  function setUp() public virtual override {
    LlamaTokenVotingTestSetup.setUp();
  }
}

contract Constructor is LlamaTokenAdapterVotesTimestampTest {
  function test_RevertIf_InitializeImplementationContract() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(erc20VotesToken)));
    llamaTokenAdapterTimestampLogic.initialize(adapterConfig);
  }
}

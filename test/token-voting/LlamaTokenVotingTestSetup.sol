// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {Vm} from "forge-std/Vm.sol";

import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";

import {DeployLlamaTokenVotingFactory} from "script/DeployLlamaTokenVotingFactory.s.sol";

contract LlamaTokenVotingTestSetup is LlamaPeripheryTestSetup, DeployLlamaTokenVotingFactory {
  function setUp() public virtual override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the Llama Token Voting factory and logic contracts
    DeployLlamaTokenVotingFactory.run();
  }
}

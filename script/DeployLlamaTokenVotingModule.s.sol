// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";

import {DeployUtils} from "script/DeployUtils.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {CasterConfig} from "src/lib/Structs.sol";
import {LlamaTokenActionCreator} from "src/token-voting/LlamaTokenActionCreator.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";
import {LlamaTokenAdapterVotesTimestamp} from "src/token-voting/token-adapters/LlamaTokenAdapterVotesTimestamp.sol";

contract DeployLlamaTokenVotingModule is Script {
  // Make sure these addresses are correct
  // Logic contracts.
  LlamaTokenAdapterVotesTimestamp constant llamaTokenAdapterTimestampLogic =
    LlamaTokenAdapterVotesTimestamp(0x88D63b8c5F8C3e95743F1d26Df8aDd0669614278);

  // Factory contracts.
  LlamaTokenVotingFactory constant tokenVotingFactory =
    LlamaTokenVotingFactory(0x2997f4D6899DC91dE9Ae0FcD98b49CA88b8Fc85e);

  address constant governanceToken = 0xf44d44a54440F22e5DC5adb7efA3233645f04007;

  function run(address deployer) public {
    DeployUtils.print(string.concat("Deploying Llama token voting module to chain:", vm.toString(block.chainid)));

    bytes memory adapterConfig = abi.encode(LlamaTokenAdapterVotesTimestamp.Config(address(governanceToken)));

    // =================================================
    // ======== Configure these variables below ========
    // =================================================

    ILlamaCore core = ILlamaCore(address(0));
    // Needs to be updated when the deployer, Llama core and adapter config are the same.
    uint256 nonce = 0;
    // Token Proposer role in instance defined by core variable
    uint8 actionCreatorRole = 0;
    // Token Governor role in instance defined by core variable
    uint8 casterRole = 0;
    // Token threshold to propose
    uint256 creationThreshold = 0;
    // Quorum needed for vote to be eligible to pass % in bps (i.e. 20% is 20_00)
    uint16 voteQuorumPct = 2500;
    // Quorum needed for veto to be eligible to pass % in bps (i.e. 20% is 20_00)
    uint16 vetoQuorumPct = 1500;

    // =================================================
    // ======== Configure these variables above ========
    // =================================================

    uint16 delayPeriodPct = 2500;
    uint16 castingPeriodPct = 5000;
    uint16 submissionPeriodPct = 2500;

    CasterConfig memory casterConfig =
      CasterConfig(voteQuorumPct, vetoQuorumPct, delayPeriodPct, castingPeriodPct, submissionPeriodPct);

    LlamaTokenVotingFactory.LlamaTokenVotingConfig memory config = LlamaTokenVotingFactory.LlamaTokenVotingConfig(
      core,
      llamaTokenAdapterTimestampLogic,
      adapterConfig,
      nonce,
      actionCreatorRole,
      casterRole,
      creationThreshold,
      casterConfig
    );

    vm.broadcast(deployer);
    (LlamaTokenActionCreator actionCreator, LlamaTokenCaster caster) = tokenVotingFactory.deploy(config);

    DeployUtils.print("Successfully deployed a new Llama token voting module");
    DeployUtils.print(string.concat("  LlamaTokenActionCreator:     ", vm.toString(address(actionCreator))));
    DeployUtils.print(string.concat("  LlamaTokenCaster:   ", vm.toString(address(caster))));
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {LlamaTokenVotingConfig} from "src/lib/Structs.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {LlamaBaseScript} from "src/token-voting/llama-scripts/LlamaBaseScript.sol";
import {LlamaTokenGovernor} from "src/token-voting/LlamaTokenGovernor.sol";
import {LlamaTokenVotingFactory} from "src/token-voting/LlamaTokenVotingFactory.sol";

/// @title LlamaDeployTokenGovernorWithRole
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract is a script that lets Llama instances deploy a token voting module, initialize a new role,
/// mint a policy and assign the role to the new token voting governor in a single action.
/// @dev This contract is a script that can only be used via delegatecall, which means it must be authorized by
/// LlamaCore before utilizing. The `run` function will fail if not delegate called.
contract LlamaDeployTokenGovernorWithRole is LlamaBaseScript {
  LlamaTokenVotingFactory public immutable FACTORY;

  constructor(LlamaTokenVotingFactory factory) LlamaBaseScript() {
    FACTORY = factory;
  }

  /// @notice Deploys a new Llama token voting module, and mints a policy with a new role the role to the
  /// LlamaTokenGovernor.
  /// @dev This is a script that can only be used via delegatecall, which means it must be authorized by LlamaCore
  /// before invoking this method.
  /// @param tokenVotingConfig The configuration of the new Llama token voting module.
  /// @param description The description of the role to be minted.
  function run(LlamaTokenVotingConfig calldata tokenVotingConfig, RoleDescription description) public onlyDelegateCall {
    LlamaTokenGovernor governor = FACTORY.deploy(tokenVotingConfig);
    ILlamaCore llamaCore = ILlamaExecutor(address(this)).LLAMA_CORE();
    ILlamaPolicy policy = llamaCore.policy();
    policy.initializeRole(description);
    policy.setRoleHolder(policy.numRoles(), address(governor), 1, type(uint64).max);
  }
}

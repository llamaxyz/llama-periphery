// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {CasterConfig, LlamaTokenVotingConfig} from "src/lib/Structs.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {LlamaTokenActionCreator} from "src/token-voting/LlamaTokenActionCreator.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";

/// @title LlamaTokenVotingFactory
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract enables Llama instances to deploy a token voting module.
contract LlamaTokenVotingFactory {
  // ========================
  // ======== Errors ========
  // ========================

  /// @dev Thrown when a token adapter has been incorrectly configured.
  error InvalidTokenAdapterConfig();

  // ========================
  // ======== Events ========
  // ========================

  /// @dev Emitted when a new Llama token voting module is created.
  event LlamaTokenVotingInstanceCreated(
    address indexed deployer,
    ILlamaCore indexed llamaCore,
    address indexed token,
    ILlamaTokenAdapter tokenAdapterLogic,
    ILlamaTokenAdapter tokenAdapter,
    uint256 nonce,
    uint8 actionCreatorRole,
    uint8 casterRole,
    LlamaTokenActionCreator llamaTokenActionCreator,
    LlamaTokenCaster llamaTokenCaster,
    uint256 chainId
  );

  // =================================================
  // ======== Constants and Storage Variables ========
  // =================================================

  /// @notice The Token Action Creator implementation (logic) contract.
  LlamaTokenActionCreator public immutable LLAMA_TOKEN_ACTION_CREATOR_LOGIC;

  /// @notice The Token Caster implementation (logic) contract.
  LlamaTokenCaster public immutable LLAMA_TOKEN_CASTER_LOGIC;

  /// @dev Set the logic contracts used to deploy Token Voting modules.
  constructor(LlamaTokenActionCreator LlamaTokenActionCreatorLogic, LlamaTokenCaster LlamaTokenCasterLogic) {
    LLAMA_TOKEN_ACTION_CREATOR_LOGIC = LlamaTokenActionCreatorLogic;
    LLAMA_TOKEN_CASTER_LOGIC = LlamaTokenCasterLogic;
  }

  /// @notice Deploys a new Llama token voting module.
  /// @param tokenVotingConfig The configuration of the new Llama token voting module.
  /// @return actionCreator The address of the `LlamaTokenActionCreator` of the deployed token voting module.
  /// @return caster The address of the `LlamaTokenCaster` of the deployed token voting module.
  function deploy(LlamaTokenVotingConfig memory tokenVotingConfig)
    external
    returns (LlamaTokenActionCreator actionCreator, LlamaTokenCaster caster)
  {
    bytes32 salt = keccak256(
      abi.encodePacked(
        msg.sender, address(tokenVotingConfig.llamaCore), tokenVotingConfig.token, tokenVotingConfig.nonce
      )
    );

    // If the voting token is the default token voting type, then the tokenAdapter is optional and can be set to the
    // zero address
    ILlamaTokenAdapter tokenAdapter;
    if (address(tokenVotingConfig.tokenAdapterLogic) != address(0)) {
      // Deploy and initialize token adapter based on provided logic address and config
      tokenAdapter = ILlamaTokenAdapter(Clones.cloneDeterministic(address(tokenVotingConfig.tokenAdapterLogic), salt));
      tokenAdapter.initialize(tokenVotingConfig.adapterConfig);

      // Check to see if token adapter was correctly initialized
      if (address(tokenAdapter.token()) == address(0)) revert InvalidTokenAdapterConfig();
      if ((address(tokenAdapter.token()) != tokenVotingConfig.token)) revert InvalidTokenAdapterConfig();
      if (tokenAdapter.timestampToTimepoint(block.timestamp) == 0) revert InvalidTokenAdapterConfig();
      if (tokenAdapter.clock() == 0) revert InvalidTokenAdapterConfig();

      // Reverts if clock is inconsistent
      tokenAdapter.checkIfInconsistentClock();
    }

    // Deploy and initialize `LlamaTokenActionCreator` contract
    actionCreator = LlamaTokenActionCreator(Clones.cloneDeterministic(address(LLAMA_TOKEN_ACTION_CREATOR_LOGIC), salt));

    actionCreator.initialize(
      tokenVotingConfig.llamaCore,
      tokenVotingConfig.token,
      tokenAdapter,
      tokenVotingConfig.actionCreatorRole,
      tokenVotingConfig.creationThreshold
    );

    // Deploy and initialize `LlamaTokenCaster` contract
    caster = LlamaTokenCaster(Clones.cloneDeterministic(address(LLAMA_TOKEN_CASTER_LOGIC), salt));

    caster.initialize(
      tokenVotingConfig.llamaCore,
      tokenVotingConfig.token,
      tokenAdapter,
      tokenVotingConfig.casterRole,
      tokenVotingConfig.casterConfig
    );

    emit LlamaTokenVotingInstanceCreated(
      msg.sender,
      tokenVotingConfig.llamaCore,
      tokenVotingConfig.token,
      tokenVotingConfig.tokenAdapterLogic,
      tokenAdapter,
      tokenVotingConfig.nonce,
      tokenVotingConfig.actionCreatorRole,
      tokenVotingConfig.casterRole,
      actionCreator,
      caster,
      block.chainid
    );
  }
}

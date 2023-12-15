// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {LlamaTokenActionCreator} from "src/token-voting/LlamaTokenActionCreator.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";

/// @title LlamaTokenVotingFactory
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract enables Llama instances to deploy a token voting module.
contract LlamaTokenVotingFactory {
  // =========================
  // ======== Structs ========
  // =========================

  /// @dev Configuration of a new Llama token voting module.
  struct LlamaTokenVotingConfig {
    ILlamaCore llamaCore; // The address of the Llama core.
    ILlamaTokenAdapter tokenAdapterLogic; // The logic contract of the token adapter.
    bytes adapterConfig; // The configuration of the token adapter.
    uint256 nonce; // The nonce to be used in the salt of the deterministic deployment.
    uint8 actionCreatorRole; // The role required by the `LlamaTokenActionCreator` to create an action.
    uint8 casterRole; // The role required by the `LlamaTokenCaster` to cast approvals and disapprovals.
    uint256 creationThreshold; // The number of tokens required to create an action.
    uint16 voteQuorumPct; // The minimum percentage of tokens required to approve an action.
    uint16 vetoQuorumPct; // The minimum percentage of tokens required to disapprove an action.
  }

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
    // Initialize token adapter based on provided logic address and config
    ILlamaTokenAdapter tokenAdapter = ILlamaTokenAdapter(
      Clones.cloneDeterministic(
        address(tokenVotingConfig.tokenAdapterLogic), keccak256(tokenVotingConfig.adapterConfig)
      )
    );
    tokenAdapter.initialize(tokenVotingConfig.adapterConfig);

    // Check to see if token adapter was correctly initialized
    if (address(tokenAdapter.token()) == address(0)) revert InvalidTokenAdapterConfig();
    if (tokenAdapter.timestampToTimepoint(block.timestamp) >= 0) revert InvalidTokenAdapterConfig();

    // Reverts if clock is inconsistent
    tokenAdapter.checkIfInconsistentClock();

    // Deploy and initialize `LlamaTokenActionCreator` contract
    actionCreator = LlamaTokenActionCreator(
      Clones.cloneDeterministic(
        address(LLAMA_TOKEN_ACTION_CREATOR_LOGIC),
        keccak256(
          abi.encodePacked(
            msg.sender, address(tokenVotingConfig.llamaCore), address(tokenAdapter), tokenVotingConfig.nonce
          )
        )
      )
    );

    actionCreator.initialize(
      tokenVotingConfig.llamaCore,
      tokenAdapter,
      tokenVotingConfig.actionCreatorRole,
      tokenVotingConfig.creationThreshold
    );

    // Deploy and initialize `LlamaTokenCaster` contract
    caster = LlamaTokenCaster(
      Clones.cloneDeterministic(
        address(LLAMA_TOKEN_CASTER_LOGIC),
        keccak256(
          abi.encodePacked(
            msg.sender, address(tokenVotingConfig.llamaCore), address(tokenAdapter), tokenVotingConfig.nonce
          )
        )
      )
    );

    caster.initialize(
      tokenVotingConfig.llamaCore,
      tokenAdapter,
      tokenVotingConfig.casterRole,
      tokenVotingConfig.voteQuorumPct,
      tokenVotingConfig.vetoQuorumPct
    );

    emit LlamaTokenVotingInstanceCreated(
      msg.sender,
      tokenVotingConfig.llamaCore,
      tokenAdapter.token(),
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {LlamaERC20TokenActionCreator} from "src/token-voting/LlamaERC20TokenActionCreator.sol";
import {LlamaERC20TokenCaster} from "src/token-voting/LlamaERC20TokenCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";
import {LlamaERC721TokenActionCreator} from "src/token-voting/LlamaERC721TokenActionCreator.sol";
import {LlamaERC721TokenCaster} from "src/token-voting/LlamaERC721TokenCaster.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";

/// @title LlamaTokenVotingFactory
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets llama instances deploy a token voting module in a single llama action.
contract LlamaTokenVotingFactory {
  error NoModulesDeployed();

  event LlamaERC20TokenActionCreatorCreated(address actionCreator, address indexed token);
  event LlamaERC721TokenActionCreatorCreated(address actionCreator, address indexed token);
  event LlamaERC20TokenCasterCreated(
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
  );
  event LlamaERC721TokenCasterCreated(
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
  );

  /// @notice The ERC20 Tokenholder Action Creator (logic) contract.
  LlamaERC20TokenActionCreator public immutable ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC20 Tokenholder Caster (logic) contract.
  LlamaERC20TokenCaster public immutable ERC20_TOKENHOLDER_CASTER_LOGIC;

  /// @notice The ERC721 Tokenholder Action Creator (logic) contract.
  LlamaERC721TokenActionCreator public immutable ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC721 Tokenholder Caster (logic) contract.
  LlamaERC721TokenCaster public immutable ERC721_TOKENHOLDER_CASTER_LOGIC;

  /// @dev Set the logic contracts used to deploy Token Voting modules.
  constructor(
    LlamaERC20TokenActionCreator llamaERC20TokenActionCreatorLogic,
    LlamaERC20TokenCaster llamaERC20TokenCasterLogic,
    LlamaERC721TokenActionCreator llamaERC721TokenActionCreatorLogic,
    LlamaERC721TokenCaster llamaERC721TokenCasterLogic
  ) {
    ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC = llamaERC20TokenActionCreatorLogic;
    ERC20_TOKENHOLDER_CASTER_LOGIC = llamaERC20TokenCasterLogic;
    ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC = llamaERC721TokenActionCreatorLogic;
    ERC721_TOKENHOLDER_CASTER_LOGIC = llamaERC721TokenCasterLogic;
  }

  ///@notice Deploys a token voting module in a single function so it can be deployed in a single llama action.
  ///@dev This method CAN NOT be used in tandem with `delegateCallDeployTokenVotingModuleWithRoles`. You must use one or
  /// the other due to the delegateCallDeployTokenVotingModuleWithRoles method requring the contract to be authorized as
  /// a script.
  ///@param token The address of the token to be used for voting.
  ///@param isERC20 Whether the token is an ERC20 or ERC721.
  ///@param actionCreatorRole The role required by the LlamaTokenActionCreator to create an action.
  ///@param casterRole The role required by the LlamaTokenCaster to cast approvals and disapprovals.
  ///@param creationThreshold The number of tokens required to create an action (set to 0 if not deploying action
  /// creator).
  ///@param minApprovalPct The minimum percentage of tokens required to approve an action (set to 0 if not deploying
  /// caster).
  ///@param minDisapprovalPct The minimum percentage of tokens required to disapprove an action (set to 0 if not
  /// deploying caster).
  function deployTokenVotingModule(
    ILlamaCore llamaCore,
    address token,
    bool isERC20,
    uint8 actionCreatorRole,
    uint8 casterRole,
    uint256 creationThreshold,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) external returns (address actionCreator, address caster) {
    if (isERC20) {
      actionCreator =
        address(_deployLlamaERC20TokenActionCreator(ERC20Votes(token), llamaCore, actionCreatorRole, creationThreshold));
      caster = address(
        _deployLlamaERC20TokenCaster(ERC20Votes(token), llamaCore, casterRole, minApprovalPct, minDisapprovalPct)
      );
    } else {
      actionCreator = address(
        _deployLlamaERC721TokenActionCreator(ERC721Votes(token), llamaCore, actionCreatorRole, creationThreshold)
      );
      caster = address(
        _deployLlamaERC721TokenCaster(ERC721Votes(token), llamaCore, casterRole, minApprovalPct, minDisapprovalPct)
      );
    }
  }

  // ====================================
  // ======== Internal Functions ========
  // ====================================

  function _deployLlamaERC20TokenActionCreator(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 creationThreshold
  ) internal returns (LlamaERC20TokenActionCreator actionCreator) {
    actionCreator = LlamaERC20TokenActionCreator(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, role, creationThreshold);
    emit LlamaERC20TokenActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployLlamaERC721TokenActionCreator(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 creationThreshold
  ) internal returns (LlamaERC721TokenActionCreator actionCreator) {
    actionCreator = LlamaERC721TokenActionCreator(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, role, creationThreshold);
    emit LlamaERC721TokenActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployLlamaERC20TokenCaster(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) internal returns (LlamaERC20TokenCaster caster) {
    caster = LlamaERC20TokenCaster(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
    emit LlamaERC20TokenCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
  }

  function _deployLlamaERC721TokenCaster(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) internal returns (LlamaERC721TokenCaster caster) {
    caster = LlamaERC721TokenCaster(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
    emit LlamaERC721TokenCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
  }
}

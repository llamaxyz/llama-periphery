// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {LlamaERC20TokenHolderActionCreator} from "src/token-voting/LlamaERC20TokenHolderActionCreator.sol";
import {LlamaERC20TokenHolderCaster} from "src/token-voting/LlamaERC20TokenHolderCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";
import {LlamaERC721TokenHolderActionCreator} from "src/token-voting/LlamaERC721TokenHolderActionCreator.sol";
import {LlamaERC721TokenHolderCaster} from "src/token-voting/LlamaERC721TokenHolderCaster.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";

/// @title LlamaTokenVotingFactory
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets llama instances deploy a token voting module in a single llama action.
contract LlamaTokenVotingFactory {
  error NoModulesDeployed();

  event LlamaERC20TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event LlamaERC721TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event LlamaERC20TokenHolderCasterCreated(
    address caster, address indexed token, uint256 voteQuorumPct, uint256 vetoQuorumPct
  );
  event LlamaERC721TokenHolderCasterCreated(
    address caster, address indexed token, uint256 voteQuorumPct, uint256 vetoQuorumPct
  );

  /// @notice The ERC20 Tokenholder Action Creator (logic) contract.
  LlamaERC20TokenHolderActionCreator public immutable ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC20 Tokenholder Caster (logic) contract.
  LlamaERC20TokenHolderCaster public immutable ERC20_TOKENHOLDER_CASTER_LOGIC;

  /// @notice The ERC721 Tokenholder Action Creator (logic) contract.
  LlamaERC721TokenHolderActionCreator public immutable ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC721 Tokenholder Caster (logic) contract.
  LlamaERC721TokenHolderCaster public immutable ERC721_TOKENHOLDER_CASTER_LOGIC;

  /// @dev Set the logic contracts used to deploy Token Voting modules.
  constructor(
    LlamaERC20TokenHolderActionCreator llamaERC20TokenHolderActionCreatorLogic,
    LlamaERC20TokenHolderCaster llamaERC20TokenHolderCasterLogic,
    LlamaERC721TokenHolderActionCreator llamaERC721TokenHolderActionCreatorLogic,
    LlamaERC721TokenHolderCaster llamaERC721TokenHolderCasterLogic
  ) {
    ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC = llamaERC20TokenHolderActionCreatorLogic;
    ERC20_TOKENHOLDER_CASTER_LOGIC = llamaERC20TokenHolderCasterLogic;
    ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC = llamaERC721TokenHolderActionCreatorLogic;
    ERC721_TOKENHOLDER_CASTER_LOGIC = llamaERC721TokenHolderCasterLogic;
  }

  ///@notice Deploys a token voting module in a single function so it can be deployed in a llama action.
  ///@param token The address of the token to be used for voting.
  ///@param isERC20 Whether the token is an ERC20 or ERC721.
  ///@param actionCreatorRole The role required by the `LlamaTokenHolderActionCreator` to create an action.
  ///@param casterRole The role required by the `LlamaTokenHolderCaster` to cast approvals and disapprovals.
  ///@param creationThreshold The number of tokens required to create an action
  ///@param voteQuorumPct The minimum percentage of tokens required to approve an action
  ///@param vetoQuorumPct The minimum percentage of tokens required to disapprove an action
  function deployTokenVotingModule(
    ILlamaCore llamaCore,
    address token,
    bool isERC20,
    uint8 actionCreatorRole,
    uint8 casterRole,
    uint256 creationThreshold,
    uint256 voteQuorumPct,
    uint256 vetoQuorumPct
  ) external returns (address actionCreator, address caster) {
    if (isERC20) {
      actionCreator = address(
        _deployLlamaERC20TokenHolderActionCreator(ERC20Votes(token), llamaCore, actionCreatorRole, creationThreshold)
      );
      caster = address(
        _deployLlamaERC20TokenHolderCaster(ERC20Votes(token), llamaCore, casterRole, voteQuorumPct, vetoQuorumPct)
      );
    } else {
      actionCreator = address(
        _deployLlamaERC721TokenHolderActionCreator(ERC721Votes(token), llamaCore, actionCreatorRole, creationThreshold)
      );
      caster = address(
        _deployLlamaERC721TokenHolderCaster(ERC721Votes(token), llamaCore, casterRole, voteQuorumPct, vetoQuorumPct)
      );
    }
  }

  // ====================================
  // ======== Internal Functions ========
  // ====================================

  function _deployLlamaERC20TokenHolderActionCreator(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 creationThreshold
  ) internal returns (LlamaERC20TokenHolderActionCreator actionCreator) {
    actionCreator = LlamaERC20TokenHolderActionCreator(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, role, creationThreshold);
    emit LlamaERC20TokenHolderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployLlamaERC721TokenHolderActionCreator(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 creationThreshold
  ) internal returns (LlamaERC721TokenHolderActionCreator actionCreator) {
    actionCreator = LlamaERC721TokenHolderActionCreator(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, role, creationThreshold);
    emit LlamaERC721TokenHolderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployLlamaERC20TokenHolderCaster(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 voteQuorumPct,
    uint256 vetoQuorumPct
  ) internal returns (LlamaERC20TokenHolderCaster caster) {
    caster = LlamaERC20TokenHolderCaster(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, voteQuorumPct, vetoQuorumPct);
    emit LlamaERC20TokenHolderCasterCreated(address(caster), address(token), voteQuorumPct, vetoQuorumPct);
  }

  function _deployLlamaERC721TokenHolderCaster(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 voteQuorumPct,
    uint256 vetoQuorumPct
  ) internal returns (LlamaERC721TokenHolderCaster caster) {
    caster = LlamaERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, voteQuorumPct, vetoQuorumPct);
    emit LlamaERC721TokenHolderCasterCreated(address(caster), address(token), voteQuorumPct, vetoQuorumPct);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {ERC20TokenholderCaster} from "src/token-voting/ERC20TokenholderCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {ERC721TokenholderCaster} from "src/token-voting/ERC721TokenholderCaster.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";

/// @title LlamaTokenVotingFactory
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets llama instances deploy a token voting module in a single llama action.
contract LlamaTokenVotingFactory {
  error NoModulesDeployed();

  event ERC20TokenholderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC721TokenholderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC20TokenholderCasterCreated(
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
  );
  event ERC721TokenholderCasterCreated(
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
  );

  /// @notice The ERC20 Tokenholder Action Creator (logic) contract.
  ERC20TokenholderActionCreator public immutable ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC20 Tokenholder Caster (logic) contract.
  ERC20TokenholderCaster public immutable ERC20_TOKENHOLDER_CASTER_LOGIC;

  /// @notice The ERC721 Tokenholder Action Creator (logic) contract.
  ERC721TokenholderActionCreator public immutable ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC721 Tokenholder Caster (logic) contract.
  ERC721TokenholderCaster public immutable ERC721_TOKENHOLDER_CASTER_LOGIC;

  /// @dev Set the logic contracts used to deploy Token Voting modules.
  constructor(
    ERC20TokenholderActionCreator erc20TokenholderActionCreatorLogic,
    ERC20TokenholderCaster erc20TokenholderCasterLogic,
    ERC721TokenholderActionCreator erc721TokenholderActionCreatorLogic,
    ERC721TokenholderCaster erc721TokenholderCasterLogic
  ) {
    ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC = erc20TokenholderActionCreatorLogic;
    ERC20_TOKENHOLDER_CASTER_LOGIC = erc20TokenholderCasterLogic;
    ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC = erc721TokenholderActionCreatorLogic;
    ERC721_TOKENHOLDER_CASTER_LOGIC = erc721TokenholderCasterLogic;
  }

  ///@notice Deploys a token voting module in a single function so it can be deployed in a single llama action.
  ///@dev This method CAN NOT be used in tandem with `delegateCallDeployTokenVotingModuleWithRoles`. You must use one or
  /// the other due to the delegateCallDeployTokenVotingModuleWithRoles method requring the contract to be authorized as
  /// a script.
  ///@param token The address of the token to be used for voting.
  ///@param isERC20 Whether the token is an ERC20 or ERC721.
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
    uint256 creationThreshold,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) external returns (address actionCreator, address caster) {
    if (isERC20) {
      actionCreator = address(_deployERC20TokenholderActionCreator(ERC20Votes(token), llamaCore, creationThreshold));
      caster =
        address(_deployERC20TokenholderCaster(ERC20Votes(token), llamaCore, 0, minApprovalPct, minDisapprovalPct));
    } else {
      actionCreator = address(_deployERC721TokenholderActionCreator(ERC721Votes(token), llamaCore, creationThreshold));
      caster =
        address(_deployERC721TokenholderCaster(ERC721Votes(token), llamaCore, 0, minApprovalPct, minDisapprovalPct));
    }
  }

  // ====================================
  // ======== Internal Functions ========
  // ====================================

  function _deployERC20TokenholderActionCreator(ERC20Votes token, ILlamaCore llamaCore, uint256 creationThreshold)
    internal
    returns (ERC20TokenholderActionCreator actionCreator)
  {
    actionCreator = ERC20TokenholderActionCreator(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, creationThreshold);
    emit ERC20TokenholderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployERC721TokenholderActionCreator(ERC721Votes token, ILlamaCore llamaCore, uint256 creationThreshold)
    internal
    returns (ERC721TokenholderActionCreator actionCreator)
  {
    actionCreator = ERC721TokenholderActionCreator(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, creationThreshold);
    emit ERC721TokenholderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployERC20TokenholderCaster(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) internal returns (ERC20TokenholderCaster caster) {
    caster = ERC20TokenholderCaster(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
    emit ERC20TokenholderCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
  }

  function _deployERC721TokenholderCaster(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) internal returns (ERC721TokenholderCaster caster) {
    caster = ERC721TokenholderCaster(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
    emit ERC721TokenholderCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
  }
}

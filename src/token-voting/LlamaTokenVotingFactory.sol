// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ERC20TokenHolderActionCreator} from "src/token-voting/ERC20TokenHolderActionCreator.sol";
import {ERC20TokenHolderCaster} from "src/token-voting/ERC20TokenHolderCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";
import {ERC721TokenHolderActionCreator} from "src/token-voting/ERC721TokenHolderActionCreator.sol";
import {ERC721TokenHolderCaster} from "src/token-voting/ERC721TokenHolderCaster.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";

/// @title LlamaTokenVotingFactory
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets llama instances deploy a token voting module in a single llama action.
contract LlamaTokenVotingFactory {
  error NoModulesDeployed();

  event ERC20TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC721TokenHolderActionCreatorCreated(address actionCreator, address indexed token);
  event ERC20TokenHolderCasterCreated(address caster, address indexed token, uint256 voteQuorum, uint256 vetoQuorum);
  event ERC721TokenHolderCasterCreated(address caster, address indexed token, uint256 voteQuorum, uint256 vetoQuorum);

  /// @notice The ERC20 TokenHolder Action Creator (logic) contract.
  ERC20TokenHolderActionCreator public immutable ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC20 TokenHolder Caster (logic) contract.
  ERC20TokenHolderCaster public immutable ERC20_TOKENHOLDER_CASTER_LOGIC;

  /// @notice The ERC721 TokenHolder Action Creator (logic) contract.
  ERC721TokenHolderActionCreator public immutable ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC;

  /// @notice The ERC721 TokenHolder Caster (logic) contract.
  ERC721TokenHolderCaster public immutable ERC721_TOKENHOLDER_CASTER_LOGIC;

  /// @dev Set the logic contracts used to deploy Token Voting modules.
  constructor(
    ERC20TokenHolderActionCreator erc20TokenHolderActionCreatorLogic,
    ERC20TokenHolderCaster erc20TokenHolderCasterLogic,
    ERC721TokenHolderActionCreator erc721TokenHolderActionCreatorLogic,
    ERC721TokenHolderCaster erc721TokenHolderCasterLogic
  ) {
    ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC = erc20TokenHolderActionCreatorLogic;
    ERC20_TOKENHOLDER_CASTER_LOGIC = erc20TokenHolderCasterLogic;
    ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC = erc721TokenHolderActionCreatorLogic;
    ERC721_TOKENHOLDER_CASTER_LOGIC = erc721TokenHolderCasterLogic;
  }

  ///@notice Deploys a token voting module in a single function so it can be deployed in a single llama action.
  ///@dev This method CAN NOT be used in tandem with `delegateCallDeployTokenVotingModuleWithRoles`. You must use one or
  /// the other due to the delegateCallDeployTokenVotingModuleWithRoles method requring the contract to be authorized as
  /// a script.
  ///@param token The address of the token to be used for voting.
  ///@param isERC20 Whether the token is an ERC20 or ERC721.
  ///@param actionCreatorRole The role required by the TokenHolderActionCreator to create an action.
  ///@param casterRole The role required by the TokenHolderCaster to cast approvals and disapprovals.
  ///@param creationThreshold The number of tokens required to create an action (set to 0 if not deploying action
  /// creator).
  ///@param voteQuorum The minimum percentage of tokens required to approve an action (set to 0 if not deploying
  /// caster).
  ///@param vetoQuorum The minimum percentage of tokens required to disapprove an action (set to 0 if not
  /// deploying caster).
  function deployTokenVotingModule(
    ILlamaCore llamaCore,
    address token,
    bool isERC20,
    uint8 actionCreatorRole,
    uint8 casterRole,
    uint256 creationThreshold,
    uint256 voteQuorum,
    uint256 vetoQuorum
  ) external returns (address actionCreator, address caster) {
    if (isERC20) {
      actionCreator = address(
        _deployERC20TokenHolderActionCreator(ERC20Votes(token), llamaCore, actionCreatorRole, creationThreshold)
      );
      caster = address(_deployERC20TokenHolderCaster(ERC20Votes(token), llamaCore, casterRole, voteQuorum, vetoQuorum));
    } else {
      actionCreator = address(
        _deployERC721TokenHolderActionCreator(ERC721Votes(token), llamaCore, actionCreatorRole, creationThreshold)
      );
      caster =
        address(_deployERC721TokenHolderCaster(ERC721Votes(token), llamaCore, casterRole, voteQuorum, vetoQuorum));
    }
  }

  // ====================================
  // ======== Internal Functions ========
  // ====================================

  function _deployERC20TokenHolderActionCreator(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 creationThreshold
  ) internal returns (ERC20TokenHolderActionCreator actionCreator) {
    actionCreator = ERC20TokenHolderActionCreator(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, role, creationThreshold);
    emit ERC20TokenHolderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployERC721TokenHolderActionCreator(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 creationThreshold
  ) internal returns (ERC721TokenHolderActionCreator actionCreator) {
    actionCreator = ERC721TokenHolderActionCreator(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, role, creationThreshold);
    emit ERC721TokenHolderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployERC20TokenHolderCaster(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 voteQuorum,
    uint256 vetoQuorum
  ) internal returns (ERC20TokenHolderCaster caster) {
    caster = ERC20TokenHolderCaster(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, voteQuorum, vetoQuorum);
    emit ERC20TokenHolderCasterCreated(address(caster), address(token), voteQuorum, vetoQuorum);
  }

  function _deployERC721TokenHolderCaster(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 voteQuorum,
    uint256 vetoQuorum
  ) internal returns (ERC721TokenHolderCaster caster) {
    caster = ERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, voteQuorum, vetoQuorum);
    emit ERC721TokenHolderCasterCreated(address(caster), address(token), voteQuorum, vetoQuorum);
  }
}

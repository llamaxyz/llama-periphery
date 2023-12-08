// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";
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
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
  );
  event LlamaERC721TokenHolderCasterCreated(
    address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
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
    LlamaERC20TokenHolderActionCreator erc20LlamaTokenHolderActionCreatorLogic,
    LlamaERC20TokenHolderCaster erc20LlamaTokenHolderCasterLogic,
    LlamaERC721TokenHolderActionCreator erc721LlamaTokenHolderActionCreatorLogic,
    LlamaERC721TokenHolderCaster erc721LlamaTokenHolderCasterLogic
  ) {
    ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC = erc20LlamaTokenHolderActionCreatorLogic;
    ERC20_TOKENHOLDER_CASTER_LOGIC = erc20LlamaTokenHolderCasterLogic;
    ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC = erc721LlamaTokenHolderActionCreatorLogic;
    ERC721_TOKENHOLDER_CASTER_LOGIC = erc721LlamaTokenHolderCasterLogic;
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
    address token,
    bool isERC20,
    uint256 creationThreshold,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) external returns (address actionCreator, address caster) {
    ILlamaCore core = ILlamaCore(ILlamaExecutor(msg.sender).LLAMA_CORE());
    if (isERC20) {
      actionCreator = address(_deployLlamaERC20TokenHolderActionCreator(ERC20Votes(token), core, creationThreshold));
      caster =
        address(_deployLlamaERC20TokenHolderCaster(ERC20Votes(token), core, 0, minApprovalPct, minDisapprovalPct));
    } else {
      actionCreator = address(_deployLlamaERC721TokenHolderActionCreator(ERC721Votes(token), core, creationThreshold));
      caster =
        address(_deployLlamaERC721TokenHolderCaster(ERC721Votes(token), core, 0, minApprovalPct, minDisapprovalPct));
    }
  }

  // ====================================
  // ======== Internal Functions ========
  // ====================================

  function _deployLlamaERC20TokenHolderActionCreator(ERC20Votes token, ILlamaCore llamaCore, uint256 creationThreshold)
    internal
    returns (LlamaERC20TokenHolderActionCreator actionCreator)
  {
    actionCreator = LlamaERC20TokenHolderActionCreator(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, creationThreshold);
    emit LlamaERC20TokenHolderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployLlamaERC721TokenHolderActionCreator(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint256 creationThreshold
  ) internal returns (LlamaERC721TokenHolderActionCreator actionCreator) {
    actionCreator = LlamaERC721TokenHolderActionCreator(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_ACTION_CREATOR_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    actionCreator.initialize(token, llamaCore, creationThreshold);
    emit LlamaERC721TokenHolderActionCreatorCreated(address(actionCreator), address(token));
  }

  function _deployLlamaERC20TokenHolderCaster(
    ERC20Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) internal returns (LlamaERC20TokenHolderCaster caster) {
    caster = LlamaERC20TokenHolderCaster(
      Clones.cloneDeterministic(
        address(ERC20_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
    emit LlamaERC20TokenHolderCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
  }

  function _deployLlamaERC721TokenHolderCaster(
    ERC721Votes token,
    ILlamaCore llamaCore,
    uint8 role,
    uint256 minApprovalPct,
    uint256 minDisapprovalPct
  ) internal returns (LlamaERC721TokenHolderCaster caster) {
    caster = LlamaERC721TokenHolderCaster(
      Clones.cloneDeterministic(
        address(ERC721_TOKENHOLDER_CASTER_LOGIC), keccak256(abi.encodePacked(address(token), msg.sender))
      )
    );
    caster.initialize(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
    emit LlamaERC721TokenHolderCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
  }
}

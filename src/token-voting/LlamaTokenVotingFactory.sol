// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";
import {RoleDescription} from "src/lib/UDVTs.sol";
import {ERC20TokenholderActionCreator} from "src/token-voting/ERC20TokenholderActionCreator.sol";
import {ERC20TokenholderCaster} from "src/token-voting/ERC20TokenholderCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";
import {ERC721TokenholderActionCreator} from "src/token-voting/ERC721TokenholderActionCreator.sol";
import {ERC721TokenholderCaster} from "src/token-voting/ERC721TokenholderCaster.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";
import {LlamaBaseScript} from "src/llama-scripts/LlamaBaseScript.sol";

/// @title LlamaTokenVotingFactory
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets llama instances deploy a token voting module in a single llama action.
contract LlamaTokenVotingFactory is LlamaBaseScript {
    error NoModulesDeployed();

    event ERC20TokenholderActionCreatorCreated(address actionCreator, address indexed token);
    event ERC721TokenholderActionCreatorCreated(address actionCreator, address indexed token);
    event ERC20TokenholderCasterCreated(
        address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
    );
    event ERC721TokenholderCasterCreated(
        address caster, address indexed token, uint256 minApprovalPct, uint256 minDisapprovalPct
    );

    ///@notice Deploys a token voting module in a single function so it can be deployed in a single llama action.
    ///@dev This method CAN NOT be used in tandem with `delegateCallDeployTokenVotingModuleWithRoles`. You must use one or
    /// the other due to the delegateCallDeployTokenVotingModuleWithRoles method requring the contract to be authorized as
    /// a script.
    ///@param token The address of the token to be used for voting.
    ///@param isERC20 Whether the token is an ERC20 or ERC721.
    ///@param deployActionCreator Whether to deploy the action creator.
    ///@param deployCaster Whether to deploy the caster.
    ///@param creationThreshold The number of tokens required to create an action (set to 0 if not deploying action
    /// creator).
    ///@param minApprovalPct The minimum percentage of tokens required to approve an action (set to 0 if not deploying
    /// caster).
    ///@param minDisapprovalPct The minimum percentage of tokens required to disapprove an action (set to 0 if not
    /// deploying caster).
    function deployTokenVotingModule(
        address token,
        bool isERC20,
        bool deployActionCreator,
        bool deployCaster,
        uint256 creationThreshold,
        uint256 minApprovalPct,
        uint256 minDisapprovalPct
    ) public returns (address, address) {
        return _deployTokenVotingModule(
            ILlamaExecutor(msg.sender),
            token,
            isERC20,
            deployActionCreator,
            deployCaster,
            creationThreshold,
            minApprovalPct,
            minDisapprovalPct
        );
    }

    ///@notice A llama script that deploys a token voting module and inittializes/issues roles to the token voting action
    /// creator and caster in a single function so it can be deployed in a single llama action.
    ///@dev This contract must be authorized as a script in the core contract before it can be used (invoke the
    /// `LlamaCore::setScriptAuthorization` function to authorize).
    ///@dev This method CAN NOT be used in tandem with `deployTokenVotingModule`. You must use one or the other due to
    /// this method requring the contract to be authorized as a script.
    ///@param token The address of the token to be used for voting.
    ///@param isERC20 Whether the token is an ERC20 or ERC721.
    ///@param deployActionCreator Whether to deploy the action creator.
    ///@param deployCaster Whether to deploy the caster.
    ///@param creationThreshold The number of tokens required to create an action (set to 0 if not deploying action
    /// creator).
    ///@param minApprovalPct The minimum percentage of tokens required to approve an action (set to 0 if not deploying
    /// caster).
    ///@param minDisapprovalPct The minimum percentage of tokens required to disapprove an action (set to 0 if not
    /// deploying caster).
    function delegateCallDeployTokenVotingModuleWithRoles(
        address token,
        bool isERC20,
        bool deployActionCreator,
        bool deployCaster,
        uint256 creationThreshold,
        uint256 minApprovalPct,
        uint256 minDisapprovalPct
    ) public onlyDelegateCall {
        (address actionCreator, address caster) = _deployTokenVotingModule(
            ILlamaExecutor(address(this)),
            token,
            isERC20,
            deployActionCreator,
            deployCaster,
            creationThreshold,
            minApprovalPct,
            minDisapprovalPct
        );

        ILlamaExecutor executor = ILlamaExecutor(address(this));
        ILlamaCore core = ILlamaCore(executor.LLAMA_CORE());
        ILlamaPolicy policy = ILlamaPolicy(core.policy());
        uint8 numRoles = policy.numRoles();
        string memory name;
        isERC20 ? name = ERC20Votes(token).name() : name = ERC721Votes(token).name();
        if (actionCreator != address(0)) {
            policy.initializeRole(RoleDescription.wrap(bytes32(abi.encodePacked("Action Creator Role: ", name))));
            policy.setRoleHolder(numRoles + 1, actionCreator, 1, type(uint64).max);
        }
        if (caster != address(0)) {
            policy.initializeRole(RoleDescription.wrap(bytes32(abi.encodePacked("Caster Role: ", name))));
            policy.setRoleHolder(actionCreator == address(0) ? numRoles + 1 : numRoles + 2, caster, 1, type(uint64).max);
        }
    }

    // ====================================
    // ======== Internal Functions ========
    // ====================================

    function _deployTokenVotingModule(
        ILlamaExecutor executor,
        address token,
        bool isERC20,
        bool deployActionCreator,
        bool deployCaster,
        uint256 creationThreshold,
        uint256 minApprovalPct,
        uint256 minDisapprovalPct
    ) internal returns (address actionCreator, address caster) {
        if (!deployActionCreator && !deployCaster) revert NoModulesDeployed();
        ILlamaCore core = ILlamaCore(executor.LLAMA_CORE());
        if (isERC20) {
            if (deployActionCreator) {
                actionCreator =
                    address(_deployERC20TokenholderActionCreator(ERC20Votes(token), core, creationThreshold));
            }
            if (deployCaster) {
                caster = address(
                    _deployERC20TokenholderCaster(ERC20Votes(token), core, 0, minApprovalPct, minDisapprovalPct)
                );
            }
        } else {
            if (deployActionCreator) {
                actionCreator =
                    address(_deployERC721TokenholderActionCreator(ERC721Votes(token), core, creationThreshold));
            }
            if (deployCaster) {
                caster = address(
                    _deployERC721TokenholderCaster(ERC721Votes(token), core, 0, minApprovalPct, minDisapprovalPct)
                );
            }
        }
    }

    function _deployERC20TokenholderActionCreator(ERC20Votes token, ILlamaCore llamaCore, uint256 creationThreshold)
        internal
        returns (ERC20TokenholderActionCreator actionCreator)
    {
        actionCreator = new ERC20TokenholderActionCreator(token, llamaCore, creationThreshold);
        emit ERC20TokenholderActionCreatorCreated(address(actionCreator), address(token));
    }

    function _deployERC721TokenholderActionCreator(ERC721Votes token, ILlamaCore llamaCore, uint256 creationThreshold)
        internal
        returns (ERC721TokenholderActionCreator actionCreator)
    {
        actionCreator = new ERC721TokenholderActionCreator(token, llamaCore, creationThreshold);
        emit ERC721TokenholderActionCreatorCreated(address(actionCreator), address(token));
    }

    function _deployERC20TokenholderCaster(
        ERC20Votes token,
        ILlamaCore llamaCore,
        uint8 role,
        uint256 minApprovalPct,
        uint256 minDisapprovalPct
    ) internal returns (ERC20TokenholderCaster caster) {
        caster = new ERC20TokenholderCaster(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
        emit ERC20TokenholderCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
    }

    function _deployERC721TokenholderCaster(
        ERC721Votes token,
        ILlamaCore llamaCore,
        uint8 role,
        uint256 minApprovalPct,
        uint256 minDisapprovalPct
    ) internal returns (ERC721TokenholderCaster caster) {
        caster = new ERC721TokenholderCaster(token, llamaCore, role, minApprovalPct, minDisapprovalPct);
        emit ERC721TokenholderCasterCreated(address(caster), address(token), minApprovalPct, minDisapprovalPct);
    }
}

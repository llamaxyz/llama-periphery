// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {LlamaTokenActionCreator} from "src/token-voting/LlamaTokenActionCreator.sol";
import {LlamaTokenVotingTimeManager} from "src/token-voting/time/LlamaTokenVotingTimeManager.sol";

/// @title LlamaERC20TokenActionCreator
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a specified `ERC20Votes` token create actions on a llama instance if their
/// token balance is greater than or equal to the creation threshold.
contract LlamaERC20TokenActionCreator is LlamaTokenActionCreator {
  ERC20Votes public token;

  /// @dev This contract is deployed as a minimal proxy from the factory's `deployTokenVotingModule` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC20TokenActionCreator` clone.
  /// @dev This function is called by the `deployTokenVotingModule` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _token The ERC20 token to be used for voting.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _creationThreshold The default number of tokens required to create an action. This must
  /// be in the same decimals as the token. For example, if the token has 18 decimals and you want a
  /// creation threshold of 1000 tokens, pass in 1000e18.
  function initialize(
    ERC20Votes _token,
    ILlamaCore _llamaCore,
    LlamaTokenVotingTimeManager _timeManager,
    uint8 _role,
    uint256 _creationThreshold
  ) external initializer {
    __initializeLlamaTokenActionCreatorMinimalProxy(_llamaCore, _timeManager, _role, _creationThreshold);
    token = _token;
    uint256 totalSupply = token.getPastTotalSupply(_timeManager.currentTimepointMinusOne());
    if (totalSupply == 0) revert InvalidTokenAddress();
    if (_creationThreshold > totalSupply) revert InvalidCreationThreshold();
  }

  function _getPastVotes(address account, uint256 timepoint) internal view virtual override returns (uint256) {
    return token.getPastVotes(account, timepoint);
  }

  function _getPastTotalSupply(uint256 timepoint) internal view virtual override returns (uint256) {
    return token.getPastTotalSupply(timepoint);
  }

  function _getClockMode() internal view virtual override returns (string memory) {
    return token.CLOCK_MODE();
  }
}
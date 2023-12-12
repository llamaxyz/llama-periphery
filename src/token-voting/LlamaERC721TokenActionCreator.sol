// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaTokenClockAdapter} from "src/interfaces/ILlamaTokenClockAdapter.sol";
import {LlamaTokenActionCreator} from "src/token-voting/LlamaTokenActionCreator.sol";

/// @title LlamaERC721TokenActionCreator
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance ERC721Votes token create actions on the llama instance if
/// they hold enough tokens.
contract LlamaERC721TokenActionCreator is LlamaTokenActionCreator {
  /// @notice The ERC721 token to be used for voting.
  ERC721Votes public token;

  /// @dev This contract is deployed as a minimal proxy from the factory's `deployTokenVotingModule` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC721TokenActionCreator` clone.
  /// @dev This function is called by the `deployTokenVotingModule` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _token The ERC721 token to be used for voting.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _creationThreshold The default number of tokens required to create an action. This must
  /// be in the same decimals as the token. For example, if the token has 18 decimals and you want a
  /// creation threshold of 1000 tokens, pass in 1000e18.
  function initialize(
    ERC721Votes _token,
    ILlamaCore _llamaCore,
    ILlamaTokenClockAdapter _clockAdapter,
    uint8 _role,
    uint256 _creationThreshold
  ) external initializer {
    __initializeLlamaTokenActionCreatorMinimalProxy(_llamaCore, _clockAdapter, _role, _creationThreshold);
    token = _token;
    if (!token.supportsInterface(type(IERC721).interfaceId)) revert InvalidTokenAddress();
    uint256 totalSupply = token.getPastTotalSupply(_currentTimepointMinusOne());
    if (totalSupply == 0) revert InvalidTokenAddress();
    if (_creationThreshold > totalSupply) revert InvalidCreationThreshold();
  }

  /// @inheritdoc LlamaTokenActionCreator
  function _getPastVotes(address account, uint256 timepoint) internal view virtual override returns (uint256) {
    return token.getPastVotes(account, timepoint);
  }

  /// @inheritdoc LlamaTokenActionCreator
  function _getPastTotalSupply(uint256 timepoint) internal view virtual override returns (uint256) {
    return token.getPastTotalSupply(timepoint);
  }

  /// @inheritdoc LlamaTokenActionCreator
  function _getClockMode() internal view virtual override returns (string memory) {
    return token.CLOCK_MODE();
  }
}

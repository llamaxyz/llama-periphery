// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaTokenClockAdapter} from "src/token-voting/ILlamaTokenClockAdapter.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";
/// @title LlamaERC721TokenCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance `ERC721Votes` token collectively cast an approval or
/// disapproval on created actions.

contract LlamaERC721TokenCaster is LlamaTokenCaster {
  /// @notice The ERC721 token to be used for voting.
  ERC721Votes public token;

  /// @dev This contract is deployed as a minimal proxy from the factory's `deploy` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC721TokenCaster` clone.
  /// @dev This function is called by the `deploy` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _token The ERC721 token to be used for voting.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _voteQuorumPct The minimum % of votes required to submit an approval to `LlamaCore`.
  /// @param _vetoQuorumPct The minimum % of vetoes required to submit a disapproval to `LlamaCore`.
  function initialize(
    ERC721Votes _token,
    ILlamaCore _llamaCore,
    ILlamaTokenClockAdapter _clockAdapter,
    uint8 _role,
    uint256 _voteQuorumPct,
    uint256 _vetoQuorumPct
  ) external initializer {
    __initializeLlamaTokenCasterMinimalProxy(_llamaCore, _clockAdapter, _role, _voteQuorumPct, _vetoQuorumPct);
    token = _token;
    if (!token.supportsInterface(type(IERC721).interfaceId)) revert InvalidTokenAddress();
    uint256 totalSupply = token.getPastTotalSupply(_currentTimepointMinusOne());
    if (totalSupply == 0) revert InvalidTokenAddress();
  }

  /// @inheritdoc LlamaTokenCaster
  function _getPastVotes(address account, uint48 timepoint) internal view virtual override returns (uint256) {
    return token.getPastVotes(account, timepoint);
  }

  /// @inheritdoc LlamaTokenCaster
  function _getPastTotalSupply(uint48 timepoint) internal view virtual override returns (uint256) {
    return token.getPastTotalSupply(timepoint);
  }

  /// @inheritdoc LlamaTokenCaster
  function _getClockMode() internal view virtual override returns (string memory clockmode) {
    if (address(clockAdapter) != address(0)) {
      clockmode = clockAdapter.CLOCK_MODE();
    } else {
      try token.CLOCK_MODE() returns (string memory mode) {
        clockmode = mode;
      } catch {
        clockmode = "mode=timestamp";
      }
    }
  }
}

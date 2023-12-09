// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {TokenHolderCaster} from "src/token-voting/TokenHolderCaster.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

/// @title ERC721TokenHolderCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance ERC721Votes token cast approvals and disapprovals
/// on created actions.
contract ERC721TokenholderCaster is TokenholderCaster {
  ERC721Votes public token;

  /// @dev This contract is deployed as a minimal proxy from the factory's `deployTokenVotingModule` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `ERC721TokenholderCaster` clone.
  /// @dev This function is called by the `deployTokenVotingModule` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _token The ERC721 token to be used for voting.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _voteQuorum The minimum % of approvals required to submit approvals to `LlamaCore`.
  /// @param _vetoQuorum The minimum % of disapprovals required to submit disapprovals to `LlamaCore`.
  function initialize(ERC721Votes _token, ILlamaCore _llamaCore, uint8 _role, uint256 _voteQuorum, uint256 _vetoQuorum)
    external
    initializer
  {
    __initializeTokenholderCasterMinimalProxy(_llamaCore, _role, _voteQuorum, _vetoQuorum);
    token = _token;
    if (!token.supportsInterface(type(IERC721).interfaceId)) revert InvalidTokenAddress();
  }

  function _getPastVotes(address account, uint256 timestamp) internal view virtual override returns (uint256) {
    return token.getPastVotes(account, timestamp);
  }

  function _getPastTotalSupply(uint256 timestamp) internal view virtual override returns (uint256) {
    return token.getPastTotalSupply(timestamp);
  }

  function _getClockMode() internal view virtual override returns (string memory) {
    return token.CLOCK_MODE();
  }
}

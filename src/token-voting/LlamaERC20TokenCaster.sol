// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

/// @title LlamaERC20TokenCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance `ERC20Votes` token collectively cast an approval or
/// disapproval on created actions.
contract LlamaERC20TokenCaster is LlamaTokenCaster {
  ERC20Votes public token;

  /// @dev This contract is deployed as a minimal proxy from the factory's `deployTokenVotingModule` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC20TokenCaster` clone.
  /// @dev This function is called by the `deployTokenVotingModule` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _token The ERC20 token to be used for voting.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _voteQuorumPct The minimum % of votes required to submit an approval to `LlamaCore`.
  /// @param _vetoQuorumPct The minimum % of vetoes required to submit a disapproval to `LlamaCore`.
  function initialize(
    ERC20Votes _token,
    ILlamaCore _llamaCore,
    uint8 _role,
    uint256 _voteQuorumPct,
    uint256 _vetoQuorumPct
  ) external initializer {
    __initializeLlamaTokenCasterMinimalProxy(_llamaCore, _role, _voteQuorumPct, _vetoQuorumPct);
    token = _token;
    uint256 totalSupply = token.getPastTotalSupply(block.timestamp - 1);
    if (totalSupply == 0) revert InvalidTokenAddress();
  }

  /// @dev Returns the number of votes for a given token holder at a given timestamp.
  function _getPastVotes(address account, uint256 timestamp) internal view virtual override returns (uint256) {
    return token.getPastVotes(account, timestamp);
  }

  /// @dev Returns the total supply of the token at a given timestamp.
  function _getPastTotalSupply(uint256 timestamp) internal view virtual override returns (uint256) {
    return token.getPastTotalSupply(timestamp);
  }

  /// @dev Returns the clock mode of the token (timestamp or blocknumber)
  function _getClockMode() internal view virtual override returns (string memory) {
    return token.CLOCK_MODE();
  }
}

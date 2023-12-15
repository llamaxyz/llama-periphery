// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaTokenAdapter} from "src/token-voting/interfaces/ILlamaTokenAdapter.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";

/// @title LlamaERC20TokenCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance `ERC20Votes` token collectively cast an approval or
/// disapproval on created actions.
contract LlamaERC20TokenCaster is LlamaTokenCaster {
  /// @dev This contract is deployed as a minimal proxy from the factory's `deploy` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC20TokenCaster` clone.
  /// @dev This function is called by the `deploy` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _voteQuorumPct The minimum % of votes required to submit an approval to `LlamaCore`.
  /// @param _vetoQuorumPct The minimum % of vetoes required to submit a disapproval to `LlamaCore`.
  function initialize(
    ILlamaCore _llamaCore,
    ILlamaTokenAdapter _tokenAdapter,
    uint8 _role,
    uint16 _voteQuorumPct,
    uint16 _vetoQuorumPct
  ) external initializer {
    __initializeLlamaTokenCasterMinimalProxy(_llamaCore, _tokenAdapter, _role, _voteQuorumPct, _vetoQuorumPct);
    uint256 totalSupply = tokenAdapter.getPastTotalSupply(tokenAdapter.clock() - 1);
    if (totalSupply == 0) revert InvalidTokenAddress();
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {CasterConfig} from "src/lib/Structs.sol";
import {ILlamaTokenClockAdapter} from "src/token-voting/ILlamaTokenClockAdapter.sol";
import {LlamaTokenCaster} from "src/token-voting/LlamaTokenCaster.sol";

/// @title LlamaERC20TokenCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance `ERC20Votes` token collectively cast an approval or
/// disapproval on created actions.
contract LlamaERC20TokenCaster is LlamaTokenCaster {
  /// @notice The ERC20 token to be used for voting.
  ERC20Votes public token;

  /// @dev This contract is deployed as a minimal proxy from the factory's `deploy` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC20TokenCaster` clone.
  /// @dev This function is called by the `deploy` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _token The ERC20 token to be used for voting.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param casterConfig Contains the quorum and period pct values to initialize the contract with.
  function initialize(
    ERC20Votes _token,
    ILlamaCore _llamaCore,
    ILlamaTokenClockAdapter _clockAdapter,
    uint8 _role,
    CasterConfig memory casterConfig
  ) external initializer {
    __initializeLlamaTokenCasterMinimalProxy(_llamaCore, _clockAdapter, _role, casterConfig);
    token = _token;
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
    return token.CLOCK_MODE();
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {LlamaTokenHolderCaster} from "src/token-voting/LlamaTokenHolderCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

/// @title LlamaERC20TokenHolderCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance ERC20Votes token cast approvals and disapprovals
/// on created actions.
contract LlamaERC20TokenHolderCaster is LlamaTokenHolderCaster {
  ERC20Votes public token;

  /// @dev This contract is deployed as a minimal proxy from the factory's `deployTokenVotingModule` function. The
  /// `_disableInitializers` locks the implementation (logic) contract, preventing any future initialization of it.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes a new `LlamaERC20TokenHolderCaster` clone.
  /// @dev This function is called by the `deployTokenVotingModule` function in the `LlamaTokenVotingFactory` contract.
  /// The `initializer` modifier ensures that this function can be invoked at most once.
  /// @param _token The ERC20 token to be used for voting.
  /// @param _llamaCore The `LlamaCore` contract for this Llama instance.
  /// @param _role The role used by this contract to cast approvals and disapprovals.
  /// @param _minApprovalPct The minimum % of approvals required to submit approvals to `LlamaCore`.
  /// @param _minDisapprovalPct The minimum % of disapprovals required to submit disapprovals to `LlamaCore`.
  function initialize(
    ERC20Votes _token,
    ILlamaCore _llamaCore,
    uint8 _role,
    uint256 _minApprovalPct,
    uint256 _minDisapprovalPct
  ) external initializer {
    __initializeLlamaTokenHolderCasterMinimalProxy(_llamaCore, _role, _minApprovalPct, _minDisapprovalPct);
    token = _token;
    uint256 totalSupply = token.totalSupply();
    if (totalSupply == 0) revert InvalidTokenAddress();
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {TokenholderActionCreator} from "src/token-voting/TokenholderActionCreator.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

/// @title ERC20TokenholderActionCreator
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a specified `ERC20Votes` token create actions on a llama instance if their
/// token balance is greater than or equal to the creation threshold.
contract ERC20TokenholderActionCreator is TokenholderActionCreator {
    ERC20Votes public immutable TOKEN;

    constructor(ERC20Votes token, ILlamaCore llamaCore, uint256 _creationThreshold)
        TokenholderActionCreator(llamaCore, _creationThreshold)
    {
        TOKEN = token;
        uint256 totalSupply = TOKEN.totalSupply();
        if (totalSupply == 0) revert InvalidTokenAddress();
        if (_creationThreshold > totalSupply) revert InvalidCreationThreshold();
    }

    function _getPastVotes(address account, uint256 timestamp) internal view virtual override returns (uint256) {
        return TOKEN.getPastVotes(account, timestamp);
    }

    function _getPastTotalSupply(uint256 timestamp) internal view virtual override returns (uint256) {
        return TOKEN.getPastTotalSupply(timestamp);
    }

    function _getClockMode() internal view virtual override returns (string memory) {
        return TOKEN.CLOCK_MODE();
    }
}

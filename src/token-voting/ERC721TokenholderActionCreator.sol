// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {TokenholderActionCreator} from "src/token-voting/TokenholderActionCreator.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

/// @title ERC721TokenholderActionCreator
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance ERC721Votes token create actions on the llama instance if
/// they hold enough tokens.
contract ERC721TokenholderActionCreator is TokenholderActionCreator {
    ERC721Votes public immutable TOKEN;

    constructor(ERC721Votes token, ILlamaCore llamaCore, uint256 _creationThreshold)
        TokenholderActionCreator(llamaCore, _creationThreshold)
    {
        TOKEN = token;
        uint256 totalSupply = TOKEN.getPastTotalSupply(block.timestamp - 1);
        if (totalSupply == 0) revert InvalidTokenAddress();
        if (_creationThreshold > totalSupply) revert InvalidCreationThreshold();
        if (!TOKEN.supportsInterface(type(IERC721).interfaceId)) revert InvalidTokenAddress();
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

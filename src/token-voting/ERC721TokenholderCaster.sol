// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {TokenholderCaster} from "src/token-voting/TokenholderCaster.sol";
import {ERC721Votes} from "@openzeppelin/token/ERC721/extensions/ERC721Votes.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

/// @title ERC721TokenholderCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance ERC721Votes token cast approvals and disapprovals
/// on created actions.
contract ERC721TokenholderCaster is TokenholderCaster {
    ERC721Votes public immutable TOKEN;

    constructor(ERC721Votes token, ILlamaCore llamaCore, uint8 role, uint256 minApprovalPct, uint256 minDisapprovalPct)
        TokenholderCaster(llamaCore, role, minApprovalPct, minDisapprovalPct)
    {
        TOKEN = token;
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

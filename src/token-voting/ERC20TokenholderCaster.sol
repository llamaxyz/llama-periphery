// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {TokenholderCaster} from "src/token-voting/TokenholderCaster.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

/// @title ERC20TokenholderCaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract lets holders of a given governance ERC20Votes token cast approvals and disapprovals
/// on created actions.
contract ERC20TokenholderCaster is TokenholderCaster {
    ERC20Votes public immutable TOKEN;

    constructor(ERC20Votes token, ILlamaCore llamaCore, uint8 role, uint256 minApprovalPct, uint256 minDisapprovalPct)
        TokenholderCaster(llamaCore, role, minApprovalPct, minDisapprovalPct)
    {
        TOKEN = token;
        uint256 totalSupply = TOKEN.totalSupply();
        if (totalSupply == 0) revert InvalidTokenAddress();
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

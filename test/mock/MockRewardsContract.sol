// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/utils/Address.sol";

contract MockRewardsContract {
  using SafeERC20 for IERC20;

  error OnlyRewardClaimer();

  modifier onlyRewardClaimer() {
    if (msg.sender != REWARD_CLAIMER) revert OnlyRewardClaimer();
    _;
  }

  address public immutable REWARD_CLAIMER;

  constructor(address rewardClaimer) {
    REWARD_CLAIMER = rewardClaimer;
  }

  function withdrawETH() external payable onlyRewardClaimer {
    Address.sendValue(payable(REWARD_CLAIMER), address(this).balance);
  }

  function withdrawERC20(IERC20 token) external onlyRewardClaimer {
    token.safeTransfer(REWARD_CLAIMER, token.balanceOf(address(this)));
  }
}

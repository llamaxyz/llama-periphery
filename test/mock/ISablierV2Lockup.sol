// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ISablierV2Lockup {
  function withdrawMax(uint256 streamId, address to) external;
}

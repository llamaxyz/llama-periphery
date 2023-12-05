// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2} from "forge-std/Script.sol";

library DeployUtils {
  function print(string memory message) internal view {
    // Avoid getting flooded with logs during tests. Note that fork tests will show logs with this
    // approach, because there's currently no way to tell which environment we're in, e.g. script
    // or test. This is being tracked in https://github.com/foundry-rs/foundry/issues/2900.
    if (block.chainid != 31_337) console2.log(message);
  }
}

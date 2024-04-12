// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";

import {DeployLlamaAccountMulticallFactory} from "script/DeployLlamaAccountMulticallFactory.s.sol";

import {LlamaAccountMulticallExtension} from "src/account-multicall/LlamaAccountMulticallExtension.sol";
import {LlamaAccountMulticallFactory} from "src/account-multicall/LlamaAccountMulticallFactory.sol";
import {LlamaAccountMulticallGuard} from "src/account-multicall/LlamaAccountMulticallGuard.sol";
import {LlamaAccountMulticallStorage} from "src/account-multicall/LlamaAccountMulticallStorage.sol";

contract LlamaAccountMulticallFactoryTest is LlamaPeripheryTestSetup, DeployLlamaAccountMulticallFactory {
  event LlamaAccountMulticallModuleCreated(
    address indexed deployer,
    address indexed llamaExecutor,
    uint256 nonce,
    address accountMulticallGuard,
    address accountMulticallExtension,
    address accountMulticallStorage,
    uint256 chainId
  );

  function setUp() public override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the factory
    DeployLlamaAccountMulticallFactory.run();
  }
}

contract DeployAccountMulticallModule is LlamaAccountMulticallFactoryTest {
  function test_Deploy() public {
    LlamaAccountMulticallStorage.TargetSelectorAuthorization[] memory data =
      new LlamaAccountMulticallStorage.TargetSelectorAuthorization[](1);
    LlamaAccountMulticallFactory.LlamaAccountMulticallConfig memory config =
      LlamaAccountMulticallFactory.LlamaAccountMulticallConfig(address(EXECUTOR), 0, data);

    // vm.expectEmit();
    // emit LlamaAccountMulticallModuleCreated(
    //   address(this), address(EXECUTOR), 0, address(0), address(0), address(0), block.chainid
    // );
    (
      LlamaAccountMulticallGuard accountMulticallGuard,
      LlamaAccountMulticallExtension accountMulticallExtension,
      LlamaAccountMulticallStorage accountMulticallStorage
    ) = accountMulticallFactory.deploy(config);

    assertEq(address(accountMulticallGuard.ACCOUNT_MULTICALL_EXTENSION()), address(accountMulticallExtension));
    assertEq(address(accountMulticallExtension.ACCOUNT_MULTICALL_STORAGE()), address(accountMulticallStorage));
    assertEq(address(accountMulticallStorage.LLAMA_EXECUTOR()), address(EXECUTOR));
  }
}

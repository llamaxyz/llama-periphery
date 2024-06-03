// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {LlamaPeripheryTestSetup} from "test/LlamaPeripheryTestSetup.sol";

import {DeployLlamaTokenVotingFactory} from "script/DeployLlamaTokenVotingFactory.s.sol";

import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ActionInfo} from "src/lib/Structs.sol";
import {LlamaMessageBroadcaster} from "src/message-broadcaster/LlamaMessageBroadcaster.sol";

contract LlamaMessageBroadcasterTest is LlamaPeripheryTestSetup, DeployLlamaTokenVotingFactory {
  event MessageBroadcasted(ILlamaExecutor indexed llamaExecutor, string message);

  function setUp() public virtual override {
    LlamaPeripheryTestSetup.setUp();

    // Deploy the peripheral contracts
    DeployLlamaTokenVotingFactory.run();
  }
}

contract BroadcastMessage is LlamaMessageBroadcasterTest {
  function test_BroadcastMessage() public {
    string memory message = "Hello World!";
    vm.expectEmit();
    emit MessageBroadcasted(EXECUTOR, message);
    vm.prank(address(EXECUTOR));
    llamaMessageBroadcaster.broadcastMessage(message);
  }

  function test_BroadcastMessageFullActionLifecycle() public {
    string memory message = "Hello World!";

    // Giving Action Creator permission to call `LlamaMessageBroadcaster.broadcastMessage`.
    vm.prank(address(EXECUTOR));
    POLICY.setRolePermission(
      CORE_TEAM_ROLE,
      ILlamaPolicy.PermissionData(
        address(llamaMessageBroadcaster), LlamaMessageBroadcaster.broadcastMessage.selector, address(STRATEGY)
      ),
      true
    );

    // Create Action to broadcast message.
    bytes memory data = abi.encodeCall(LlamaMessageBroadcaster.broadcastMessage, (message));
    vm.prank(coreTeam1);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(llamaMessageBroadcaster), 0, data, "");
    ActionInfo memory actionInfo =
      ActionInfo(actionId, coreTeam1, CORE_TEAM_ROLE, STRATEGY, address(llamaMessageBroadcaster), 0, data);

    // Approval and auto-queue process.
    vm.prank(coreTeam2);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam3);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam4);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");

    // Execute Action.
    vm.expectEmit();
    emit MessageBroadcasted(EXECUTOR, message);
    CORE.executeAction(actionInfo);
  }

  function test_RevertIf_CallerIsNotExecutor() public {
    string memory message = "Hello World!";
    vm.expectRevert();
    llamaMessageBroadcaster.broadcastMessage(message);
  }
}

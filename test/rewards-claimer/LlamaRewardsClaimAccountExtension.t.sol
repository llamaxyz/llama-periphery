// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {MockRewardsContract} from "test/mock/MockRewardsContract.sol";
import {LlamaRewardsClaimTestSetup} from "test/rewards-claimer/LlamaRewardsClaimTestSetup.sol";

import {ILlamaAccount} from "src/interfaces/ILlamaAccount.sol";
import {ActionInfo} from "src/lib/Structs.sol";
import {LlamaRewardsClaimAccountExtension} from "src/rewards-claimer/LlamaRewardsClaimAccountExtension.sol";
import {LlamaRewardsClaimGuard} from "src/rewards-claimer/LlamaRewardsClaimGuard.sol";

contract LlamaRewardsClaimAccountExtensionTest is LlamaRewardsClaimTestSetup {
  event ethWithdrawn(address indexed from, address indexed to, uint256 amount);
  event erc20Withdrawn(IERC20 indexed token, address indexed from, address indexed to, uint256 amount);

  function setUp() public override {
    LlamaRewardsClaimTestSetup.setUp();
  }
}

contract Constructor is LlamaRewardsClaimAccountExtensionTest {
  function test_SetsRewardsClaimStorage() public {
    assertEq(address(rewardsClaimAccountExtension.REWARDS_CLAIM_STORAGE()), address(rewardsClaimStorage));
  }
}

contract ClaimRewards is LlamaRewardsClaimAccountExtensionTest {
  function _createAndQueueActionClaimRewards() public returns (ActionInfo memory actionInfo) {
    LlamaRewardsClaimAccountExtension.TargetData[] memory targetData = _setupClaimRewardsData();
    bytes memory accountExtensionData = abi.encodeCall(LlamaRewardsClaimAccountExtension.claimRewards, (targetData));
    bytes memory data =
      abi.encodeCall(ILlamaAccount.execute, (address(rewardsClaimAccountExtension), true, 0, accountExtensionData));

    // Create an action to claim rewards.
    vm.prank(coreTeam1);
    uint256 actionId = CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(ACCOUNT), 0, data, "");
    actionInfo = ActionInfo(actionId, coreTeam1, CORE_TEAM_ROLE, STRATEGY, address(ACCOUNT), 0, data);

    // Approve and queue the action.
    vm.prank(coreTeam1);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam2);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
    vm.prank(coreTeam3);
    CORE.castApproval(CORE_TEAM_ROLE, actionInfo, "");
  }

  function test_ClaimRewards() public {
    ActionInfo memory actionInfo = _createAndQueueActionClaimRewards();

    assertEq(address(rewardsContract1).balance, 1 ether);
    assertEq(USDC.balanceOf(address(rewardsContract1)), 1 ether);
    assertEq(address(rewardsContract2).balance, 1 ether);
    assertEq(USDC.balanceOf(address(rewardsContract2)), 1 ether);
    assertEq(address(rewardsContract3).balance, 1 ether);
    assertEq(USDC.balanceOf(address(rewardsContract3)), 1 ether);
    assertEq(address(rewardsContract4).balance, 1 ether);
    assertEq(USDC.balanceOf(address(rewardsContract4)), 1 ether);
    assertEq(address(rewardsContract5).balance, 1 ether);
    assertEq(USDC.balanceOf(address(rewardsContract5)), 1 ether);

    uint256 initialLlamaAccountETHBalance = address(ACCOUNT).balance;
    uint256 initialLlamaAccountUSDCBalance = USDC.balanceOf(address(ACCOUNT));

    // Execute the action.
    vm.expectEmit();
    emit ethWithdrawn(address(rewardsContract1), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit erc20Withdrawn(USDC, address(rewardsContract1), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit ethWithdrawn(address(rewardsContract2), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit erc20Withdrawn(USDC, address(rewardsContract2), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit ethWithdrawn(address(rewardsContract3), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit erc20Withdrawn(USDC, address(rewardsContract3), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit ethWithdrawn(address(rewardsContract4), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit erc20Withdrawn(USDC, address(rewardsContract4), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit ethWithdrawn(address(rewardsContract5), address(ACCOUNT), 1 ether);
    vm.expectEmit();
    emit erc20Withdrawn(USDC, address(rewardsContract5), address(ACCOUNT), 1 ether);

    CORE.executeAction(actionInfo);

    assertEq(address(rewardsContract1).balance, 0);
    assertEq(USDC.balanceOf(address(rewardsContract1)), 0);
    assertEq(address(rewardsContract2).balance, 0);
    assertEq(USDC.balanceOf(address(rewardsContract2)), 0);
    assertEq(address(rewardsContract3).balance, 0);
    assertEq(USDC.balanceOf(address(rewardsContract3)), 0);
    assertEq(address(rewardsContract4).balance, 0);
    assertEq(USDC.balanceOf(address(rewardsContract4)), 0);
    assertEq(address(rewardsContract5).balance, 0);
    assertEq(USDC.balanceOf(address(rewardsContract5)), 0);

    assertEq(address(ACCOUNT).balance, initialLlamaAccountETHBalance + 5 ether);
    assertEq(USDC.balanceOf(address(ACCOUNT)), initialLlamaAccountUSDCBalance + 5 ether);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {MockRewardsContract} from "test/mock/MockRewardsContract.sol";
import {LlamaRewardsClaimTestSetup} from "test/rewards-claimer/LlamaRewardsClaimTestSetup.sol";

import {ILlamaAccount} from "src/interfaces/ILlamaAccount.sol";
import {LlamaRewardsClaimAccountExtension} from "src/rewards-claimer/LlamaRewardsClaimAccountExtension.sol";
import {LlamaRewardsClaimGuard} from "src/rewards-claimer/LlamaRewardsClaimGuard.sol";

contract LlamaRewardsClaimGuardTest is LlamaRewardsClaimTestSetup {
  function setUp() public override {
    LlamaRewardsClaimTestSetup.setUp();
  }
}

contract Constructor is LlamaRewardsClaimGuardTest {
  function test_SetsRewardsClaimer() public {
    assertEq(address(rewardsClaimGuard.REWARDS_CLAIMER()), address(rewardsClaimAccountExtension));
  }
}

contract ValidateActionCreation is LlamaRewardsClaimGuardTest {
  function _setupClaimRewardsData()
    public
    view
    returns (LlamaRewardsClaimAccountExtension.TargetData[] memory targetData)
  {
    targetData = new LlamaRewardsClaimAccountExtension.TargetData[](10);
    targetData[0] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract1), 0, abi.encodeCall(MockRewardsContract.withdrawETH, ())
    );
    targetData[1] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract1), 0, abi.encodeCall(MockRewardsContract.withdrawERC20, (USDC))
    );
    targetData[2] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract2), 0, abi.encodeCall(MockRewardsContract.withdrawETH, ())
    );
    targetData[3] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract2), 0, abi.encodeCall(MockRewardsContract.withdrawERC20, (USDC))
    );
    targetData[4] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract3), 0, abi.encodeCall(MockRewardsContract.withdrawETH, ())
    );
    targetData[5] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract3), 0, abi.encodeCall(MockRewardsContract.withdrawERC20, (USDC))
    );
    targetData[6] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract4), 0, abi.encodeCall(MockRewardsContract.withdrawETH, ())
    );
    targetData[7] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract4), 0, abi.encodeCall(MockRewardsContract.withdrawERC20, (USDC))
    );
    targetData[8] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract5), 0, abi.encodeCall(MockRewardsContract.withdrawETH, ())
    );
    targetData[9] = LlamaRewardsClaimAccountExtension.TargetData(
      address(rewardsContract5), 0, abi.encodeCall(MockRewardsContract.withdrawERC20, (USDC))
    );
  }

  function test_RevertIf_TargetIsNotRewardsClaimer() public {
    LlamaRewardsClaimAccountExtension.TargetData[] memory targetData = _setupClaimRewardsData();

    address dummyTarget = address(0xdeadbeef);

    bytes memory accountExtensionData = abi.encodeCall(LlamaRewardsClaimAccountExtension.claimRewards, (targetData));
    bytes memory data = abi.encodeCall(ILlamaAccount.execute, (dummyTarget, true, 0, accountExtensionData));

    vm.prank(coreTeam1);
    vm.expectRevert(
      abi.encodeWithSelector(
        LlamaRewardsClaimGuard.UnauthorizedCall.selector,
        dummyTarget,
        LlamaRewardsClaimAccountExtension.claimRewards.selector,
        true
      )
    );
    CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(ACCOUNT), 0, data, "");
  }

  function test_RevertIf_SelectorIsNotClaimRewards() public {
    LlamaRewardsClaimAccountExtension.TargetData[] memory targetData = _setupClaimRewardsData();

    bytes4 dummySelector = bytes4(0);

    bytes memory accountExtensionData = abi.encodeWithSelector(dummySelector, targetData);
    bytes memory data =
      abi.encodeCall(ILlamaAccount.execute, (address(rewardsClaimAccountExtension), true, 0, accountExtensionData));

    vm.prank(coreTeam1);
    vm.expectRevert(
      abi.encodeWithSelector(
        LlamaRewardsClaimGuard.UnauthorizedCall.selector, address(rewardsClaimAccountExtension), dummySelector, true
      )
    );
    CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(ACCOUNT), 0, data, "");
  }

  function test_RevertIf_NotDelegateCall() public {
    LlamaRewardsClaimAccountExtension.TargetData[] memory targetData = _setupClaimRewardsData();

    bytes memory accountExtensionData = abi.encodeCall(LlamaRewardsClaimAccountExtension.claimRewards, (targetData));
    bytes memory data =
      abi.encodeCall(ILlamaAccount.execute, (address(rewardsClaimAccountExtension), false, 0, accountExtensionData));

    vm.prank(coreTeam1);
    vm.expectRevert(
      abi.encodeWithSelector(
        LlamaRewardsClaimGuard.UnauthorizedCall.selector,
        address(rewardsClaimAccountExtension),
        LlamaRewardsClaimAccountExtension.claimRewards.selector,
        false
      )
    );
    CORE.createAction(CORE_TEAM_ROLE, STRATEGY, address(ACCOUNT), 0, data, "");
  }
}

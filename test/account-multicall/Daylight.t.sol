// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IProtocolRewards} from "test/mock/IProtocolRewards.sol";

import {ILlamaAccount} from "src/interfaces/ILlamaAccount.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";
import {ILlamaLens} from "src/interfaces/ILlamaLens.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ActionInfo} from "src/lib/Structs.sol";
import {LlamaAccountMulticallExtension} from "src/account-multicall/LlamaAccountMulticallExtension.sol";
import {LlamaAccountMulticallStorage} from "src/account-multicall/LlamaAccountMulticallStorage.sol";

contract DaylightTest is Test {
  string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL"); // can't use constant here

  event Withdraw(address indexed from, address indexed to, uint256 amount);

  IProtocolRewards public constant REWARDS_CONTRACT = IProtocolRewards(0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B);

  // Daylight's Llama instance.
  ILlamaCore constant CORE = ILlamaCore(0x933094dB418ff18F1C4387965e4cdD6B26176E36);
  ILlamaExecutor constant EXECUTOR = ILlamaExecutor(0x4f3907664DA95607c11009F1BD987226f1689F1c);
  ILlamaPolicy constant POLICY = ILlamaPolicy(0x5d657f5FF2E34CC8015B6548245E7de8dB7C1F24);
  ILlamaAccount constant ACCOUNT = ILlamaAccount(0xD0844Dd6a7A064d2F3691A2d1b42FC9800438A10);
  ILlamaStrategy constant INSTANT_STRATEGY = ILlamaStrategy(0x75217BE08371f9B2C392DE41913b76620F4497D1);
  ILlamaLens constant LENS = ILlamaLens(0x1D74803D4939aFa3CC9fF1B8667bE4d119d925cB);
  address constant RELATIVE_QUANTITY_QUORUM_LOGIC = 0x81F7D26fD7d814bFcEF78239a32c0BA5282C98Dc;

  // Account Multicall Module.
  LlamaAccountMulticallStorage constant ACCOUNT_MULTICALL_STORAGE =
    LlamaAccountMulticallStorage(0x3A44bE9AB1182d335E27DF7E66C0c302f2EeA91d);
  LlamaAccountMulticallExtension constant ACCOUNT_MULTICALL_EXTENSION =
    LlamaAccountMulticallExtension(0x7c902930d282d73DbA30dBb0EB744D39ed8b6c18);

  uint8 public constant REWARDS_CLAIMER_ROLE = 2;

  address policyBot = 0xc33eDd04b044a14843B647f8f5A2fF85F55259A3;

  // Othes constants.
  uint96 DEFAULT_ROLE_QTY = 1;
  uint96 EMPTY_ROLE_QTY = 0;
  uint64 DEFAULT_ROLE_EXPIRATION = type(uint64).max;

  function setUp() public virtual {
    vm.createSelectFork(OPTIMISM_RPC_URL, 119_451_383);
  }

  function _setupClaimRewardsData() public view returns (LlamaAccountMulticallExtension.TargetData[] memory targetData) {
    targetData = new LlamaAccountMulticallExtension.TargetData[](1);
    targetData[0] = LlamaAccountMulticallExtension.TargetData(
      address(REWARDS_CONTRACT), 0, abi.encodeCall(REWARDS_CONTRACT.withdrawFor, (address(ACCOUNT), 0))
    );
  }

  function mineBlock() internal {
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);
  }
}

contract Multicall is DaylightTest {
  function _createAndQueueActionClaimRewards() public returns (ActionInfo memory actionInfo) {
    LlamaAccountMulticallExtension.TargetData[] memory targetData = _setupClaimRewardsData();
    bytes memory accountExtensionData = abi.encodeCall(LlamaAccountMulticallExtension.multicall, (targetData));
    bytes memory data =
      abi.encodeCall(ILlamaAccount.execute, (address(ACCOUNT_MULTICALL_EXTENSION), true, 0, accountExtensionData));

    // Create an action to claim rewards.
    vm.prank(policyBot);
    uint256 actionId = CORE.createAction(
      REWARDS_CLAIMER_ROLE,
      INSTANT_STRATEGY,
      address(ACCOUNT),
      0,
      data,
      "# Claim Rewards for 0xD0844Dd6a7A064d2F3691A2d1b42FC9800438A10\n\n"
    );
    actionInfo = ActionInfo(actionId, policyBot, REWARDS_CLAIMER_ROLE, INSTANT_STRATEGY, address(ACCOUNT), 0, data);

    // Queue action.
    CORE.queueAction(actionInfo);
  }

  function test_Multicall() public {
    ActionInfo memory actionInfo = _createAndQueueActionClaimRewards();

    uint256 balanceToClaim = 666_000_000_000_000;
    assertEq(REWARDS_CONTRACT.balanceOf(address(ACCOUNT)), balanceToClaim);

    uint256 initialLlamaAccountETHBalance = address(ACCOUNT).balance;

    // Execute the action.
    vm.expectEmit();
    emit Withdraw(address(ACCOUNT), address(ACCOUNT), balanceToClaim);

    CORE.executeAction(actionInfo);

    assertEq(REWARDS_CONTRACT.balanceOf(address(ACCOUNT)), 0);
    assertEq(address(ACCOUNT).balance, initialLlamaAccountETHBalance + balanceToClaim);
  }
}

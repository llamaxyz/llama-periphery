// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {ISablierV2Batch} from "test/mock/ISablierV2Batch.sol";

import {ILlamaAccount} from "src/interfaces/ILlamaAccount.sol";
import {ILlamaStrategy} from "src/interfaces/ILlamaStrategy.sol";
import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";
import {ILlamaLens} from "src/interfaces/ILlamaLens.sol";
import {ILlamaPolicy} from "src/interfaces/ILlamaPolicy.sol";
import {ActionInfo} from "src/lib/Structs.sol";

contract BoostCreateStreamTest is Test {
  string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL"); // can't use constant here

  ISablierV2Batch public constant SABLIER_V2_BATCH = ISablierV2Batch(0x8145429538dDBdDc4099B2bAfd24DD8958fa03b8);
  address public constant SABLIER_V2_LOCKUP_LINEAR = 0x4b45090152a5731b5bc71b5baF71E60e05B33867;
  IERC20 public constant OP_TOKEN = IERC20(0x4200000000000000000000000000000000000042);

  // Boost's Llama instance.
  ILlamaCore constant CORE = ILlamaCore(0x4C18b41AC340E18D7622310D193aa9cA2350A404);
  ILlamaExecutor constant EXECUTOR = ILlamaExecutor(0xCe276223Ef4d467C286e0A02ECb010D3220EA980);
  ILlamaPolicy constant POLICY = ILlamaPolicy(0xeCCB99806ce0738918F20253F304A373FF197CDd);
  ILlamaAccount constant ACCOUNT = ILlamaAccount(0x48E6a039bcF6d99806Ce4595fC59e4A7C0CaAB19);
  ILlamaStrategy constant CORE_APPROVAL_STRATEGY = ILlamaStrategy(0xc6BB7ed128566FeB1d2E62fd57F23A81A0Fbf498);
  ILlamaLens constant LENS = ILlamaLens(0x1D74803D4939aFa3CC9fF1B8667bE4d119d925cB);
  address constant RELATIVE_QUANTITY_QUORUM_LOGIC = 0x81F7D26fD7d814bFcEF78239a32c0BA5282C98Dc;

  uint8 public constant STREAM_CREATOR_ROLE = 5;

  address policyBot = 0x998c0d63AAeFaE1D44e3B735D9A0Dd00FCD87Dfa;

  // Othes constants.
  uint96 DEFAULT_ROLE_QTY = 1;
  uint96 EMPTY_ROLE_QTY = 0;
  uint64 DEFAULT_ROLE_EXPIRATION = type(uint64).max;

  function setUp() public virtual {
    vm.createSelectFork(OPTIMISM_RPC_URL, 120_022_066);
  }

  function mineBlock() internal {
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);
  }
}

contract CreateStreams is BoostCreateStreamTest {
  function _setupClaimRewardsData() public pure returns (LlamaAccountMulticallExtension.TargetData[] memory targetData) {
    targetData = new LlamaAccountMulticallExtension.TargetData[](1);
    targetData[0] = LlamaAccountMulticallExtension.TargetData(
      address(REWARDS_CONTRACT), 0, abi.encodeCall(REWARDS_CONTRACT.withdrawFor, (address(ACCOUNT), 0))
    );
    console2.logBytes(abi.encodeCall(REWARDS_CONTRACT.withdrawFor, (address(ACCOUNT), 0)));
  }

  function _createAndQueueActionClaimRewards() public returns (ActionInfo memory actionInfo) {
    LlamaAccountMulticallExtension.TargetData[] memory targetData = _setupClaimRewardsData();
    bytes memory accountExtensionData = abi.encodeCall(LlamaAccountMulticallExtension.multicall, (targetData));
    console2.logBytes(accountExtensionData);
    bytes memory data =
      abi.encodeCall(ILlamaAccount.execute, (address(ACCOUNT_MULTICALL_EXTENSION), true, 0, accountExtensionData));
    console2.logBytes(data);

    // Create an action to claim rewards.
    console2.logBytes(
      abi.encodeCall(
        ILlamaCore.createAction,
        (
          REWARDS_CLAIMER_ROLE,
          INSTANT_STRATEGY,
          address(ACCOUNT),
          0,
          data,
          "# Claim Rewards for 0xD0844Dd6a7A064d2F3691A2d1b42FC9800438A10\n\n"
        )
      )
    );
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

  function test_CreateStreams() public {
    ERC20Data memory approvalData = ERC20Data(OP_TOKEN, SABLIER_V2_BATCH, 250e18);
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

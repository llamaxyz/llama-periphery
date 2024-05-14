// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {ISablierV2Batch, CreateWithDurations, Durations, Broker} from "test/mock/ISablierV2Batch.sol";
import {ISablierV2Lockup} from "test/mock/ISablierV2Lockup.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

import {ILlamaAccount, ERC20Data} from "src/interfaces/ILlamaAccount.sol";
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
  uint256 public constant DEPOSIT_AMOUNT = 10_000e18;

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
    vm.createSelectFork(OPTIMISM_RPC_URL, 120_022_812);
  }

  function mineBlock() internal {
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 1);
  }
}

contract CreateStreams is BoostCreateStreamTest {
  function _setupStreamsData() public pure returns (CreateWithDurations[] memory streamsData) {
    streamsData = new CreateWithDurations[](15);
    streamsData[0] = CreateWithDurations(
      address(EXECUTOR),
      0x32F1406809E2C6967e41Ac44C8BDE46aB597DE3C,
      4_186_448_345_548_490_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[1] = CreateWithDurations(
      address(EXECUTOR),
      0xA2b430fFfA485250ddd20A81B609f507728B4ccF,
      1_823_539_872_459_710_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[2] = CreateWithDurations(
      address(EXECUTOR),
      0xbED050C15224a53a12815Fa79F2B1EF431887Eb2,
      1_006_915_677_288_420_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[3] = CreateWithDurations(
      address(EXECUTOR),
      0x512b55b00d744fC2eDB8474f223a7498c3e5a7ce,
      955_514_606_821_921_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[4] = CreateWithDurations(
      address(EXECUTOR),
      0x2D7F5212E93740a74b99D8a0799b4514061dbDA5,
      341_831_765_437_998_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[5] = CreateWithDurations(
      address(EXECUTOR),
      0xd47f59Ed8d4E889363A79a56fEDf64223609E29f,
      268_745_691_612_985_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[6] = CreateWithDurations(
      address(EXECUTOR),
      0xA6554D85b945Ce01505005bb07e56e6126259686,
      241_893_788_288_894_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[7] = CreateWithDurations(
      address(EXECUTOR),
      0xF2E82029a3B83341Ac1BA7EF71F6a93b43C75f77,
      228_912_259_795_094_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[8] = CreateWithDurations(
      address(EXECUTOR),
      0x4e038840C21F12f3c02Ca029376eF3b93D91CDd7,
      204_697_058_667_877_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[9] = CreateWithDurations(
      address(EXECUTOR),
      0xccD724B9af92A3A389150334556330EfD3f59487,
      169_308_628_738_403_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[10] = CreateWithDurations(
      address(EXECUTOR),
      0xd9906b2f00c0aD4DaA8bEf197718e77B8B47B773,
      158_965_842_620_510_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[11] = CreateWithDurations(
      address(EXECUTOR),
      0x544Ea3D7C3b93639d42D1482b3eaeb51E2335862,
      136_626_360_280_544_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[12] = CreateWithDurations(
      address(EXECUTOR),
      0xAe7F45e9CAc43AA06254fCce2F6077190834C37f,
      126_679_992_097_101_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[13] = CreateWithDurations(
      address(EXECUTOR),
      0xeBfE2bC632A46bbEb919D9C8FA8b505997FD4f1A,
      77_266_811_289_232_000_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
    streamsData[14] = CreateWithDurations(
      address(EXECUTOR),
      0x9477861457123C55cD34C608068c58af2BFF5DC8,
      72_653_299_052_811_800_000,
      true,
      true,
      Durations(0, 60 days),
      Broker(address(0), UD60x18(ud(0)))
    );
  }

  function _createAndQueueActionSetupStreams() public returns (ActionInfo memory actionInfo) {
    CreateWithDurations[] memory streamsData = _setupStreamsData();
    bytes memory sablierV2BatchData =
      abi.encodeCall(SABLIER_V2_BATCH.createWithDurations, (SABLIER_V2_LOCKUP_LINEAR, OP_TOKEN, streamsData));
    console2.logBytes(sablierV2BatchData);
    bytes memory data = abi.encodeCall(ILlamaAccount.execute, (address(SABLIER_V2_BATCH), false, 0, sablierV2BatchData));
    console2.logBytes(data);

    // Create an action to claim rewards.
    console2.logBytes(
      abi.encodeCall(
        ILlamaCore.createAction,
        (STREAM_CREATOR_ROLE, CORE_APPROVAL_STRATEGY, address(ACCOUNT), 0, data, "# Create Sablier Linear Streams\n\n")
      )
    );
    vm.prank(policyBot);
    uint256 actionId = CORE.createAction(
      STREAM_CREATOR_ROLE, CORE_APPROVAL_STRATEGY, address(ACCOUNT), 0, data, "# Create Sablier Linear Streams\n\n"
    );
    actionInfo = ActionInfo(actionId, policyBot, STREAM_CREATOR_ROLE, CORE_APPROVAL_STRATEGY, address(ACCOUNT), 0, data);

    // Queue action.
    CORE.queueAction(actionInfo);
  }

  function test_CreateStreams() public {
    ActionInfo memory actionInfo = _createAndQueueActionSetupStreams();

    uint256 initialTreasuryOPBalance = OP_TOKEN.balanceOf(address(ACCOUNT));

    CORE.executeAction(actionInfo);

    assertGe(OP_TOKEN.balanceOf(address(ACCOUNT)), initialTreasuryOPBalance - (DEPOSIT_AMOUNT));
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ILlamaCore} from "src/interfaces/ILlamaCore.sol";
import {ILlamaExecutor} from "src/interfaces/ILlamaExecutor.sol";

/// @title LlamaMessageBroadcaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract enables Llama instances to broadcast an offchain message.
contract LlamaMessageBroadcaster {
  /// @dev Emitted when a message is broadcast by a Llama instance.
  event MessageBroadcasted(ILlamaExecutor indexed llamaExecutor, string message);

  /// @notice Broadcasts a message from a Llama instance.
  /// @param message Message to be broadcasted.
  function broadcastMessage(string calldata message) external {
    ILlamaExecutor llamaExecutor = ILlamaExecutor(msg.sender);
    // Duck testing to check if the caller is a Llama instance.
    ILlamaCore(llamaExecutor.LLAMA_CORE()).actionsCount();
    emit MessageBroadcasted(llamaExecutor, message);
  }
}

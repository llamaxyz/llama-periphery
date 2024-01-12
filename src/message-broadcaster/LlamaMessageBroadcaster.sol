// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title LlamaMessageBroadcaster
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This contract enables Llama instances to broadcast an offchain message.
contract LlamaMessageBroadcaster {
  /// @dev Emitted when a message is broadcast.
  event LlamaInstanceMessageBroadcasted(address indexed llamaExecutor, string message);

  function broadcastMessage(string calldata message) external {
    emit LlamaInstanceMessageBroadcasted(msg.sender, message);
  }
}

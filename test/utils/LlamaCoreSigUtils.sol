// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ActionInfo} from "src/lib/Structs.sol";

contract LlamaCoreSigUtils {
  struct EIP712Domain {
    string name;
    string version;
    uint256 chainId;
    address verifyingContract;
  }

  struct CreateAction {
    address tokenHolder;
    address strategy;
    address target;
    uint256 value;
    bytes data;
    string description;
    uint256 nonce;
  }

  struct CancelAction {
    address tokenHolder;
    ActionInfo actionInfo;
    uint256 nonce;
  }

  struct CastApproval {
    address tokenHolder;
    uint8 support;
    ActionInfo actionInfo;
    string reason;
    uint256 nonce;
  }

  struct CastDisapproval {
    address tokenHolder;
    uint8 support;
    ActionInfo actionInfo;
    string reason;
    uint256 nonce;
  }

  /// @notice EIP-712 base typehash.
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @notice EIP-712 createAction typehash.
  bytes32 internal constant CREATE_ACTION_TYPEHASH = keccak256(
    "CreateAction(address tokenHolder,address strategy,address target,uint256 value,bytes data,string description,uint256 nonce)"
  );

  /// @dev EIP-712 cancelAction typehash.
  bytes32 internal constant CANCEL_ACTION_TYPEHASH = keccak256(
    "CancelAction(address tokenHolder,ActionInfo actionInfo,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice EIP-712 castVote typehash.
  bytes32 internal constant CAST_APPROVAL_TYPEHASH = keccak256(
    "CastApproval(address tokenHolder,uint8 support,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice EIP-712 castVeto typehash.
  bytes32 internal constant CAST_DISAPPROVAL_TYPEHASH = keccak256(
    "CastDisapproval(address tokenHolder,uint8 role,ActionInfo actionInfo,string reason,uint256 nonce)ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  /// @notice EIP-712 actionInfo typehash.
  bytes32 internal constant ACTION_INFO_TYPEHASH = keccak256(
    "ActionInfo(uint256 id,address creator,uint8 creatorRole,address strategy,address target,uint256 value,bytes data)"
  );

  bytes32 internal DOMAIN_SEPARATOR;

  /// @notice Sets the EIP-712 domain separator.
  function setDomainHash(EIP712Domain memory eip712Domain) internal {
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        EIP712_DOMAIN_TYPEHASH,
        keccak256(bytes(eip712Domain.name)),
        keccak256(bytes(eip712Domain.version)),
        eip712Domain.chainId,
        eip712Domain.verifyingContract
      )
    );
  }

  /// @notice Returns the hash of CreateAction.
  function getCreateActionHash(CreateAction memory createAction) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        CREATE_ACTION_TYPEHASH,
        createAction.tokenHolder,
        createAction.strategy,
        createAction.target,
        createAction.value,
        keccak256(createAction.data),
        keccak256(bytes(createAction.description)),
        createAction.nonce
      )
    );
  }

  /// @notice Returns the hash of the fully encoded EIP-712 message for the CreateAction domain, which can be used to
  /// recover the signer.
  function getCreateActionTypedDataHash(CreateAction memory createAction) internal view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getCreateActionHash(createAction)));
  }

  /// @notice Returns the hash of CancelActionBySig.
  function getCancelActionHash(CancelAction memory cancelAction) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        CANCEL_ACTION_TYPEHASH, cancelAction.tokenHolder, getActionInfoHash(cancelAction.actionInfo), cancelAction.nonce
      )
    );
  }

  /// @notice Returns the hash of the fully encoded EIP-712 message for the CancelAction domain, which can be used to
  /// recover the signer.
  function getCancelActionTypedDataHash(CancelAction memory cancelAction) internal view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getCancelActionHash(cancelAction)));
  }

  /// @notice Returns the hash of CastApproval.
  function getCastApprovalHash(CastApproval memory castVote) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        CAST_APPROVAL_TYPEHASH,
        castVote.tokenHolder,
        castVote.support,
        getActionInfoHash(castVote.actionInfo),
        keccak256(bytes(castVote.reason)),
        castVote.nonce
      )
    );
  }

  /// @notice Returns the hash of the fully encoded EIP-712 message for the CastApproval domain, which can be used to
  /// recover the signer.
  function getCastApprovalTypedDataHash(CastApproval memory castVote) internal view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getCastApprovalHash(castVote)));
  }

  /// @notice Returns the hash of CastDisapprovalBySig.
  function getCastDisapprovalHash(CastDisapproval memory castVeto) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        CAST_DISAPPROVAL_TYPEHASH,
        castVeto.tokenHolder,
        castVeto.support,
        getActionInfoHash(castVeto.actionInfo),
        keccak256(bytes(castVeto.reason)),
        castVeto.nonce
      )
    );
  }

  /// @notice Returns the hash of the fully encoded EIP-712 message for the CastDisapproval domain, which can be used to
  /// recover the signer.
  function getCastDisapprovalTypedDataHash(CastDisapproval memory castVeto) internal view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getCastDisapprovalHash(castVeto)));
  }

  /// @notice Returns the hash of ActionInfo.
  function getActionInfoHash(ActionInfo memory actionInfo) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_INFO_TYPEHASH,
        actionInfo.id,
        actionInfo.creator,
        actionInfo.creatorRole,
        address(actionInfo.strategy),
        actionInfo.target,
        actionInfo.value,
        keccak256(actionInfo.data)
      )
    );
  }
}

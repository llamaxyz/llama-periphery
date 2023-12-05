// SPDX-License-Identifier: MIT
// TODO This interface was generated from `cast interface`, so some types are not as strong as they
// could be.
pragma solidity ^0.8.23;

/// @title LlamaRelativeStrategyBase Interface
/// @author Llama (devsdosomething@llama.xyz)
/// @notice This is the interface for LlamaRelativeStrategyBase.
interface ILlamaRelativeStrategyBase {
    type ActionState is uint8;

    struct ActionInfo {
        uint256 id;
        address creator;
        uint8 creatorRole;
        address strategy;
        address target;
        uint256 value;
        bytes data;
    }

    error CannotCancelInState(ActionState currentState);
    error DisapprovalDisabled();
    error InvalidActionInfo();
    error InvalidMinApprovalPct(uint256 minApprovalPct);
    error InvalidRole(uint8 role);
    error OnlyActionCreator();
    error RoleHasZeroSupply(uint8 role);
    error RoleNotInitialized(uint8 role);
    error UnsafeCast(uint256 n);

    event Initialized(uint8 version);

    function approvalEndTime(ActionInfo memory actionInfo) external view returns (uint256);
    function approvalPeriod() external view returns (uint64);
    function approvalRole() external view returns (uint8);
    function checkIfApprovalEnabled(ActionInfo memory, address, uint8 role) external view;
    function checkIfDisapprovalEnabled(ActionInfo memory, address, uint8 role) external view;
    function disapprovalRole() external view returns (uint8);
    function expirationPeriod() external view returns (uint64);
    function forceApprovalRole(uint8 role) external view returns (bool isForceApproval);
    function forceDisapprovalRole(uint8 role) external view returns (bool isForceDisapproval);
    function getApprovalQuantityAt(address policyholder, uint8 role, uint256 timestamp)
        external
        view
        returns (uint96);
    function getApprovalSupply(ActionInfo memory actionInfo) external view returns (uint96);
    function getDisapprovalQuantityAt(address policyholder, uint8 role, uint256 timestamp)
        external
        view
        returns (uint96);
    function getDisapprovalSupply(ActionInfo memory actionInfo) external view returns (uint96);
    function initialize(bytes memory config) external returns (bool);
    function isActionActive(ActionInfo memory actionInfo) external view returns (bool);
    function isActionApproved(ActionInfo memory actionInfo) external view returns (bool);
    function isActionDisapproved(ActionInfo memory actionInfo) external view returns (bool);
    function isActionExpired(ActionInfo memory actionInfo) external view returns (bool);
    function isFixedLengthApprovalPeriod() external view returns (bool);
    function llamaCore() external view returns (address);
    function minApprovalPct() external view returns (uint16);
    function minDisapprovalPct() external view returns (uint16);
    function minExecutionTime(ActionInfo memory) external view returns (uint64);
    function policy() external view returns (address);
    function queuingPeriod() external view returns (uint64);
    function validateActionCancelation(ActionInfo memory actionInfo, address caller) external view;
    function validateActionCreation(ActionInfo memory actionInfo) external view;
}

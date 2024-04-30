// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IProtocolRewards {
  error ADDRESS_ZERO();
  error ARRAY_LENGTH_MISMATCH();
  error INVALID_DEPOSIT();
  error INVALID_SIGNATURE();
  error INVALID_WITHDRAW();
  error InvalidShortString();
  error SIGNATURE_DEADLINE_EXPIRED();
  error StringTooLong(string str);
  error TRANSFER_FAILED();

  event Deposit(address indexed from, address indexed to, bytes4 indexed reason, uint256 amount, string comment);
  event EIP712DomainChanged();
  event RewardsDeposit(
    address indexed creator,
    address indexed createReferral,
    address indexed mintReferral,
    address firstMinter,
    address zora,
    address from,
    uint256 creatorReward,
    uint256 createReferralReward,
    uint256 mintReferralReward,
    uint256 firstMinterReward,
    uint256 zoraReward
  );
  event Withdraw(address indexed from, address indexed to, uint256 amount);

  function WITHDRAW_TYPEHASH() external view returns (bytes32);

  function balanceOf(address) external view returns (uint256);

  function deposit(address to, bytes4 reason, string memory comment) external payable;

  function depositBatch(
    address[] memory recipients,
    uint256[] memory amounts,
    bytes4[] memory reasons,
    string memory comment
  ) external payable;

  function depositRewards(
    address creator,
    uint256 creatorReward,
    address createReferral,
    uint256 createReferralReward,
    address mintReferral,
    uint256 mintReferralReward,
    address firstMinter,
    uint256 firstMinterReward,
    address zora,
    uint256 zoraReward
  ) external payable;

  function eip712Domain()
    external
    view
    returns (
      bytes1 fields,
      string memory name,
      string memory version,
      uint256 chainId,
      address verifyingContract,
      bytes32 salt,
      uint256[] memory extensions
    );

  function nonces(address) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function withdraw(address to, uint256 amount) external;

  function withdrawFor(address to, uint256 amount) external;

  function withdrawWithSig(address from, address to, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFengFaucet {
    event Claimed(address indexed recipient, address indexed dispenser, uint256 ethAmount, uint256 usdgAmount);
    event ParamsSet(uint256 ethPerClaim, uint256 usdgPerClaim, uint256 dailyCap);
    event EthWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error AlreadyClaimed(address recipient);
    error DailyCapReached(uint256 dailyCap);
    error FaucetEmpty();
    error RecipientIsContract(address recipient);
    error TransferFailed();

    function DISPENSER_ROLE() external view returns (bytes32);
    function usdg() external view returns (address);
    function ethPerClaim() external view returns (uint256);
    function usdgPerClaim() external view returns (uint256);
    function dailyCap() external view returns (uint256);
    function hasClaimed(address recipient) external view returns (bool);
    function claimsToday() external view returns (uint256);
    function currentDay() external view returns (uint256);

    function claimFor(address recipient) external;
    function setParams(uint256 ethPerClaim_, uint256 usdgPerClaim_, uint256 dailyCap_) external;
    function withdrawEth(address payable to, uint256 amount) external;
    receive() external payable;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct Constituent {
    address token;
    uint16 targetWeightBps;
    bool isStrategyToken;
}

interface IStrategyVault {
    event Deposit(address indexed sender, address indexed receiver, uint256 usdgAmount, uint256 shares);
    event Redeem(
        address indexed sender, address indexed receiver, address indexed owner, uint256 shares, uint256 usdgAmount
    );
    event Rebalanced(uint256 indexed timestamp, bool timeBased, bool thresholdBased);

    function deposit(uint256 usdgAmount, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 usdgAmount);

    function previewDeposit(uint256 usdgAmount) external view returns (uint256 shares);

    function previewRedeem(uint256 shares) external view returns (uint256 usdgAmount);

    function totalAssetsUSDG() external view returns (uint256);

    function getConstituents() external view returns (Constituent[] memory);

    function depth() external view returns (uint8);

    function rebalanceNeeded() external view returns (bool timeBased, bool thresholdBased);

    function executeRebalance() external;
}

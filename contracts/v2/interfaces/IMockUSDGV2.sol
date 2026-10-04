// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMockUSDGV2 {
    function MINTER_ROLE() external view returns (bytes32);
    function mint(address to, uint256 amount) external;
    function decimals() external view returns (uint8);
}

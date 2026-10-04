// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStrategyTokenV2 {
    error NotVault();
    error ZeroAddress();

    function vault() external view returns (address);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function burnFrom(address owner, address spender, uint256 amount) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVenue} from "./IVenue.sol";

interface IRegistryGate {
    function isRegistered(address vault) external view returns (bool);
}

interface IOracleDesk is IVenue {
    enum Mode {
        Unsupported,
        Mint,
        Inventory
    }

    event TokenConfigured(address indexed token, Mode mode, uint8 decimals);
    event SpreadSet(uint16 spreadBps);
    event ReserveFunded(address indexed from, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event InventoryFunded(address indexed token, address indexed from, uint256 amount);
    event InventoryWithdrawn(address indexed token, address indexed to, uint256 amount);

    error SpreadTooHigh(uint16 spreadBps);
    error NotConfigured(address token);
    error DecimalsTooHigh(address token, uint8 decimals);

    function owner() external view returns (address);
    function oracle() external view returns (address);
    function registry() external view returns (address);
    function maxPriceStaleness() external view returns (uint256);
    function spreadBps() external view returns (uint16);
    function mode(address token) external view returns (Mode);
    function tokenDecimals(address token) external view returns (uint8);
    function reserveUsdg() external view returns (uint256);
    function tokenInventory(address token) external view returns (uint256);
    function accounting()
        external
        view
        returns (uint256 fundedUsdg, uint256 withdrawnUsdg, uint256 buyUsdgIn, uint256 sellUsdgOut);

    function setToken(address token, Mode mode_) external;
    function setSpreadBps(uint16 spreadBps_) external;
    function fundReserve(uint256 amount) external;
    function withdrawReserve(address to, uint256 amount) external;
    function fundInventory(address token, uint256 amount) external;
    function withdrawInventory(address token, address to, uint256 amount) external;
}

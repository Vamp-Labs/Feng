// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";

interface IPriceOracleV2 is IPriceOracle {
    function isSupported(address token) external view returns (bool);

    function priceDecimals() external view returns (uint8);
}

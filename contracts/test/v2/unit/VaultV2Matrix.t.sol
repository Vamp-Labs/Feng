// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultV2Base} from "./VaultV2Base.sol";

contract VaultV2_U6_S18 is VaultV2Base {
    constructor() {
        cfgUsdg = 6;
        cfgStock = 18;
    }
}

contract VaultV2_U18_S18 is VaultV2Base {
    constructor() {
        cfgUsdg = 18;
        cfgStock = 18;
    }
}

contract VaultV2_U6_S8 is VaultV2Base {
    constructor() {
        cfgUsdg = 6;
        cfgStock = 8;
    }
}

contract VaultV2_U18_S8 is VaultV2Base {
    constructor() {
        cfgUsdg = 18;
        cfgStock = 8;
    }
}

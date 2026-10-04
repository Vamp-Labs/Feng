// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVenue} from "../../../v2/interfaces/IVenue.sol";

contract FakeVault {
    function depth() external pure returns (uint8) {
        return 1;
    }

    function swap(address venue, address tin, address tout, uint256 amt, uint256 minOut, address to)
        external
        returns (uint256)
    {
        IERC20(tin).approve(venue, amt);
        return IVenue(venue).swapExactIn(tin, tout, amt, minOut, to);
    }
}

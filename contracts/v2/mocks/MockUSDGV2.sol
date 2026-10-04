// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMockUSDGV2} from "../interfaces/IMockUSDGV2.sol";

contract MockUSDGV2 is ERC20, AccessControl, IMockUSDGV2 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint8 private immutable _decimals;

    error ZeroAddress();

    constructor(address admin, uint8 decimals_) ERC20("Mock Global Dollar", "USDG") {
        if (admin == address(0)) revert ZeroAddress();
        _decimals = decimals_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function decimals() public view override(ERC20, IMockUSDGV2) returns (uint8) {
        return _decimals;
    }
}

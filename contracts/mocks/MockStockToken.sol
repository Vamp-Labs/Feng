// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMintableStockToken} from "../interfaces/IMintableStockToken.sol";

contract MockStockToken is ERC20, AccessControl, IMintableStockToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private immutable _uiMultiplier;

    constructor(string memory name_, string memory symbol_, address admin, uint256 uiMultiplier_)
        ERC20(name_, symbol_)
    {
        require(admin != address(0), "zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _uiMultiplier = uiMultiplier_;
    }

    function uiMultiplier() external view returns (uint256) {
        return _uiMultiplier;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
}

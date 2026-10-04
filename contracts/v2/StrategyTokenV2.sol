// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IStrategyTokenV2} from "./interfaces/IStrategyTokenV2.sol";

contract StrategyTokenV2 is ERC20, IStrategyTokenV2 {
    address public immutable vault;

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(string memory name_, string memory symbol_, address vault_) ERC20(name_, symbol_) {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
    }

    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }

    function burnFrom(address owner, address spender, uint256 amount) external onlyVault {
        _spendAllowance(owner, spender, amount);
        _burn(owner, amount);
    }
}

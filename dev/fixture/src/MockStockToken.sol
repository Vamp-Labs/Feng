// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockStockToken is ERC20, Ownable {
    mapping(address => bool) public isMinter;

    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC20(name_, symbol_)
        Ownable(initialOwner)
    {
        _mint(msg.sender, 1_000_000 ether);
    }

    function setMinter(address account, bool allowed) external onlyOwner {
        isMinter[account] = allowed;
    }

    function mint(address to, uint256 amount) external {
        require(isMinter[msg.sender], "not minter");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(isMinter[msg.sender], "not minter");
        _burn(from, amount);
    }

    function uiMultiplier() external pure returns (uint256) {
        return 1 ether;
    }
}

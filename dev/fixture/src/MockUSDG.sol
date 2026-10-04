// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDG is ERC20 {
    constructor() ERC20("Mock Global Dollar", "USDG") {
        _mint(msg.sender, 10_000_000 ether);
    }

    function faucet(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}

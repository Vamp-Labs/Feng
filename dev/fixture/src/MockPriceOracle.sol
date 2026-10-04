// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockPriceOracle is Ownable {
    mapping(address => uint256) public priceOf;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setPrice(address token, uint256 price) external onlyOwner {
        priceOf[token] = price;
    }

    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt) {
        return (priceOf[token], block.timestamp);
    }
}

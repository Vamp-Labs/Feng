// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFengFaucet} from "../interfaces/IFengFaucet.sol";
import {IMockUSDGV2} from "../interfaces/IMockUSDGV2.sol";

contract FengFaucet is IFengFaucet, AccessControl, ReentrancyGuard {
    bytes32 public constant DISPENSER_ROLE = keccak256("DISPENSER_ROLE");

    address public immutable usdg;

    uint256 public ethPerClaim;
    uint256 public usdgPerClaim;
    uint256 public dailyCap;

    uint256 private _day;
    uint256 private _claimsInDay;
    mapping(address => bool) public hasClaimed;

    constructor(address admin, address usdg_, uint256 ethPerClaim_, uint256 usdgPerClaim_, uint256 dailyCap_) {
        if (admin == address(0) || usdg_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        usdg = usdg_;
        ethPerClaim = ethPerClaim_;
        usdgPerClaim = usdgPerClaim_;
        dailyCap = dailyCap_;
        emit ParamsSet(ethPerClaim_, usdgPerClaim_, dailyCap_);
    }

    receive() external payable {}

    function claimFor(address recipient) external onlyRole(DISPENSER_ROLE) nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        if (recipient.code.length != 0) revert RecipientIsContract(recipient);
        if (hasClaimed[recipient]) revert AlreadyClaimed(recipient);

        uint256 today = currentDay();
        if (today != _day) {
            _day = today;
            _claimsInDay = 0;
        }
        if (_claimsInDay >= dailyCap) revert DailyCapReached(dailyCap);
        uint256 ethAmount = ethPerClaim;
        if (address(this).balance < ethAmount) revert FaucetEmpty();

        hasClaimed[recipient] = true;
        _claimsInDay += 1;

        uint256 usdgAmount = usdgPerClaim;
        IMockUSDGV2(usdg).mint(recipient, usdgAmount);
        (bool ok,) = recipient.call{value: ethAmount}("");
        if (!ok) revert TransferFailed();

        emit Claimed(recipient, msg.sender, ethAmount, usdgAmount);
    }

    function setParams(uint256 ethPerClaim_, uint256 usdgPerClaim_, uint256 dailyCap_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        ethPerClaim = ethPerClaim_;
        usdgPerClaim = usdgPerClaim_;
        dailyCap = dailyCap_;
        emit ParamsSet(ethPerClaim_, usdgPerClaim_, dailyCap_);
    }

    function withdrawEth(address payable to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit EthWithdrawn(to, amount);
    }

    function claimsToday() external view returns (uint256) {
        return currentDay() == _day ? _claimsInDay : 0;
    }

    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }
}

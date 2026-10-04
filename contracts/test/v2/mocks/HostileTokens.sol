// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract TestToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint8 private immutable _dec;

    constructor(string memory name_, string memory symbol_, uint8 dec_) ERC20(name_, symbol_) {
        _dec = dec_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function uiMultiplier() external pure returns (uint256) {
        return 1e18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
}

contract ReentrantToken is TestToken {
    address public hookTarget;
    bytes[] public payloads;
    bool public armed;
    uint256 public attempts;
    uint256 public successes;
    bytes4[] public failureSelectors;
    bool private _inHook;

    constructor(string memory name_, string memory symbol_, uint8 dec_) TestToken(name_, symbol_, dec_) {}

    function arm(address target, bytes[] calldata calls) external {
        hookTarget = target;
        delete payloads;
        for (uint256 i = 0; i < calls.length; i++) {
            payloads.push(calls[i]);
        }
        armed = true;
        attempts = 0;
        successes = 0;
        delete failureSelectors;
    }

    function disarm() external {
        armed = false;
    }

    function failureCount() external view returns (uint256) {
        return failureSelectors.length;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (armed && !_inHook && from != address(0) && to != address(0)) {
            _inHook = true;
            for (uint256 i = 0; i < payloads.length; i++) {
                attempts++;
                (bool ok, bytes memory ret) = hookTarget.call(payloads[i]);
                if (ok) {
                    successes++;
                } else {
                    bytes4 sel;
                    if (ret.length >= 4) {
                        assembly {
                            sel := mload(add(ret, 32))
                        }
                    }
                    failureSelectors.push(sel);
                }
            }
            _inHook = false;
        }
    }
}

contract BlocklistToken is TestToken {
    mapping(address => bool) public blocked;
    bool public globalPause;

    error Blocked(address who);
    error TokenPaused();

    constructor(string memory name_, string memory symbol_, uint8 dec_) TestToken(name_, symbol_, dec_) {}

    function setBlocked(address who, bool b) external {
        blocked[who] = b;
    }

    function setPaused(bool p) external {
        globalPause = p;
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        if (globalPause) revert TokenPaused();
        if (blocked[msg.sender]) revert Blocked(msg.sender);
        if (blocked[spender]) revert Blocked(spender);
        return super.approve(spender, value);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            if (globalPause) revert TokenPaused();
            if (blocked[from]) revert Blocked(from);
            if (blocked[to]) revert Blocked(to);
        }
        super._update(from, to, value);
    }
}

contract FeeOnTransferToken is TestToken {
    uint256 public feeBps;

    constructor(string memory name_, string memory symbol_, uint8 dec_) TestToken(name_, symbol_, dec_) {}

    function setFeeBps(uint256 bps) external {
        feeBps = bps;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && feeBps > 0) {
            uint256 fee = (value * feeBps) / 10_000;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}

contract RebasingToken is ERC20 {
    uint256 private _multiplierBps = 10_000;
    mapping(address => uint256) private _raw;
    uint256 private _rawSupply;
    uint8 private immutable _dec;

    constructor(string memory name_, string memory symbol_, uint8 dec_) ERC20(name_, symbol_) {
        _dec = dec_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function rebase(uint256 newMultiplierBps) external {
        _multiplierBps = newMultiplierBps;
    }

    function mint(address to, uint256 amount) external {
        uint256 raw = (amount * 10_000) / _multiplierBps;
        _raw[to] += raw;
        _rawSupply += raw;
        emit Transfer(address(0), to, amount);
    }

    function totalSupply() public view override returns (uint256) {
        return (_rawSupply * _multiplierBps) / 10_000;
    }

    function balanceOf(address a) public view override returns (uint256) {
        return (_raw[a] * _multiplierBps) / 10_000;
    }

    function _update(address from, address to, uint256 value) internal override {
        uint256 raw = (value * 10_000) / _multiplierBps;
        if (from != address(0)) {
            _raw[from] -= raw;
        }
        if (to != address(0)) {
            _raw[to] += raw;
        }
        emit Transfer(from, to, value);
    }
}

contract NoReturnToken {
    string public name = "NoReturn";
    string public symbol = "NRT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract ReturnFalseToken is TestToken {
    bool public failing;

    constructor(string memory name_, string memory symbol_, uint8 dec_) TestToken(name_, symbol_, dec_) {}

    function setFailing(bool f) external {
        failing = f;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (failing) return false;
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (failing) return false;
        return super.transferFrom(from, to, value);
    }
}

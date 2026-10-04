// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct Constituent {
    address token;
    uint16 targetWeightBps;
    bool isStrategyToken;
}

interface IMintableBurnable {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt);
}

interface IStrategyToken {
    function vault() external view returns (address);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

interface IStrategyVaultExternal {
    function deposit(uint256 usdgAmount, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 usdgAmount);
    function totalAssetsUSDG() external view returns (uint256);
    function depth() external view returns (uint8);
}

contract StrategyVault {
    address public immutable factory;
    address public immutable usdg;
    address public immutable oracle;
    address public token;
    uint8 public immutable depth;
    uint16 public immutable maxWeightBps;
    uint256 public immutable rebalanceInterval;
    uint256 public lastRebalanceAt;

    Constituent[] private _constituents;

    event Deposit(address indexed sender, address indexed receiver, uint256 usdgAmount, uint256 shares);
    event Redeem(
        address indexed sender, address indexed receiver, address indexed owner, uint256 shares, uint256 usdgAmount
    );
    event Rebalanced(uint256 indexed timestamp, bool timeBased, bool thresholdBased);

    constructor(
        address factory_,
        address usdg_,
        address oracle_,
        Constituent[] memory constituents_,
        uint16 maxWeightBps_,
        uint256 rebalanceInterval_,
        uint8 depth_
    ) {
        factory = factory_;
        usdg = usdg_;
        oracle = oracle_;
        maxWeightBps = maxWeightBps_;
        rebalanceInterval = rebalanceInterval_;
        depth = depth_;
        lastRebalanceAt = block.timestamp;
        for (uint256 i = 0; i < constituents_.length; i++) {
            _constituents.push(constituents_[i]);
        }
    }

    function setToken(address token_) external {
        require(msg.sender == factory, "not factory");
        require(token == address(0), "token already set");
        token = token_;
    }

    function getConstituents() external view returns (Constituent[] memory) {
        return _constituents;
    }

    function _priceOf(address t) internal view returns (uint256) {
        (uint256 price,) = IPriceOracle(oracle).getPrice(t);
        return price;
    }

    function totalAssetsUSDG() public view returns (uint256 total) {
        total = IERC20(usdg).balanceOf(address(this));
        for (uint256 i = 0; i < _constituents.length; i++) {
            if (!_constituents[i].isStrategyToken) continue;
            address nestedToken = _constituents[i].token;
            address nestedVault = IStrategyToken(nestedToken).vault();
            uint256 nestedSupply = IERC20(nestedToken).totalSupply();
            if (nestedSupply == 0) continue;
            uint256 nestedShares = IERC20(nestedToken).balanceOf(address(this));
            total += (nestedShares * IStrategyVaultExternal(nestedVault).totalAssetsUSDG()) / nestedSupply;
        }
    }

    function previewDeposit(uint256 usdgAmount) public view returns (uint256 shares) {
        uint256 supply = token == address(0) ? 0 : IERC20(token).totalSupply();
        uint256 assets = totalAssetsUSDG();
        if (supply == 0 || assets == 0) return usdgAmount;
        return (usdgAmount * supply) / assets;
    }

    function previewRedeem(uint256 shares) public view returns (uint256 usdgAmount) {
        uint256 supply = token == address(0) ? 0 : IERC20(token).totalSupply();
        if (supply == 0) return 0;
        return (shares * totalAssetsUSDG()) / supply;
    }

    function rebalanceNeeded() public view returns (bool timeBased, bool thresholdBased) {
        timeBased = block.timestamp >= lastRebalanceAt + rebalanceInterval;
        thresholdBased = false;
    }

    function deposit(uint256 usdgAmount, address receiver) external returns (uint256 shares) {
        require(usdgAmount > 0, "zero amount");
        shares = previewDeposit(usdgAmount);
        require(IERC20(usdg).transferFrom(msg.sender, address(this), usdgAmount), "transferFrom failed");
        _acquireBasket(usdgAmount);
        IStrategyToken(token).mint(receiver, shares);
        emit Deposit(msg.sender, receiver, usdgAmount, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 usdgAmount) {
        require(msg.sender == owner, "not owner");
        require(shares > 0, "zero shares");
        usdgAmount = previewRedeem(shares);
        IStrategyToken(token).burn(owner, shares);
        _liquidateBasket(usdgAmount);
        require(IERC20(usdg).transfer(receiver, usdgAmount), "transfer failed");
        emit Redeem(msg.sender, receiver, owner, shares, usdgAmount);
    }

    function _acquireBasket(uint256 usdgAmount) internal {
        for (uint256 i = 0; i < _constituents.length; i++) {
            Constituent memory c = _constituents[i];
            uint256 share = (usdgAmount * c.targetWeightBps) / 10_000;
            if (share == 0) continue;
            if (c.isStrategyToken) {
                address nestedVault = IStrategyToken(c.token).vault();
                IERC20(usdg).approve(nestedVault, share);
                IStrategyVaultExternal(nestedVault).deposit(share, address(this));
            } else {
                uint256 price = _priceOf(c.token);
                if (price == 0) continue;
                IMintableBurnable(c.token).mint(address(this), (share * 1 ether) / price);
            }
        }
    }

    function _liquidateBasket(uint256 usdgAmount) internal {
        for (uint256 i = 0; i < _constituents.length; i++) {
            Constituent memory c = _constituents[i];
            uint256 share = (usdgAmount * c.targetWeightBps) / 10_000;
            if (share == 0) continue;
            if (c.isStrategyToken) {
                address nestedVault = IStrategyToken(c.token).vault();
                uint256 nestedSupply = IERC20(c.token).totalSupply();
                uint256 nestedAssets = nestedSupply > 0 ? IStrategyVaultExternal(nestedVault).totalAssetsUSDG() : 0;
                uint256 nestedShares = nestedAssets > 0 ? (share * nestedSupply) / nestedAssets : 0;
                uint256 held = IERC20(c.token).balanceOf(address(this));
                if (nestedShares > held) nestedShares = held;
                if (nestedShares > 0) {
                    IStrategyVaultExternal(nestedVault).redeem(nestedShares, address(this), address(this));
                }
            } else {
                uint256 price = _priceOf(c.token);
                if (price == 0) continue;
                uint256 tokenAmount = (share * 1 ether) / price;
                uint256 held = IERC20(c.token).balanceOf(address(this));
                if (tokenAmount > held) tokenAmount = held;
                if (tokenAmount > 0) {
                    IMintableBurnable(c.token).burn(address(this), tokenAmount);
                }
            }
        }
    }

    function executeRebalance() external {
        (bool timeBased, bool thresholdBased) = rebalanceNeeded();
        require(timeBased || thresholdBased, "rebalance not needed");
        lastRebalanceAt = block.timestamp;
        emit Rebalanced(block.timestamp, timeBased, thresholdBased);
    }
}

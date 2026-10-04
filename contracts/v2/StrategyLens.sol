// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constituent} from "../interfaces/IStrategyVault.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IVenue} from "./interfaces/IVenue.sol";
import {IStrategyTokenV2} from "./interfaces/IStrategyTokenV2.sol";
import {IStrategyVaultV2} from "./interfaces/IStrategyVaultV2.sol";

contract StrategyLens {
    function quoteRedeem(address vault, uint256 shares) public view returns (uint256 usdgOut) {
        IStrategyVaultV2 v = IStrategyVaultV2(vault);
        uint256 supply = IERC20(v.token()).totalSupply();
        if (supply == 0) return 0;
        address usdg = v.usdgToken();
        usdgOut = Math.mulDiv(IERC20(usdg).balanceOf(vault), shares, supply);
        Constituent[] memory cs = v.getConstituents();
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 part = Math.mulDiv(IERC20(cs[i].token).balanceOf(vault), shares, supply);
            if (part == 0) continue;
            if (cs[i].isStrategyToken) {
                address child = IStrategyTokenV2(cs[i].token).vault();
                if (IStrategyVaultV2(child).previewRedeem(part) != 0) usdgOut += quoteRedeem(child, part);
            } else if (_oracleValue(v, cs[i].token, part) != 0) {
                usdgOut += IVenue(v.venue()).quoteExactIn(cs[i].token, usdg, part);
            }
        }
    }

    function previewRedeemInKind(address vault, uint256 shares)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        IStrategyVaultV2 v = IStrategyVaultV2(vault);
        uint256 supply = IERC20(v.token()).totalSupply();
        Constituent[] memory cs = v.getConstituents();
        uint256 n = cs.length;
        tokens = new address[](n + 1);
        amounts = new uint256[](n + 1);
        for (uint256 i = 0; i < n; i++) {
            tokens[i] = cs[i].token;
        }
        tokens[n] = v.usdgToken();
        if (supply == 0) return (tokens, amounts);
        for (uint256 i = 0; i <= n; i++) {
            amounts[i] = Math.mulDiv(IERC20(tokens[i]).balanceOf(vault), shares, supply);
        }
    }

    function _oracleValue(IStrategyVaultV2 v, address asset, uint256 amount) private view returns (uint256) {
        (uint256 price,) = IPriceOracle(v.priceOracle()).getPrice(asset);
        return Math.mulDiv(amount, price, 10 ** (uint256(IERC20Metadata(asset).decimals()) + 18 - v.usdgDecimals()));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVaultDeployerV2} from "./interfaces/IStrategyFactoryV2.sol";
import {VaultParams} from "./interfaces/IStrategyVaultV2.sol";
import {StrategyVaultV2} from "./StrategyVaultV2.sol";

contract VaultDeployerV2 is IVaultDeployerV2 {
    function deploy(VaultParams calldata) external returns (address vault, address token) {
        bytes memory initCode = bytes.concat(type(StrategyVaultV2).creationCode, msg.data[4:]);
        assembly {
            vault := create(0, add(initCode, 0x20), mload(initCode))
            if iszero(vault) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        token = StrategyVaultV2(vault).token();
    }
}

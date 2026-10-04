// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IMarketplaceRegistryV2, StrategyInfoV2, StrategyMeta} from "./interfaces/IMarketplaceRegistryV2.sol";
import {IStrategyVaultV2} from "./interfaces/IStrategyVaultV2.sol";

contract MarketplaceRegistryV2 is AccessControl, IMarketplaceRegistryV2 {
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    uint256 public constant MAX_DESCRIPTION_BYTES = 160;
    uint256 public constant MAX_TAGS = 3;
    uint256 public constant MAX_TAG_BYTES = 16;

    struct Record {
        address token;
        address creator;
        uint8 depth;
        uint256 createdAt;
        string description;
        string[] tags;
    }

    address[] private _strategies;
    mapping(address => Record) private _records;

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function registerStrategy(address vault, address token, address creator, StrategyMeta calldata meta)
        external
        onlyRole(FACTORY_ROLE)
    {
        Record storage r = _records[vault];
        if (r.createdAt != 0) revert AlreadyRegistered();
        _validateMeta(meta);
        _strategies.push(vault);
        r.token = token;
        r.creator = creator;
        r.depth = IStrategyVaultV2(vault).depth();
        r.createdAt = block.timestamp;
        _storeMeta(r, meta);
        emit StrategyRegistered(vault, token, creator);
        emit MetaUpdated(vault, meta.description, meta.tags);
    }

    function updateMeta(address vault, StrategyMeta calldata meta) external {
        Record storage r = _records[vault];
        if (r.createdAt == 0) revert NotRegistered();
        if (r.creator != msg.sender) revert NotCreator();
        _validateMeta(meta);
        _storeMeta(r, meta);
        emit MetaUpdated(vault, meta.description, meta.tags);
    }

    function getAllStrategies() external view returns (address[] memory) {
        return _strategies;
    }

    function getStrategies(uint256 offset, uint256 limit) external view returns (address[] memory vaults) {
        uint256 count = _strategies.length;
        if (offset >= count) return new address[](0);
        uint256 end = offset + limit;
        if (end > count || end < offset) end = count;
        vaults = new address[](end - offset);
        for (uint256 i = 0; i < vaults.length; i++) {
            vaults[i] = _strategies[offset + i];
        }
    }

    function strategyCount() external view returns (uint256) {
        return _strategies.length;
    }

    function isRegistered(address vault) external view returns (bool) {
        return _records[vault].createdAt != 0;
    }

    function getStrategyInfo(address vault)
        external
        view
        returns (address token, address creator, uint8 depth, uint256 createdAt)
    {
        Record storage r = _records[vault];
        if (r.createdAt == 0) revert NotRegistered();
        return (r.token, r.creator, r.depth, r.createdAt);
    }

    function getStrategyInfoV2(address vault) external view returns (StrategyInfoV2 memory) {
        Record storage r = _records[vault];
        if (r.createdAt == 0) revert NotRegistered();
        return StrategyInfoV2(vault, r.token, r.creator, r.depth, r.createdAt, r.description, r.tags);
    }

    function getStrategyMeta(address vault) external view returns (StrategyMeta memory) {
        Record storage r = _records[vault];
        if (r.createdAt == 0) revert NotRegistered();
        return StrategyMeta(r.description, r.tags);
    }

    function _storeMeta(Record storage r, StrategyMeta calldata meta) private {
        r.description = meta.description;
        delete r.tags;
        for (uint256 i = 0; i < meta.tags.length; i++) {
            r.tags.push(meta.tags[i]);
        }
    }

    function _validateMeta(StrategyMeta calldata meta) private pure {
        if (bytes(meta.description).length > MAX_DESCRIPTION_BYTES) revert DescriptionTooLong();
        uint256 n = meta.tags.length;
        if (n > MAX_TAGS) revert TooManyTags();
        for (uint256 i = 0; i < n; i++) {
            bytes calldata tag = bytes(meta.tags[i]);
            if (tag.length == 0 || tag.length > MAX_TAG_BYTES) revert InvalidTag();
            for (uint256 k = 0; k < tag.length; k++) {
                bytes1 ch = tag[k];
                bool ok = (ch >= 0x61 && ch <= 0x7a) || (ch >= 0x30 && ch <= 0x39) || ch == 0x2d;
                if (!ok) revert InvalidTag();
            }
            for (uint256 j = i + 1; j < n; j++) {
                if (keccak256(bytes(meta.tags[j])) == keccak256(tag)) revert DuplicateTag();
            }
        }
    }
}

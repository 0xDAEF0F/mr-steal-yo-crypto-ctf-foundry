// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMoneyMarket {
    function _supportMarket(address asset) external returns (uint256);
    function supply(address asset, uint256 amount) external returns (uint256);
    function withdraw(address asset, uint256 requestedAmount) external returns (uint256);
}

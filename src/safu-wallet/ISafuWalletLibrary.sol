// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISafuWalletLibrary {
    function initWallet(address[] calldata _owners, uint256 _required, uint256 _daylimit) external;
    function initMultiowned(address[] calldata _owners, uint256 _required) external;
    function revoke(bytes32 _operation) external;
    function initDaylimit(uint256 _limit) external;
    function kill(address _to) external;
    function execute(address _to, uint256 _value, bytes calldata _data) external returns (bytes32 o_hash);
    function confirm(bytes32 _h) external returns (bool o_success);
}

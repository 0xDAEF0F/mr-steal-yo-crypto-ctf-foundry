//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";

/// @dev this is the proxy contract
contract SafuWallet {
    using Address for address;

    // FIELDS
    address constant _safuWalletLibrary = 0x3Ede3eCa2a72B3aeCC820E955B36f38437D01395; // logic address

    // the number of owners that must confirm the same operation before it is run.
    uint256 public m_required;
    // pointer used to find a free slot in m_owners
    uint256 public m_numOwners;

    uint256 public m_dailyLimit;
    uint256 public m_spentToday;
    uint256 public m_lastDay;

    // list of owners
    uint256[256] m_owners;

    event Deposit(address _from, uint256 value);

    /// @dev calls the `initWallet` method of the Library in this context
    constructor(address[] memory _owners, uint256 _required, uint256 _daylimit) {
        bytes memory data =
            abi.encodeWithSignature("initWallet(address[],uint256,uint256)", _owners, _required, _daylimit);

        _safuWalletLibrary.functionDelegateCall(data);
    }

    // Gets an owner by 0-indexed position (using numOwners as the count)
    function getOwner(uint256 ownerIndex) external view returns (address) {
        return address(uint160(m_owners[ownerIndex + 1]));
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    fallback() external {
        _safuWalletLibrary.functionDelegateCall(msg.data);
    }
}

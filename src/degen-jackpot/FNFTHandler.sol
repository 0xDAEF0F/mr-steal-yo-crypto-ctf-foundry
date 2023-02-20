// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "./OtherInterfaces.sol";
import "./OtherContracts.sol";

/// @dev Handles storage and management of FNFTs
contract FNFTHandler is ERC1155, AccessControl, RevestAccessControl, IFNFTHandler {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(uint256 => uint256) public supply;
    uint256 public fnftsCreated = 0;

    /**
     * @dev Primary constructor to create an instance of NegativeEntropy
     * Grants ADMIN and MINTER_ROLE to whoever creates the contract
     */
    constructor(address provider) ERC1155("") RevestAccessControl(provider) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        external
        override
        onlyRevestController
    {
        supply[id] += amount;
        _mint(account, id, amount, data);
        fnftsCreated += 1;
    }

    function mintBatchRec(
        address[] calldata recipients,
        uint256[] calldata quantities,
        uint256 id,
        uint256 newSupply,
        bytes memory data
    ) external override onlyRevestController {
        supply[id] += newSupply;
        for (uint256 i = 0; i < quantities.length; i++) {
            _mint(recipients[i], id, quantities[i], data);
        }
        fnftsCreated += 1;
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        external
        override
        onlyRevestController
    {
        _mintBatch(to, ids, amounts, data);
    }

    function burn(address account, uint256 id, uint256 amount) external override onlyRevestController {
        supply[id] -= amount;
        _burn(account, id, amount);
    }

    function burnBatch(address account, uint256[] memory ids, uint256[] memory amounts)
        external
        override
        onlyRevestController
    {
        _burnBatch(account, ids, amounts);
    }

    function getBalance(address account, uint256 id) external view override returns (uint256) {
        return balanceOf(account, id);
    }

    function getSupply(uint256 fnftId) public view override returns (uint256) {
        return supply[fnftId];
    }

    function getNextId() public view override returns (uint256) {
        return fnftsCreated;
    }
}

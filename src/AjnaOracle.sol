// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title AJNA Oracle Ritual Contract
/// @notice Gate ritual with World ID, mint NFT revelations
contract AJNAOracle is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    AccessControlEnumerable,
    Ownable,
    ReentrancyGuard,
    EIP712
{
    using Strings for uint256;
    using ECDSA for bytes32;

    /// Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// Backend signer for voucher redemption
    address public backendSigner;

    /// Mapping to record used nonces
    mapping(uint256 => bool) public usedNonces;

    /// Whitelisted addresses allowed to mint directly
    mapping(address => bool) public whitelist;

    /// Whether whitelist is enabled
    bool public whitelistEnabled;

    /// Typehash for EIP712 voucher
    bytes32 private constant _VOUCHER_TYPEHASH =
        keccak256("Voucher(address to,uint256 nonce,uint256 deadline)");

    /// Counter for token IDs
    uint256 private _nextTokenId;

    /// Base URI / fallback
    string private _baseTokenURI;

    /// Emitted when a ritual is opened and NFT is minted
    event RitualOpened(
        uint256 indexed tokenId,
        uint256 indexed nonce,
        uint256 indexed sacredTimestamp
    );

    /// Emitted when whitelist is toggled
    event WhitelistToggled(bool enabled);

    constructor(
        string memory name_,
        string memory symbol_,
        address backendSigner_,
        string memory baseURI_
    ) 
        ERC721(name_, symbol_)
        Ownable(msg.sender)
        EIP712("AJNAOracle", "1")
    {
        backendSigner = backendSigner_;
        _baseTokenURI = baseURI_;
        whitelistEnabled = true; // Whitelist is enabled by default

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /// @notice Redeem a signed voucher to mint a revelation.
    function redeemVoucher(
        address to,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        uint256 cardId,
        string calldata birthHash,
        string calldata messageCID
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Voucher expired");

        bytes32 structHash = keccak256(abi.encode(_VOUCHER_TYPEHASH, to, nonce, deadline));
        address signer = _hashTypedDataV4(structHash).recover(signature);
        require(signer == backendSigner, "Invalid signature");

        require(!usedNonces[nonce], "Nonce already used");
        usedNonces[nonce] = true;

        uint256 tokenId = _mintRevelation(to, birthHash, messageCID, cardId);
        uint256 sacredTimestamp = block.timestamp;
        emit RitualOpened(tokenId, nonce, sacredTimestamp);
    }

    /// @notice Internal function to handle NFT minting
    function _mintRevelation(
        address to,
        string memory birthHash,
        string memory messageCID,
        uint256 cardId
    ) internal returns (uint256) {
        uint256 tokenId = _nextTokenId++;

        _safeMint(to, tokenId);

        // Construct tokenURI pointing to baseURI + messageCID
        // Assume baseURI ends with trailing slash
        string memory uri = string(abi.encodePacked(_baseTokenURI, messageCID));
        _setTokenURI(tokenId, uri);

        return tokenId;
    }

    /// @notice Set a new base URI for token metadata. Only admin.
    function setBaseURI(string calldata newBaseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
    }

    /// @notice Update the backend signer address. Only admin.
    function setBackendSigner(address newSigner) external onlyRole(ADMIN_ROLE) {
        backendSigner = newSigner;
    }

    /// @notice Add an address to the whitelist. Only owner.
    function addToWhitelist(address account) external onlyOwner {
        whitelist[account] = true;
    }

    /// @notice Remove an address from the whitelist. Only owner.
    function removeFromWhitelist(address account) external onlyOwner {
        whitelist[account] = false;
    }

    /// @notice Toggle whitelist functionality. Only owner.
    function toggleWhitelist() external onlyOwner {
        whitelistEnabled = !whitelistEnabled;
        emit WhitelistToggled(whitelistEnabled);
    }

    /// @notice Mint a revelation directly for whitelisted senders.
    function mintWhitelisted(
        uint256 cardId,
        string calldata birthHash,
        string calldata messageCID
    ) external nonReentrant {
        require(!whitelistEnabled || whitelist[msg.sender], "Not whitelisted");
        uint256 tokenId = _mintRevelation(msg.sender, birthHash, messageCID, cardId);
        uint256 sacredTimestamp = block.timestamp;
        emit RitualOpened(tokenId, 0, sacredTimestamp);
    }

    /// @dev The following functions are overrides required by Solidity.
    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 amount)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, amount);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

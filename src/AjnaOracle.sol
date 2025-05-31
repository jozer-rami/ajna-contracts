// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

// Interface for ERC-6551 Registry
interface IERC6551Registry {
    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes memory initData
    ) external returns (address);
}

/// @title AJNA Oracle Ritual Contract
/// @notice Gate ritual with World ID, mint NFT revelations, integrate ERC-6551
contract AJNAOracle is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlEnumerableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;
    using ECDSAUpgradeable for bytes32;

    /// Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// ERC-6551 Registry & implementation
    IERC6551Registry public erc6551Registry;
    address public erc6551Implementation;

    /// Backend signer for voucher redemption
    address public backendSigner;

    /// Mapping to record used nonces
    mapping(uint256 => bool) public usedNonces;

    /// Whitelisted addresses allowed to mint directly
    mapping(address => bool) public whitelist;

    /// Typehash for EIP712 voucher
    bytes32 private constant _VOUCHER_TYPEHASH = keccak256("Voucher(address to,uint256 nonce,uint256 deadline)");

    /// Counter for token IDs
    CountersUpgradeable.Counter private _tokenIdCounter;

    /// Base URI / fallback
    string private _baseTokenURI;

    /// Per-token data
    mapping(uint256 => string) private _messages;
    mapping(uint256 => string) private _birthHashes;
    mapping(uint256 => uint256) private _cardIds;

    /// Emitted when a ritual is opened and NFT is minted
    event RitualOpened(uint256 indexed tokenId, uint256 indexed nonce, uint256 indexed sacredTimestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        string memory name_,
        string memory symbol_,
        address registryAddress_,
        address implementationAddress_,
        address backendSigner_,
        string memory baseURI_
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __AccessControlEnumerable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __EIP712_init("AJNAOracle", "1");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        erc6551Registry = IERC6551Registry(registryAddress_);
        erc6551Implementation = implementationAddress_;

        backendSigner = backendSigner_;

        _baseTokenURI = baseURI_;
    }

    /// @notice Redeem a signed voucher to mint a revelation.
    function redeemVoucher(
        address to,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        uint256 cardId,
        string calldata birthHash,
        string calldata message
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Voucher expired");

        bytes32 structHash = keccak256(abi.encode(_VOUCHER_TYPEHASH, to, nonce, deadline));
        address signer = _hashTypedDataV4(structHash).recover(signature);
        require(signer == backendSigner, "Invalid signature");

        require(!usedNonces[nonce], "Nonce already used");
        usedNonces[nonce] = true;

        uint256 tokenId = _mintRevelation(to, birthHash, message, cardId);
        uint256 sacredTimestamp = block.timestamp;
        emit RitualOpened(tokenId, nonce, sacredTimestamp);
    }

    /// @notice Internal function to handle NFT minting and ERC-6551 account creation
    function _mintRevelation(address to, string memory birthHash, string memory message, uint256 cardId)
        internal
        returns (uint256)
    {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();

        _safeMint(to, tokenId);

        _messages[tokenId] = message;
        _birthHashes[tokenId] = birthHash;
        _cardIds[tokenId] = cardId;

        // Create ERC-6551 account for this token
        _createTokenBoundAccount(tokenId);

        return tokenId;
    }

    /// @notice Create a token-bound account via ERC-6551 registry
    function _createTokenBoundAccount(uint256 tokenId) internal {
        bytes memory initData = "";
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        erc6551Registry.createAccount(erc6551Implementation, chainId, address(this), tokenId, 0, initData);
    }

    /// @notice Override required by Solidity for UUPS upgradeability
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

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

    /// @notice Mint a revelation directly for whitelisted senders.
    function mintWhitelisted(uint256 cardId, string calldata birthHash, string calldata message)
        external
        nonReentrant
    {
        require(whitelist[msg.sender], "Not whitelisted");
        _mintRevelation(msg.sender, birthHash, message, cardId);
    }

    /// @dev The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        string memory message = _messages[tokenId];
        string memory birthHash = _birthHashes[tokenId];
        uint256 cardId = _cardIds[tokenId];

        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300">',
                '<rect width="100%" height="100%" fill="black"/>',
                '<text x="50%" y="50%" fill="white" font-size="16" dominant-baseline="middle" text-anchor="middle">',
                message,
                "</text></svg>"
            )
        );

        string memory image =
            string(abi.encodePacked("data:image/svg+xml;base64,", Base64Upgradeable.encode(bytes(svg))));

        string memory json = Base64Upgradeable.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"Revelation #',
                        tokenId.toString(),
                        '","description":"Onchain Revelation","attributes":[',
                        '{"trait_type":"Birth Hash","value":"',
                        birthHash,
                        '"},',
                        '{"trait_type":"Card ID","value":"',
                        cardId.toString(),
                        '"}],"image":"',
                        image,
                        '"}'
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(
            ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlEnumerableUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;
}

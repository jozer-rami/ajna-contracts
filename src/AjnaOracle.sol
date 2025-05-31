// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

// Interface for World ID Semaphore Verifier
interface ISemaphoreVerifier {
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifier,
        uint256[8] calldata proof
    ) external view;
}

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
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;

    /// Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// World ID verifier contract
    ISemaphoreVerifier public semaphoreVerifier;
    uint256 public worldIdGroupId;

    /// ERC-6551 Registry & implementation
    IERC6551Registry public erc6551Registry;
    address public erc6551Implementation;

    /// Counter for token IDs
    CountersUpgradeable.Counter private _tokenIdCounter;

    /// Base URI / fallback
    string private _baseTokenURI;

    /// Mapping to record used nullifierHashes (optional, Semaphore already prevents double use per externalNullifier)
    mapping(uint256 => bool) public nullifierHashes;

    /// Emitted when a ritual is opened and NFT is minted
    event RitualOpened(
        uint256 indexed tokenId,
        uint256 indexed nullifierHash,
        uint256 indexed sacredTimestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        string memory name_,
        string memory symbol_,
        address verifierAddress_,
        uint256 groupId_,
        address registryAddress_,
        address implementationAddress_,
        string memory baseURI_
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        semaphoreVerifier = ISemaphoreVerifier(verifierAddress_);
        worldIdGroupId = groupId_;

        erc6551Registry = IERC6551Registry(registryAddress_);
        erc6551Implementation = implementationAddress_;

        _baseTokenURI = baseURI_;
    }

    /// @notice Computes the externalNullifier for today using chain timestamp
    function _todayExternalNullifier() internal view returns (uint256) {
        (uint256 year, uint256 month, uint256 day) = _timestampToDate(block.timestamp);
        return uint256(keccak256(abi.encodePacked("AJNA-DAY-", year, "-", _twoDigit(month), "-", _twoDigit(day))));
    }

    /// @notice Open the ritual: verify World ID proof and mint NFT.
    /// @param proof Semaphore proof array (eight elements)
    /// @param root Merkle root from World ID Merkle tree
    /// @param nullifierHash Nullifier hash for this proof
    /// @param cardId ID of the oracle card selected by user (off-chain)
    /// @param birthHash SHA-256 hash of user birth date and place
    /// @param messageCID CID pointing to JSON metadata (IPFS/Arweave)
    function openRitual(
        uint256[8] calldata proof,
        uint256 root,
        uint256 nullifierHash,
        uint256 cardId,
        string calldata birthHash,
        string calldata messageCID
    ) external nonReentrant {
        uint256 ext = _todayExternalNullifier();

        require(!nullifierHashes[nullifierHash], "Nullifier already used");

        // Construct the signal hash from msg.sender and cardId
        uint256 signalHash = uint256(keccak256(abi.encodePacked(msg.sender, cardId)));

        // Verify proof via World ID semaphore verifier
        semaphoreVerifier.verifyProof(
            root,
            worldIdGroupId,
            signalHash,
            nullifierHash,
            ext,
            proof
        );

        // Mark nullifier as used
        nullifierHashes[nullifierHash] = true;

        // Mint NFT and emit event
        uint256 tokenId = _mintRevelation(msg.sender, birthHash, messageCID, cardId);
        uint256 sacredTimestamp = block.timestamp;
        emit RitualOpened(tokenId, nullifierHash, sacredTimestamp);
    }

    /// @notice Internal function to handle NFT minting and ERC-6551 account creation
    function _mintRevelation(
        address to,
        string memory birthHash,
        string memory messageCID,
        uint256 cardId
    ) internal returns (uint256) {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();

        _safeMint(to, tokenId);

        // Construct tokenURI pointing to baseURI + messageCID
        // Assume baseURI ends with trailing slash
        string memory uri = string(abi.encodePacked(_baseTokenURI, messageCID));
        _setTokenURI(tokenId, uri);

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

        erc6551Registry.createAccount(
            erc6551Implementation,
            chainId,
            address(this),
            tokenId,
            0,
            initData
        );
    }

    /// @notice Override required by Solidity for UUPS upgradeability
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    /// @notice Set a new World ID group ID (root). Only admin.
    function setWorldIdGroupId(uint256 newGroupId) external onlyRole(ADMIN_ROLE) {
        worldIdGroupId = newGroupId;
    }

    /// @notice Set a new Semaphore Verifier address. Only admin.
    function setSemaphoreVerifier(address newVerifier) external onlyRole(ADMIN_ROLE) {
        semaphoreVerifier = ISemaphoreVerifier(newVerifier);
    }

    /// @notice Set a new base URI for token metadata. Only admin.
    function setBaseURI(string calldata newBaseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
    }

    /// @dev Internal helper: converts timestamp to date components (Y, M, D)
    function _timestampToDate(uint256 timestamp) internal pure returns (uint256, uint256, uint256) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = (z >= 0 ? z : z - 146096) / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 y = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 d = doy - (153 * mp + 2) / 5 + 1;
        // Handle month calculation without negative numbers
        uint256 m = mp;
        if (mp < 10) {
            m = mp + 3;
        } else {
            m = mp - 9;
        }
        y += (m <= 2 ? 1 : 0);
        return (y, m, d);
    }

    /// @dev Internal helper: ensures two-digit month/day representation
    function _twoDigit(uint256 num) internal pure returns (string memory) {
        if (num >= 10) {
            return StringsUpgradeable.toString(num);
        } else {
            return string(abi.encodePacked("0", StringsUpgradeable.toString(num)));
        }
    }

    /// @dev The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(
            ERC721Upgradeable,
            ERC721EnumerableUpgradeable,
            ERC721URIStorageUpgradeable,
            AccessControlEnumerableUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;
}

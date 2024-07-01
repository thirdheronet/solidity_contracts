// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ThirdHeroTokens is ERC1155, EIP712, Ownable {
    bytes8 constant LIST_SECTION_ITEMS = "items";
    bytes8 constant LIST_SECTION_CARDS = "cards";

    IERC20 private paymentToken;

    struct Item {
        uint256 id;
        uint256 salePrice;

        bytes8 section;
        address owner;

        string metadata;
        string saciPath; // server/account/character/invetory IDs
    }

    mapping(uint256 => Item) private items;

    bytes8[] private sectionNames; 
    uint256[] private itemIds;

    bytes32 private constant PLAYER_MINT_TYPEHASH =
        keccak256("PlayerMint(address to,bytes8 section,string metadata,string saciPath,uint256 id)");

    event PlayerNewTokenMined(uint256 tokenId, address owner, string metadata, string saciPath);
    event PlayerTokenSold(uint256 tokenId, address oldOwner, address newOwner, string metadata);
    event PlayerTokenWrapped(uint256 tokenId);
    event PlayerTokenUnwrapped(uint256 tokenId, string saciPath);

    constructor(IERC20 _paymentToken) ERC1155("ipfs://") EIP712("ThirdHero", "1") Ownable(msg.sender) {
        // 0x27beC33e82eB9d95367C87842AE306F8dd3aF7bb
        setPaymentToken(_paymentToken);

        addSection(LIST_SECTION_CARDS);
        addSection(LIST_SECTION_ITEMS);
    }

    function _addItem(
        uint256 tokenId, 
        bytes8 section, 
        string memory metadata, 
        string memory saciPath,
        address owner
        ) private {        
            items[tokenId] = Item({
                id: tokenId, 
                salePrice: 0,
                metadata: metadata,
                section: section,
                owner: owner,
                saciPath: saciPath
            });

            itemIds.push(tokenId); 
    }

    function mint(
        address to, 
        bytes8 section, 
        string memory metadata, 
        string memory saciPath,
        uint256 id
        ) private {    
            require(!(id == 0), "Token ID can't be 0!"); 
            require(!(items[id].id > 0), "Token has already been mined!");
 
            bool sectionFound;

            for (uint256 i = 0; i < sectionNames.length; i++) {
                if(section == sectionNames[i]) {
                    sectionFound = true;
                }
            }

            require(sectionFound, "Section doesn't exist.");

            _addItem(id, section, metadata, saciPath, to);
            _mint(to, id, 1, "");
    }

    function serverMint(        
        address to, 
        bytes8 section, 
        string memory metadata, 
        string memory saciPath, 
        uint256 id
        ) public onlyOwner {
            mint(to, section, metadata, saciPath, id);
    }

    function playerMint(
        address to, 
        bytes8 section, 
        string memory metadata, 
        string memory saciPath,
        uint256 id, 
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 structHash = keccak256(
            abi.encode(
                PLAYER_MINT_TYPEHASH, 
                to, 
                section, 
                keccak256(bytes(metadata)), 
                keccak256(bytes(saciPath)), 
                id
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);
   
        require(signer == owner(), "Invalid signature");

        mint(to, section, metadata, saciPath, id);

        emit PlayerNewTokenMined(id, to, metadata, saciPath);
    }

    function addSection(bytes8 name) public onlyOwner {
        bool sectionFound;

        for (uint256 i = 0; i < sectionNames.length; i++) {
            if(name == sectionNames[i]) {
                sectionFound = true;
            }
        }

        require(!sectionFound, "Section already exists.");

        sectionNames.push(name);
    }

    function correctSectionName(bytes8 section, bytes8 newName) public onlyOwner {
        for (uint256 i = 0; i < sectionNames.length; i++) {
            if(section == sectionNames[i]) {
                sectionNames[i] = newName;
            }
        }
    }

    function manageOfferSale(uint256 tokenId, uint256 salePrice) public {
        require(balanceOf(msg.sender, tokenId) != 0, "You don't own this token!");

        items[tokenId].salePrice = salePrice;
        setApprovalForAll(address(this), salePrice != 0);
    }

    function acceptOfferSale(
        uint256 tokenId, 
        uint256 expiration, 
        uint8 v,
        bytes32 r,
        bytes32 s
        ) public {
            uint256 salePrice = items[tokenId].salePrice;

            require(salePrice != 0, "Not for sale!");
            require(balanceOf(items[tokenId].owner, tokenId) > 0, "Wrong seller!");

            IERC20Permit(address(paymentToken)).permit(
                msg.sender,
                address(this),
                salePrice,
                expiration,
                v,
                r,
                s
            );

            require(paymentToken.allowance(msg.sender, items[tokenId].owner) >= salePrice, "Token allowance too low!");
            require(isApprovedForAll(items[tokenId].owner, address(this)), "Not approved manage the token!");
         
            address oldOwner = items[tokenId].owner;

            paymentToken.transferFrom(msg.sender, items[tokenId].owner, salePrice);
            _safeTransferFrom(items[tokenId].owner, msg.sender, tokenId, 1, "");
            manageOfferSale(tokenId, 0);
            items[tokenId].owner = msg.sender;

            emit PlayerTokenSold(
                tokenId, 
                oldOwner, 
                msg.sender, 
                items[tokenId].metadata
            );
    }

    function wrapToken(uint256 tokenId) public
    {
        require(items[tokenId].owner == msg.sender, "You are not owner of the token!");

        items[tokenId].saciPath = "";
        emit PlayerTokenWrapped(tokenId);
    }

    function unwrapToken(uint256 tokenId, string memory saciPath) public
    {
        require(items[tokenId].owner == msg.sender, "You are not owner of the token!");

        items[tokenId].saciPath = saciPath;
        emit PlayerTokenUnwrapped(tokenId, saciPath);
    }

    function setPaymentToken(IERC20 token) public onlyOwner {
        paymentToken = token;
    }

    function uri(uint256 tokenId) public view override returns (string memory) {  
        return items[tokenId].metadata;
    }

    function getItems() public view returns (Item[] memory)
    {
        Item[] memory itemsList = new Item[](itemIds.length);

        for (uint256 i = 0; i < itemIds.length; i++) {
            itemsList[i] = items[itemIds[i]];
        }

        return itemsList;
    }

    function getFilteredItems(bool onlyForSale, bytes8[] memory sections) public view returns (Item[] memory) {
        Item[] memory itemsList = new Item[](itemIds.length);
        bool noSkip;

        for (uint256 i = 0; i < itemIds.length; i++) {
             noSkip = false;

            if(onlyForSale && items[itemIds[i]].salePrice == 0) {
                continue;
            }

            for (uint256 x = 0; x < sections.length; x++) {
                if(items[itemIds[i]].section == sections[x]) {
                    noSkip = true;
                }
            }

            if(noSkip) {
                itemsList[i] = items[itemIds[i]];
            }
        }

        return itemsList;
    }

    function getItemsByOwner(address owner) public view returns (Item[] memory) {
        Item[] memory itemsList = new Item[](itemIds.length);

        for (uint256 i = 0; i < itemIds.length; i++) {
            if(items[itemIds[i]].owner == owner) {
                itemsList[i] = items[itemIds[i]];
            }
        }

        return itemsList;
    }

    function getSections() public view returns(bytes8[] memory) {
        return sectionNames;
    }

    function getListSize() public view returns(uint256) {
        return itemIds.length;
    }

    function getItemsIds() public view returns (uint256[] memory) {
        return itemIds;
    }
    
    function getItem(uint256 tokenId) public view returns (Item memory) {
        return items[tokenId];
    }
}
// SPDX-License-Identifier: MIT
// https://www.thirdhero.net

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./IThirdHeroTokens.sol";

contract ThirdHeroTokens is ERC1155, EIP712, Ownable, IERC721Errors, IERC20Errors, IThirdHeroTokens {
    bytes8 constant private LIST_SECTION_ITEMS = "items";
    bytes8 constant private LIST_SECTION_CARDS = "cards";

    bytes32 constant private PLAYER_MINT_TYPEHASH =
        keccak256("PlayerMint(address to,bytes8 section,string metadata,string saciPath,uint256 id)");

    IERC20 private paymentToken;

    mapping(uint256 => Item) private items;

    bytes8[] private sectionNames; 
    uint256[] private itemIds;

    constructor(IERC20 _paymentToken) ERC1155("ipfs://") EIP712("ThirdHero", "1") Ownable(msg.sender) {
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

    function fixItem(uint256 tokenId, string memory metaData, bytes8 section) public onlyOwner {
        if(items[tokenId].owner != msg.sender) {
            revert NotTokenOwner(tokenId, items[tokenId].owner);
        }

        items[tokenId].metadata = metaData;
        items[tokenId].section = section;
    }

    function mint(
        address to, 
        bytes8 section, 
        string memory metadata, 
        string memory saciPath,
        uint256 id
        ) private {    
            if(id == 0) {
                revert ZeroTokenId();
            }

            if(items[id].id > 0) {
                revert TokenAlreadyMined(id);
            }
 
            bool sectionFound;

            for (uint256 i = 0; i < sectionNames.length; i++) {
                if(section == sectionNames[i]) {
                    sectionFound = true;
                }
            }

            if(!sectionFound) {
                revert SectionDoesntExist(section);
            }

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
            if(to == address(0)) {
                revert ERC1155InvalidReceiver(address(0));
            }

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
        if(to == address(0)) {
            revert ERC1155InvalidReceiver(to);
        }

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
   
        if(signer != owner()) {
           revert InvalidSignature();
        }

        mint(to, section, metadata, saciPath, id);

        emit PlayerNewTokenMined(id, to, metadata, saciPath);
    }

    function burn(uint256 id) public {
        if(items[id].owner != msg.sender) {
            revert NotTokenOwner(id, items[id].owner);
        }

        _burn(items[id].owner, id, 1);

        emit PlayerTokenBurned(id, items[id].owner, items[id].metadata);
    }

    function addSection(bytes8 name) public onlyOwner {
        bool sectionFound;

        for (uint256 i = 0; i < sectionNames.length; i++) {
            if(name == sectionNames[i]) {
                sectionFound = true;
            }
        }

        if(sectionFound) {
            revert SectionAlreadyExists(name);
        }

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
        if(balanceOf(msg.sender, tokenId) == 0) {
            revert ERC721IncorrectOwner(msg.sender, tokenId, items[tokenId].owner);
        }

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

            if(salePrice == 0) {
                revert TokenNotForSale(tokenId);
            }

            if(balanceOf(items[tokenId].owner, tokenId) == 0) {
                revert PoorTokenSeller();
            }
            
            IERC20Permit(address(paymentToken)).permit(
                msg.sender,
                address(this),
                salePrice,
                expiration,
                v,
                r,
                s
            );

            uint256 allowance = paymentToken.allowance(msg.sender, items[tokenId].owner);

            if(allowance < salePrice) {
                revert ERC20InsufficientAllowance(msg.sender, allowance, salePrice);
            }

            if(!isApprovedForAll(items[tokenId].owner, address(this))) {
                revert ERC20InvalidApprover(items[tokenId].owner);
            }
         
            address oldOwner = items[tokenId].owner;

            paymentToken.transferFrom(msg.sender, items[tokenId].owner, salePrice);
            _safeTransferFrom(items[tokenId].owner, msg.sender, tokenId, 1, "");
            manageOfferSale(tokenId, 0);

            items[tokenId].owner = msg.sender;
            items[tokenId].saciPath = "";

            emit PlayerTokenSold(
                tokenId, 
                oldOwner, 
                msg.sender, 
                items[tokenId].metadata
            );
    }

    function equip(uint256 tokenId, string memory saciPath) public
    {
        if(items[tokenId].owner != msg.sender) {
            revert NotTokenOwner(tokenId, items[tokenId].owner);
        }

        string memory oldSaciPath = items[tokenId].saciPath;
        items[tokenId].saciPath = saciPath;

        emit PlayerTokenEquipped(tokenId, items[tokenId].owner, saciPath, oldSaciPath);
    }

    function setPaymentToken(IERC20 token) public onlyOwner {
        paymentToken = token;
    }

    function getPaymentToken() public view returns (IERC20) {
        return paymentToken;
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
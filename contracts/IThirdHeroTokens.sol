// SPDX-License-Identifier: MIT
// https://www.thirdhero.net

pragma solidity ^0.8.20;

interface IThirdHeroTokens {
    event PlayerNewTokenMined(uint256 tokenId, address owner, string metadata, string saciPath);
    event PlayerTokenSold(uint256 tokenId, address oldOwner, address newOwner, string metadata);
    event PlayerTokenEquipped(uint256 tokenId, address owner, string saciPath, string oldSaciPath);
    event PlayerTokenBurned(uint256 tokenId, address owner, string metadata);

    error ZeroTokenId();
    error TokenNotForSale(uint256 id);
    error TokenAlreadyMined(uint256 id);
    error NotTokenOwner(uint256 id, address owner);
    error SectionAlreadyExists(bytes8 name);
    error SectionDoesntExist(bytes8 name);
    error InvalidSignature();
    error PoorTokenSeller();
    
    struct Item {
        uint256 id;
        uint256 salePrice;

        bytes8 section;
        address owner;

        string metadata;
        string saciPath; // server/account/character/invetory IDs
    }
}
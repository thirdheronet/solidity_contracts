// SPDX-License-Identifier: MIT
// https://www.thirdhero.net
        
pragma solidity >=0.4.22 <0.9.0;

import "remix_tests.sol"; 
import "remix_accounts.sol";
import "../contracts/ThirdHeroTokens.sol";

contract testSuite {
    ThirdHeroTokens thirdHeroTokens;

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory addressBytes = abi.encodePacked(_addr);
        bytes memory hexBytes = new bytes(2 + addressBytes.length * 2);

        hexBytes[0] = "0";
        hexBytes[1] = "x";

        bytes memory alphabet = "0123456789abcdef";

        for (uint256 i = 0; i < addressBytes.length; i++) {
            hexBytes[2 + i * 2] = alphabet[uint8(addressBytes[i] >> 4)];
            hexBytes[3 + i * 2] = alphabet[uint8(addressBytes[i] & 0x0f)];
        }

        return string(hexBytes);
    }

    function beforeAll() public {
        thirdHeroTokens = new ThirdHeroTokens(IERC20(0x27beC33e82eB9d95367C87842AE306F8dd3aF7bb));
    }

    function testChangePaymentToken() public {
        Assert.equal(
            address(thirdHeroTokens.getPaymentToken()), 
            0x27beC33e82eB9d95367C87842AE306F8dd3aF7bb, 
            "payment token error!"
        );

        thirdHeroTokens.setPaymentToken(IERC20(0x27BeC33E82Eb9d95367C87842Ae306f8dd3AF7bE));

        Assert.equal(
            address(thirdHeroTokens.getPaymentToken()), 
            0x27BeC33E82Eb9d95367C87842Ae306f8dd3AF7bE, 
            "payment token error!"
        );
    }

    function testServerMint() public {
        thirdHeroTokens.serverMint(msg.sender, "items", "ipfs://abc", "", 10000);
        Assert.equal(thirdHeroTokens.getListSize(), 1, "Server mint failed!");

        try thirdHeroTokens.serverMint(msg.sender, "items", "ipfs://abc", "", 10000) {
            Assert.ok(false, "Server mint is broken, token ID duplucated!");
        } catch (bytes memory lowLevelData) { }

        try thirdHeroTokens.serverMint(msg.sender, "items", "ipfs://abc", "", 0) {
            Assert.ok(false, "Server mint is broken, token ID is 0!");
        } catch (bytes memory lowLevelData) { }

        Assert.equal(
            thirdHeroTokens.getItems()[0].owner, 
            msg.sender, 
            "Server mint wrong owner!"
        );

        Assert.equal(
            thirdHeroTokens.getItems()[0].metadata, 
            "ipfs://abc", 
            "Server mint wrong ipfs path!"
        );
    }

    function testAddSections() public {
        try thirdHeroTokens.addSection("items") {} catch (bytes memory lowLevelData) {}
        Assert.equal(thirdHeroTokens.getSectionsSize(), 2, "Sections size error!");

        try thirdHeroTokens.addSection("beers") {} catch (bytes memory lowLevelData) {}
        Assert.equal(thirdHeroTokens.getSectionsSize(), 3, "Sections size error!");

        try thirdHeroTokens.addSection("bEers") {} catch (bytes memory lowLevelData) {}
        Assert.equal(thirdHeroTokens.getSectionsSize(), 4, "Sections size error!");
    }

    function testRenameSections() public {
        try thirdHeroTokens.correctSectionName("items", "items2") {} catch (bytes memory lowLevelData) {}
        Assert.equal(thirdHeroTokens.getSections()[1], "items2", "Sections name error!");

        try thirdHeroTokens.correctSectionName("items2", "items") {} catch (bytes memory lowLevelData) {}
        Assert.equal(thirdHeroTokens.getSections()[1], "items", "Sections name error!");
    }
}
    
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract THT is ERC20Permit {
    address owner;
 
    constructor() ERC20("Third Hero Token", "THT") ERC20Permit("THT") {
        owner = msg.sender;
        mint(msg.sender, 10000);
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    function mint(address account, uint256 value) public onlyOwner {
        _mint(account, value * 10 ** decimals());
    }

    function burn(uint256 value) public onlyOwner {
        _burn(owner, value * 10 ** decimals());
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        _transfer(msg.sender, to, value);

        return true;
    }
}

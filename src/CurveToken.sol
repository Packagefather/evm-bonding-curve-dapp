// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin-contracts/access/Ownable.sol";

contract CurveToken is ERC20, Ownable(msg.sender) {
    uint8 private _decimals;

    constructor(string memory n, string memory s, uint8 d, address initialOwner) ERC20(n, s) {
        _decimals = d;
        _transferOwnership(initialOwner);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

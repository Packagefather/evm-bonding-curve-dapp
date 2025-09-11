// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { CurveToken } from "../src/CurveToken.sol";

contract TokenDeployment is Script, Test {
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public ADMIN = makeAddr("Admin");

    CurveToken public token;

    function run() external {
        vm.startPrank(ADMIN);

        // Deploy the token
        token = new CurveToken("MyToken", "MKT", 18, ADMIN);

        console.log("Token deployed at:", address(token));
        console.log("Deployer (Admin):", ADMIN);

        // Mint some tokens to admin to test transfer
        uint256 mintAmount = 1_000_000e18;
        token.mint(ADMIN, mintAmount);
        console.log("Minted", mintAmount, "tokens to Admin");

        // Check Admin balance
        uint256 adminBal = token.balanceOf(ADMIN);
        console.log("Admin token balance:", adminBal);

        // Try transfer to Bob
        address BOB = makeAddr("Bob");
        uint256 transferAmount = 1000e18;
        bool sent = token.transfer(BOB, transferAmount);
        console.log("Transfer to Bob successful?", sent);

        // Check Bob's balance
        uint256 bobBal = token.balanceOf(BOB);
        console.log("Bob token balance:", bobBal);

        vm.stopPrank();
    }
}

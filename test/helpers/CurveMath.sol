// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

contract CurveMath {
    uint256 constant PRECISION = 1e14; // ~0.0001 tokens

    function findIdealVETH(
        uint256 totalSupply,       // Already in 1e18
        uint256 allocationPercent, // E.g. 80
        uint256 curveLimit         // In ETH (not 1e18 yet)
    ) public pure returns (uint256) {
        uint256 allocation = (totalSupply * allocationPercent) / 100; // 80% of total

        uint256 low = 1e16; // 0.01 ETH
        uint256 high = curveLimit * 1e18; // Convert to 1e18

        uint256 bestVETH;

        for (uint256 i = 0; i < 128; i++) {
            uint256 vETH = (low + high) / 2;

            uint256 vToken = allocation;
            uint256 k = (vETH * vToken) / 1e18;

            uint256 newVETH = vETH + (curveLimit * 1e18);
            uint256 newVToken = (k * 1e18) / newVETH;

            uint256 tokensSold = vToken > newVToken ? vToken - newVToken : 0;

            if (_absDiff(tokensSold, allocation) <= PRECISION) {
                bestVETH = vETH;
                break;
            }

            if (tokensSold > allocation) {
                high = vETH;
            } else {
                low = vETH;
            }
        }

        return bestVETH; // 1e18 scale
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
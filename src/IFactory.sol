// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFactory {
    // --- Protocol-level Fees ---
    function protocolFeeBps() external view returns (uint96);

    function sellFeeBps() external view returns (uint96);

    function referralFeeBps() external view returns (uint96);

    function migrationFeeBps() external view returns (uint96);

    // --- Treasury & Migration Wallets ---
    function treasury() external view returns (address);

    function tradingFeeWallet() external view returns (address);

    function migrationFeeWallet() external view returns (address);

    // --- Liquidity & Anti-FUD ---
    function liquidityPercentage() external view returns (uint96); // e.g. 90% of raised funds

    function antifiludLauncherQuotaBps() external view returns (uint96); // % of antifud sent to launcher

    function antifiludFeeBps() external view returns (uint96); // % antifud fee on sells

    // --- Ownership ---
    function owner() external view returns (address);

    // --- Curve Limits ---
    function maxCurveLimitEth() external view returns (uint256);

    function minCurveLimitEth() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    // function virtualETH() external view returns (uint256);

    function tokenUsed(address token) external view returns (bool);

    function fixedAllocationPercent() external view returns (uint256);

    function fixedAllocationOfVToken() external view returns (uint256);

    function superAdmin() external view returns (address);
}

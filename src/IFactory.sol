// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFactory {
    // --- Protocol-level Fees ---
    function platformFeeBps() external view returns (uint96);

    function sellFeeBps() external view returns (uint96);

    function referralFeeBps() external view returns (uint96);

    function migrationFeeBps() external view returns (uint96);

    // --- Treasury & Migration Wallets ---
    function treasury() external view returns (address);

    function tradingFeeWallet() external view returns (address);

    function migrationFeeWallet() external view returns (address);

    // --- Liquidity & Anti-FUD ---
    function liquidityPercentage() external view returns (uint96); // e.g. 90% of raised funds

    function antiFudPercentage() external view returns (uint96); // e.g. 30% antifud

    function antifiludLauncherQuotaBps() external view returns (uint96); // % of antifud sent to launcher

    // --- Ownership ---
    function owner() external view returns (address);

    // --- Curve Limits ---
    function maxCurveLimit() external view returns (uint256);

    function minCurveLimit() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function virtualETH() external view returns (uint256);
}

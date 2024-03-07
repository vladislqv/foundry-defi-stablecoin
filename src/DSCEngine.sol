// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


/**
 * @title DSCEngine
 * @author Vladislav Zavtur
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == 1$ peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * 
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by ETH and BTC.
 * 
 * The DSC system should always be "overcollateralized". At no point, should the value of the DSC tokens exceed the value of the collateral.
 * 
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and reedeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine {
    function depositCollateralAndMintDsc() external {}

    function depositCollateral() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
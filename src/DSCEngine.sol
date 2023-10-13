// SPDX-License-Identifier: MIT

//This is the logic
//This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/*
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC systems should always be overcollateralized. At no point, should the value of all collateral <= the $ backed value of all DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////
    // Errors //
    //////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddresesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintedFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////
    // Types //
    //////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////
    // State variables//
    //////////////
    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollteralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //this means 10% bonus
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    DecentralizedStableCoin public immutable i_dsc;
    mapping(address token => address s_priceFeeds) public s_priceFeeds;
    //Traccia quanto collaterala ha depositato ogni utente
    mapping(address user => mapping(address token => uint256)) public s_collateralDeposits;
    //Traccia quantyi DSC ha mintato ogni utente
    mapping(address user => uint256 amountDSCMinted) public s_DSCMinted;
    //Array di tutti i tioken che accettiamo come collateral
    address[] private s_collateralTokens;

    ////////////////
    // Event //
    //////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////
    // Modifiers //
    //////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    /////////////////
    // Functions //
    //////////////
    //Nel costruttore passiamo gli indirizzi dei token che vogliamo accettare come collateral e gli indirizzi del loro feed price + l'indirizzo del DSC
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        //USD Price Feed
        //Controllo che la lunghezza dell'array dei tokenn sia uguale a quella degli indirizzi dei feed price
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddresesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            //Se il token ha il price feed è allowed altrimenti non lo è
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            //Aggiungo i tokenAddress al nostro array
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////
    // External Function //
    //////////////

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /*
     * @notice follow CEI
     * @notice This function allows a user to deposit collateral into the system and mint DSC.
     * @param tokenCollateralAddress The address of the collateral token to deposit.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDSC The amount of DSC to mint.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposits[msg.sender][tokenCollateralAddress] += amountCollateral;
        //Emetto un evento ogni volta che aggiorno il deposito
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        //Adesso deposito il token
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */

    function reedemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeemCollateral already check the Health factor
    }

    //In order to redeem collateral:
    //1. Check health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertHealthFactorIsBroken(msg.sender);
    }

    //Check if the collateral value > DSC amount (check price feed etc)
    //Deposit 200$ ETH --> riceve $20 DSC
    /*
        * @notice Follow CEI
        * @param amountDSCToMint The amount of decentralized stable coin to mint.
        * @notice they must have more collateral value then the minimum threashold
        */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        //if they minted to much (150$ DSC, 100$ ETH)
        _revertHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintedFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertHealthFactorIsBroken(msg.sender); //I don't think this would be ever hit...
    }

    //Funzione che viene chiamata dagli altri utenti per liquidare le posizioni sotto-collateralizzate degli altri utenti
    //100$ ETH --> 50 DSC
    //20$ ETH --> 50 DSC (undercollateralized 20/50 <1) DSC doesn't worth 1 $

    //75$ ETH --> 50$ DSC è minore della nostra soglia a 50
    //liquidator take 75$ backing and burns 50$ DSC

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //need to check health factor of the user
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        //We want to burn they DSC debt
        //And take their collateral
        //Bad user: 140$ ETH, 100$ DSC
        //Debt to cover: 100$
        //100$ DSC --> ? ETH
        //0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        //And give them 10% bonus
        //So we are giving the liquidator 110$ of WETH for 100 DSC
        //We should implement a feature to liquidate in the event the protocol is insolvent
        //and sweep extra amount into a treasury
        //0.55 ETH * 0.1 = 0.0055 ETH. Getting 0.055 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        //We need to burn the DSC
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertHealthFactorIsBroken(msg.sender);
    }

    //Deposit 100$ ETH collateral --> 0
    //Mint 50 DSC --> 0
    //It's ok, is overcollateriezed
    //---------------------
    //
    //Deposit 100$ ETH collateral --> se prezzo ETH crolla a 40$ devo liquidare l'utente
    //Setto un threashold per es. 150%. Quinidi i miei ETH devono valere almeno 75$ per ogni 50$ di DSC
    //
    //---------------------
    //Deposit 100$ ETH --> se prezzo ETH crolla a 74$ (sotto-soglia)
    //UNDERCOLLATERRALIZED
    //Hei, if someone pays back your minted DSC, they can have all your collateral for a discount
    //I'll pay back the 50 DSC --> Get all your collateral (74$ ETH)
    // $74 ETH
    // - 50DSC
    // $24 ETH
    //Pago 50DSC mi danno 74$ ETH, ho un guadagno di 24$ ETH. Sono incentivato a farlo.

    /////////////////
    // Private & Internal View Function //
    //////////////

    /*
     * Low level internal function, do not call unless the function calling it is checking foe health factors being broken 
     */
    function _burnDSC(uint256 amountDSCToBurn, address onBehalfFrom, address dscFrom) private {
        s_DSCMinted[onBehalfFrom] -= amountDSCToBurn;
        //Trasferisco i DSC che voglio bruciare al contratto
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        //Brucio i DSC
        i_dsc.burn(amountDSCToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        //Il totale dei DSC mintati dall'utente
        totalDscMinted = s_DSCMinted[user];
        //Il valore del collaterale in USD
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    //Calcola l'health factor che è un parametro secondo la formula di aave
    /*
     * Returns how close to liquidation user is 
     * if a user goes below 1, then they get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        //total DSC minted
        //total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        //Collateral adjusted with threashold
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
        //50% = 50 LIQUIDATION_THREASHOLD / 100 = 1 / 2 abbiamo raddoppiato il collaterale
        //1000ETH *50 = 50000 / 100 = 500

        //150$ ETH / 100 DSC --> 1.5
        //150 * 50 = 7500 / 100 = (75/100) < 1
        //return (collateralValueInUsd / totalDSCMinted); //(vogliamo che l'utente sia sopra una soglia stabilita 150/100)
        //1000$ ETH / 100 DSC
        //1000 * 50 = 50000 / 100 = 500 / 100 = 5 > 1
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    //1. Check health factor (do they have enough collateral?)
    //2. Revert if don't
    function _revertHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////
    // Public and View external Function //
    //////////////

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        //Internal accoount per vedere quanto collaterale hanno depositato
        s_collateralDeposits[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        //In quyesto caso violo CEI - prima trasferisco poi faccio check dell'health factor che reverta nel caso non sia ok
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address token, uint256 amountInWei) public view returns (uint256) {
        //price of ETH (token)
        //$/ETH ETH ??
        //$2000 ETH $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        //($10e18 * 1e18) / ($2000 e8 * 1e10)
        return (amountInWei * PRECISION) / (uint256(price) * ADDITION_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through all collateral tokens, get the amount they have deposit and map it to the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            //Address del token
            address token = s_collateralTokens[i];
            //Get the amount the user has deposited
            uint256 amount = s_collateralDeposits[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        //1ETH = 1000 $
        //The return value of chainlink will be 1000 * 1e8
        //Entrambi i moltiplicatori devono essere 1e18 quindi devo aggiustare price e poi divido tutto per 1e18
        return ((uint256(price) * ADDITION_FEED_PRECISION) * amount) / PRECISION; //(1000 * 1e8 * (1e10)) * 1000 * 1e18
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalancOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposits[user][token];
    }
}

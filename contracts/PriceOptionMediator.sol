// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BetMe} from "./BetMe.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceOptionMediator
 * @author MauriceDeSaxe
 * @notice Mediates a bet between two players that the price of a certain
 * given asset will raise/fall to a certain "strike" price before a certain date.
 * @dev The data feed heartbeat is optional, but is recommended to avoid stale pricing data
 * which can be a very real security risk.
 * @dev Please check the data feed's decimals before setting the strike price.
 */
contract PriceOptionMediator {
    AggregatorV3Interface internal dataFeed;
    uint256 public dataFeedHeartbeat;
    string public optionType; // "put" or "call"
    address public buyer;
    address public seller;
    uint256 public strikePrice;
    uint256 public expiration;
    address public betMe;

    struct CProps {
        address dataFeed;
        uint256 dataFeedHeartbeat;
        string optionType;
        address buyer;
        address seller;
        uint256 strikePrice;
        uint256 expiration;
    }

    event PriceOptionMediatorCreated(
        address indexed dataFeed,
        string indexed optionType,
        address indexed buyer,
        address indexed seller,
        uint256 strikePrice,
        uint256 expiration
    );
    event WinnerPicked(address indexed winner, uint256 strikePrice, uint256 expiration, string optionType);

    constructor(CProps memory _props) {
        bool missingProps = _props.dataFeed == address(0) || _props.buyer == address(0) || _props.seller == address(0)
            || _props.strikePrice == 0 || _props.expiration == 0 || _props.optionType == "";
        if (missingProps) {
            revert("DataFeed, Buyer, Seller, StrikePrice, Expiration and OptionType are all required");
        }

        bool expired = block.timestamp > _props.expiration;
        if (expired) {
            revert("Expiration is in the past");
        }

        dataFeed = AggregatorV3Interface(_props.dataFeed);
        if (_props.dataFeedHeartbeat != 0) {
            // dataFeedHeartbeat is optional and can be used to check that the data feed is still healthy.
            // It's recommended that the deployer set this value to avoid stale pricing data.
            dataFeedHeartbeat = _props.dataFeedHeartbeat;
        }

        if (_props.optionType != "put" && _props.optionType != "call") {
            revert("OptionType must be either 'put' or 'call'");
        }
        if (_props.optionType == "put") {
            bool strikePriceTooHigh = _props.strikePrice > getChainlinkDataFeedLatestAnswer();
            if (strikePriceTooHigh) {
                revert("StrikePrice is too high for a put option");
            }
        } else {
            bool strikePriceTooLow = _props.strikePrice < getChainlinkDataFeedLatestAnswer();
            if (strikePriceTooLow) {
                revert("StrikePrice is too low for a call option");
            }
        }

        optionType = _props.optionType;
        buyer = _props.buyer;
        seller = _props.seller;
        strikePrice = _props.strikePrice;
        expiration = _props.expiration;

        betMe = address(new BetMe(_props.buyer, _props.seller));
        emit PriceOptionMediatorCreated(address(dataFeed), optionType, buyer, seller, strikePrice, expiration);
    }

    /**
     * @notice Try to pick the winner of the bet.
     * @dev We use a Chainlink data feed to get the price of the asset.
     * @dev If the price is at/below the strike price and the expiration date has not passed, the putBuyer wins.
     * @dev If the expiration date has passed, the putSeller wins.
     * @dev The data feed heartbeat is optional, but is recommended to avoid stale pricing data
     * which can be a very real security risk.
     */
    function tryPickWinner() external {
        address winner;

        bool expired = block.timestamp > expiration;
        if (expired) {
            // The option has expired, so the put seller wins; we don't need to check the price
            winner = seller;
            BetMe(betMe).pickWinner(winner);
            emit WinnerPicked(winner, strikePrice, expiration, optionType);
            return; // stop further execution
        }

        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            uint256 timeStamp,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData(); // technically this could be reentrant, but the called contract is set in the constructor by a trusted deployer

        // this only runs if dataFeedHeartbeat is set; it's optional but highly recommended that the deployer set this value to avoid stale pricing data
        if (dataFeedHeartbeat != 0) {
            // timeStamp of latest round + heartbeat threshold > now
            bool isWithinHeartbeat = timeStamp + dataFeedHeartbeat > block.timestamp;
            if (!isWithinHeartbeat) {
                revert("DataFeed heartbeat expired");
            }
        }

        if (optionType == "put") {
            bool isAboveStrikePrice = answer > strikePrice;
            if (!isAboveStrikePrice) {
                // The put buyer has bet that the price will fall at/below the strike price
                // within the expiration period, so they win
                winner = buyer;
            }
        } else {
            bool isBelowStrikePrice = answer < strikePrice;
            if (!isBelowStrikePrice) {
                // The put seller has bet that the price will rise above the strike price
                // within the expiration period, so they win
                winner = seller;
            }
        }

        if (winner == address(0)) {
            revert("No winner");
        }
        BetMe(betMe).pickWinner(winner); // technically this could be reentrant, but the called contract is set in the constructor by a trusted deployer
        emit WinnerPicked(winner, strikePrice, expiration, optionType);
    }
}

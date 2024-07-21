// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BetMe} from "./BetMe.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PutMediator
 * @author MauriceDeSaxe
 * @notice Mediates a bet between two players that the price of a certain
 * given asset will fall to a certain price before a certain date.
 */
contract PutMediator {
    AggregatorV3Interface internal dataFeed;
    address public putBuyer;
    address public putSeller;
    uint256 public strikePrice;
    uint256 public expiration;
    address public betMe;

    struct CProps {
        address dataFeed;
        address putBuyer;
        address putSeller;
        uint256 strikePrice;
        uint256 expiration;
    }

    event PutMediatorCreated(
        address indexed dataFeed,
        address indexed putBuyer,
        address indexed putSeller,
        uint256 strikePrice,
        uint256 expiration
    );

    event WinnerPicked(address indexed winner);

    constructor(CProps memory _props) {
        bool missingProps = _props.dataFeed == address(0) || _props.putBuyer == address(0)
            || _props.putSeller == address(0) || _props.strikePrice == 0 || _props.expiration == 0;
        if (missingProps) {
            revert("DataFeed, PutBuyer, PutSeller, StrikePrice and Expiration are all required");
        }

        bool expired = block.timestamp > _props.expiration;
        if (expired) {
            revert("Expiration is in the past");
        }

        dataFeed = AggregatorV3Interface(_props.dataFeed);

        bool strikePriceTooHigh = _props.strikePrice > getChainlinkDataFeedLatestAnswer();
        if (strikePriceTooHigh) {
            revert("StrikePrice is too high");
        }

        putBuyer = _props.putBuyer;
        putSeller = _props.putSeller;
        strikePrice = _props.strikePrice;
        expiration = _props.expiration;

        betMe = address(new BetMe(_props.putBuyer, _props.putSeller));
    }

    /**
     * @notice Try to pick the winner of the bet.
     * @dev We use a Chainlink data feed to get the price of the asset.
     * @dev If the price is at/below the strike price and the expiration date has not passed, the putBuyer wins.
     * @dev If the expiration date has passed, the putSeller wins.
     */
    function tryPickWinner() external {
        address winner;

        bool expired = block.timestamp > expiration;
        if (expired) {
            // The option has expired, so the put seller wins; we don't need to check the price
            winner = putSeller;
            BetMe(betMe).pickWinner(winner);
            emit WinnerPicked(winner);
            return; // stop further execution
        }

        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            /*uint timeStamp*/
            ,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();

        // TODO check data feed heartbeat

        bool isAboveStrikePrice = answer > strikePrice;
        if (!isAboveStrikePrice) {
            // The put buyer has bet that the price will fall at/below the strike price
            // within the expiration period, so they win
            winner = putBuyer;
        }

        if (winner == address(0)) {
            revert("No winner");
        }
        BetMe(betMe).pickWinner(winner);
        emit WinnerPicked(winner);
    }
}

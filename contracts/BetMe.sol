// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title BetMe
 * @author MauriceDeSaxe
 * @notice A simple 2-player 1:1 betting contract with a mediator.
 * That means each bettor bets an equal amount and the mediator picks the winner.
 */
contract BetMe {
    address public mediator;
    address public bettor1;
    address public bettor2;
    mapping(address => uint256) public bets;

    bool public isLocked;
    address public winner;

    event Bet(uint256 amount, uint256 when, address who);
    event Winner(uint256 amount, uint256 when, address who);
    event Withdraw(uint256 amount, uint256 when, address who);

    /**
     * @notice Mediator creates the contract assigning the bettors.
     * @param _bettor1 Address of the first bettor.
     * @param _bettor2 Address of the second bettor.
     */
    constructor(address _bettor1, address _bettor2) payable {
        require(_bettor1 != _bettor2, "Bettors can't be the same");
        bettor1 = _bettor1;
        bettor2 = _bettor2;
        mediator = msg.sender;
    }

    /**
     * @notice Bettors can bet whatever they want, as soon as bets are equal the bets are locked.
     * @dev You can't bet if you're not a bettor or if the bet is locked.
     */
    function bet() public payable {
        bool isBettor1 = msg.sender == bettor1;
        bool isBettor2 = msg.sender == bettor2;
        require(msg.value > 0, "Amount must be greater than 0");
        require(isBettor1 || isBettor2, "You are not a bettor");
        require(isLocked == false, "The bet is locked");

        bets[msg.sender] += msg.value;
        if (bets[bettor1] == bets[bettor2]) {
            isLocked = true;
        }
        emit Bet(msg.value, block.timestamp, msg.sender);
    }

    /**
     * @notice The mediator can pick the winner if the bet is locked or the winner is already picked.
     * @param _winner Address of the winner.
     */
    function pickWinner(address _winner) public {
        require(msg.sender == mediator, "You are not the mediator");
        require(isLocked == true, "The bet is not locked");
        require(winner == address(0), "The winner is already picked");
        require(_winner == bettor1 || _winner == bettor2, "The winner is not a bettor");

        winner = _winner;
        emit Winner(bets[winner], block.timestamp, winner);
    }

    /**
     * @notice If the winner is picked, the winner can withdraw the total amount of deposits.
     */
    function withdraw() public {
        require(winner != address(0), "The winner is not picked");
        require(msg.sender == winner, "You are not the winner");

        uint256 total = bets[bettor1] + bets[bettor2];
        require(total > 0, "Total is 0");
        require(address(this).balance >= total, "Total is greater than the contract balance");

        bets[bettor1] = 0;
        bets[bettor2] = 0;

        payable(msg.sender).transfer(total);
        emit Withdraw(total, block.timestamp, msg.sender);
    }

    receive() external payable {
        revert("Use bet() to bet");
    }
}

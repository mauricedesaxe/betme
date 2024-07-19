// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "hardhat/console.sol";

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

    constructor(address _bettor1, address _bettor2) payable {
        mediator = msg.sender;
        bettor1 = _bettor1;
        bettor2 = _bettor2;
    }

    function bet() public payable {
        bool isBettor1 = msg.sender == bettor1;
        bool isBettor2 = msg.sender == bettor2;
        require(isBettor1 || isBettor2, "You are not a bettor");
        require(isLocked == false, "The bet is locked");
        require(msg.value > 0, "Amount must be greater than 0");

        bets[msg.sender] += msg.value;
        if (bets[bettor1] == bets[bettor2]) {
            isLocked = true;
        }
        emit Bet(msg.value, block.timestamp, msg.sender);
    }

    function pickWinner(address _winner) public {
        require(msg.sender == mediator, "You are not the mediator");
        require(winner == address(0), "The winner is already picked");
        require(isLocked == true, "The bet is not locked");
        require(_winner == bettor1 || _winner == bettor2, "The winner is not a bettor");

        winner = _winner;
        emit Winner(bets[winner], block.timestamp, winner);
    }

    function withdraw() public {
        require(winner != address(0), "The winner is not picked");
        require(msg.sender == winner, "You are not the winner");

        uint256 total = bets[bettor1] + bets[bettor2];
        payable(msg.sender).transfer(total);
        emit Withdraw(total, block.timestamp, msg.sender);
    }

    receive() external payable {}
}

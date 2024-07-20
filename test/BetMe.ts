import { expect } from "chai";
import hre from "hardhat";
import { getAddress, parseEther } from "viem";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("BetMe", function () {
  async function deployBetMeFixture() {
    const [mediator, bettor1, bettor2, otherAccount] =
      await hre.viem.getWalletClients();

    const betMe = await hre.viem.deployContract(
      "BetMe",
      [bettor1.account.address, bettor2.account.address],
      {
        value: parseEther("1"),
      }
    );

    const publicClient = await hre.viem.getPublicClient();
    const testClient = await hre.viem.getTestClient();

    return {
      betMe,
      mediator,
      bettor1,
      bettor2,
      otherAccount,
      publicClient,
      testClient,
    };
  }

  describe("Happy Path", function () {
    it("Should set the right mediator and bettors", async function () {
      const { betMe, mediator, bettor1, bettor2 } = await loadFixture(
        deployBetMeFixture
      );

      expect(await betMe.read.mediator()).to.equal(
        getAddress(mediator.account.address)
      );
      expect(await betMe.read.bettor1()).to.equal(
        getAddress(bettor1.account.address)
      );
      expect(await betMe.read.bettor2()).to.equal(
        getAddress(bettor2.account.address)
      );
    });

    it("Should lock the bet if both bettors bet the same amount", async function () {
      const { betMe, bettor1, bettor2 } = await loadFixture(deployBetMeFixture);

      await betMe.write.bet({
        value: parseEther("1"),
        account: bettor1.account.address,
      });
      await betMe.write.bet({
        value: parseEther("1"),
        account: bettor2.account.address,
      });

      expect(await betMe.read.isLocked()).to.be.true;
    });

    it("Should pick the winner if the bet is locked", async function () {
      const { betMe, bettor1, bettor2 } = await loadFixture(deployBetMeFixture);

      await betMe.write.bet({
        value: parseEther("1"),
        account: bettor1.account.address,
      });
      await betMe.write.bet({
        value: parseEther("1"),
        account: bettor2.account.address,
      });
      await betMe.write.pickWinner([bettor1.account.address]);

      expect((await betMe.read.winner()).toLowerCase()).to.equal(
        bettor1.account.address.toLowerCase()
      );
    });

    it("Should be able to withdraw the winner's balance", async function () {
      const { betMe, bettor1, bettor2, publicClient } = await loadFixture(
        deployBetMeFixture
      );

      const initialBalance = await publicClient.getBalance({
        address: bettor1.account.address,
      });
      const initialBalanceOfContract = await publicClient.getBalance({
        address: betMe.address,
      });

      const betTx1 = await betMe.write.bet({
        value: parseEther("1"),
        account: bettor1.account.address,
      });
      await betMe.write.bet({
        value: parseEther("1"),
        account: bettor2.account.address,
      });
      await betMe.write.pickWinner([bettor1.account.address]);

      // Calculate gas cost for bet transaction
      const betReceipt = await publicClient.waitForTransactionReceipt({
        hash: betTx1,
      });
      const gasUsedBet = betReceipt.gasUsed;
      const gasPriceBet = betReceipt.effectiveGasPrice;
      const gasCostBet = gasPriceBet * gasUsedBet;

      // impersonate bettor1 & withdraw
      const withdrawTx = await betMe.write.withdraw({
        account: bettor1.account.address,
      });
      const withdrawReceipt = await publicClient.waitForTransactionReceipt({
        hash: withdrawTx,
      });
      const gasUsedWithdraw = withdrawReceipt.gasUsed;
      const gasPriceWithdraw = withdrawReceipt.effectiveGasPrice;
      const gasCostWithdraw = gasPriceWithdraw * gasUsedWithdraw;

      const finalBalance = await publicClient.getBalance({
        address: bettor1.account.address,
      });

      const expectedBalance =
        initialBalance -
        parseEther("1") - // bettor1's bet
        gasCostBet + // gas cost for bet and pickWinner transactions
        parseEther("2") - // winnings
        gasCostWithdraw; // gas cost for withdraw transaction

      expect(finalBalance).to.equal(expectedBalance);

      expect(
        await publicClient.getBalance({
          address: betMe.address,
        })
      ).to.equal(initialBalanceOfContract); // contract should have the same balance as on deployment
    });
  });

  describe("Unhappy Paths", function () {
    describe("When betting", function () {
      it("Should not be able to deposit 0", async function () {
        const { betMe, bettor1 } = await loadFixture(deployBetMeFixture);

        await expect(
          betMe.write.bet({
            value: parseEther("0"),
            account: bettor1.account.address,
          })
        ).to.be.rejectedWith("Amount must be greater than 0");
      });

      it("Should not be able to deposit if you are not a bettor", async function () {
        const { betMe, mediator, otherAccount } = await loadFixture(
          deployBetMeFixture
        );

        await expect(
          betMe.write.bet({
            value: parseEther("1"),
            account: mediator.account.address,
          })
        ).to.be.rejectedWith("You are not a bettor");
        await expect(
          betMe.write.bet({
            value: parseEther("1"),
            account: otherAccount.account.address,
          })
        ).to.be.rejectedWith("You are not a bettor");
      });

      it("Should not be able to deposit if the bet is already locked", async function () {
        const { betMe, bettor1, bettor2 } = await loadFixture(
          deployBetMeFixture
        );

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });
        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor2.account.address,
        });

        await expect(
          betMe.write.bet({
            value: parseEther("1"),
            account: bettor1.account.address,
          })
        ).to.be.rejectedWith("The bet is locked");
      });

      it("Should not lock if both bettors bet aren't the same amount", async function () {
        const { betMe, bettor1, bettor2 } = await loadFixture(
          deployBetMeFixture
        );

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });
        await betMe.write.bet({
          value: parseEther("2"),
          account: bettor2.account.address,
        });

        expect(await betMe.read.isLocked()).to.be.false;
      });
    });

    describe("When picking a winner", function () {
      it("Should not be able to pick a winner if you are not the mediator", async function () {
        const { betMe, bettor1, bettor2, otherAccount } = await loadFixture(
          deployBetMeFixture
        );

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });
        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor2.account.address,
        });

        // impersonate bettor1 & try to pick self; should fail
        await expect(
          betMe.write.pickWinner([bettor1.account.address], {
            account: bettor1.account.address,
          })
        ).to.be.rejectedWith("You are not the mediator");

        // impersonate otherAccount & try to pick self; should fail
        await expect(
          betMe.write.pickWinner([otherAccount.account.address], {
            account: otherAccount.account.address,
          })
        ).to.be.rejectedWith("You are not the mediator");
      });

      it("Should not be able to pick a winner if the bet is not locked", async function () {
        const { betMe, bettor1, bettor2 } = await loadFixture(
          deployBetMeFixture
        );

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });

        await expect(
          betMe.write.pickWinner([bettor1.account.address])
        ).to.be.rejectedWith("The bet is not locked");
      });

      it("Should not be able to pick a winner if the bet is already won", async function () {
        const { betMe, bettor1, bettor2 } = await loadFixture(
          deployBetMeFixture
        );

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });
        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor2.account.address,
        });
        await betMe.write.pickWinner([bettor1.account.address]);

        await expect(
          betMe.write.pickWinner([bettor1.account.address])
        ).to.be.rejectedWith("The winner is already picked");
      });

      it("Should not be able to pick a winner that is not a bettor", async function () {
        const { betMe, bettor1, bettor2, mediator, otherAccount } =
          await loadFixture(deployBetMeFixture);

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });
        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor2.account.address,
        });

        await expect(
          betMe.write.pickWinner([mediator.account.address])
        ).to.be.rejectedWith("The winner is not a bettor");
        await expect(
          betMe.write.pickWinner([otherAccount.account.address])
        ).to.be.rejectedWith("The winner is not a bettor");
      });
    });

    describe("When withdrawing", function () {
      it("Should not be able to withdraw if the winner is not picked", async function () {
        const { betMe, bettor1, bettor2 } = await loadFixture(
          deployBetMeFixture
        );

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });
        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor2.account.address,
        });

        await expect(
          betMe.write.withdraw({
            account: bettor1.account.address,
          })
        ).to.be.rejectedWith("The winner is not picked");
      });

      it("Should not be able to withdraw if the winner is not a the winner", async function () {
        const { betMe, bettor1, bettor2, mediator, otherAccount } =
          await loadFixture(deployBetMeFixture);

        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor1.account.address,
        });
        await betMe.write.bet({
          value: parseEther("1"),
          account: bettor2.account.address,
        });

        await betMe.write.pickWinner([bettor1.account.address]);

        await expect(
          betMe.write.withdraw({
            account: bettor2.account.address,
          })
        ).to.be.rejectedWith("You are not the winner");
        await expect(
          betMe.write.withdraw({
            account: mediator.account.address,
          })
        ).to.be.rejectedWith("You are not the winner");
        await expect(
          betMe.write.withdraw({
            account: otherAccount.account.address,
          })
        ).to.be.rejectedWith("You are not the winner");
      });
    });
  });
});

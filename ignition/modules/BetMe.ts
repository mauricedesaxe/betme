import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const BetMeModule = buildModule("BetMeModule", (m) => {
  const bettor1 = m.getParameter("bettor1");
  const bettor2 = m.getParameter("bettor2");

  const betMe = m.contract("BetMe", [bettor1, bettor2], {});

  return { betMe };
});

export default BetMeModule;

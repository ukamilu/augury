import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const CONTRACT_NAME = "augury";
const MIN_STAKE = 1000n;
const PLATFORM_FEE = 10n;
const FEE_DIVISOR = 1000n;
const DEFAULT_AMOUNT = 2000n;

const ERR = {
  invalidAmount: 405n,
  doubleStake: 800n,
  contractPaused: 801n,
};

const accounts = simnet.getAccounts();
const deployer = (() => {
  const account = accounts.get("deployer") ?? accounts.get("wallet_1");
  if (!account) {
    throw new Error("Missing deployer account");
  }
  return account;
})();
const wallet1 = accounts.get("wallet_1") ?? deployer;
const wallet2 = accounts.get("wallet_2") ?? deployer;

function setPredictionDeadline(blocksFromNow = 10, sender = deployer) {
  const target = BigInt(simnet.blockHeight + blocksFromNow);
  const call = simnet.callPublicFn(
    CONTRACT_NAME,
    "set-prediction-deadline",
    [Cl.uint(target)],
    sender,
  );
  expect(call.result).toBeOk(Cl.bool(true));
  return target;
}

function predict(choice: boolean, amount: bigint, sender: string) {
  return simnet.callPublicFn(
    CONTRACT_NAME,
    "predict",
    [Cl.bool(choice), Cl.uint(amount)],
    sender,
  );
}

function expectedStake(amount: bigint) {
  const fee = (amount * PLATFORM_FEE) / FEE_DIVISOR;
  return { fee, stake: amount - fee };
}

describe("augury core flows", () => {
  it("predict updates pools, stakes, and user stats", () => {
    setPredictionDeadline();

    const { stake } = expectedStake(DEFAULT_AMOUNT);
    const call = predict(true, DEFAULT_AMOUNT, wallet1);
    expect(call.result).toBeOk(Cl.bool(true));

    const truePool = simnet.getDataVar(CONTRACT_NAME, "total-true-pool");
    expect(truePool).toBeUint(stake);

    const stakeEntry = simnet.getMapEntry(
      CONTRACT_NAME,
      "stakes",
      Cl.tuple({ user: Cl.principal(wallet1), prediction: Cl.bool(true) }),
    );
    expect(stakeEntry).toBeSome(Cl.tuple({ amount: Cl.uint(stake) }));

    const stats = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "get-user-stats",
      [Cl.principal(wallet1)],
      wallet1,
    );
    expect(stats.result).toBeTuple({
      "total-staked": Cl.uint(stake),
      "total-won": Cl.uint(0),
      "predictions-made": Cl.uint(1),
      "successful-predictions": Cl.uint(0),
    });
  });

  it("rejects predictions that fail stake validation", () => {
    setPredictionDeadline();

    const call = predict(true, MIN_STAKE, wallet1);
    expect(call.result).toBeErr(Cl.uint(ERR.invalidAmount));
  });

  it("rejects a double stake on the same prediction", () => {
    setPredictionDeadline();

    const first = predict(true, DEFAULT_AMOUNT, wallet1);
    expect(first.result).toBeOk(Cl.bool(true));

    const second = predict(true, DEFAULT_AMOUNT, wallet1);
    expect(second.result).toBeErr(Cl.uint(ERR.doubleStake));
  });

  it("prevents predictions while the contract is paused", () => {
    setPredictionDeadline();

    const pause = simnet.callPublicFn(
      CONTRACT_NAME,
      "set-contract-pause",
      [Cl.bool(true)],
      deployer,
    );
    expect(pause.result).toBeOk(Cl.bool(true));

    const call = predict(true, DEFAULT_AMOUNT, wallet1);
    expect(call.result).toBeErr(Cl.uint(ERR.contractPaused));
  });

  it("allows claims after resolve and clears the stake", () => {
    setPredictionDeadline();

    const { stake } = expectedStake(DEFAULT_AMOUNT);
    const enter = predict(true, DEFAULT_AMOUNT, wallet1);
    expect(enter.result).toBeOk(Cl.bool(true));

    const resolve = simnet.callPublicFn(
      CONTRACT_NAME,
      "resolve",
      [Cl.bool(true)],
      deployer,
    );
    expect(resolve.result).toBeOk(Cl.bool(true));

    const claim = simnet.callPublicFn(CONTRACT_NAME, "claim", [], wallet1);
    expect(claim.result).toBeOk(Cl.uint(0));

    const stakeEntry = simnet.getMapEntry(
      CONTRACT_NAME,
      "stakes",
      Cl.tuple({ user: Cl.principal(wallet1), prediction: Cl.bool(true) }),
    );
    expect(stakeEntry).toBeNone();

    const stats = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "get-user-stats",
      [Cl.principal(wallet1)],
      wallet1,
    );
    expect(stats.result).toBeTuple({
      "total-staked": Cl.uint(stake),
      "total-won": Cl.uint(stake),
      "predictions-made": Cl.uint(1),
      "successful-predictions": Cl.uint(1),
    });
  });

  it("processes batch predictions and records the batch", () => {
    setPredictionDeadline();

    const amount1 = 2000n;
    const amount2 = 3000n;
    const stake1 = expectedStake(amount1).stake;
    const stake2 = expectedStake(amount2).stake;

    const predictions = Cl.list([
      Cl.tuple({ choice: Cl.bool(true), amount: Cl.uint(amount1) }),
      Cl.tuple({ choice: Cl.bool(false), amount: Cl.uint(amount2) }),
    ]);

    const call = simnet.callPublicFn(
      CONTRACT_NAME,
      "batch-predict",
      [predictions],
      wallet2,
    );
    expect(call.result).toBeOk(Cl.uint(0));

    const truePool = simnet.getDataVar(CONTRACT_NAME, "total-true-pool");
    const falsePool = simnet.getDataVar(CONTRACT_NAME, "total-false-pool");
    expect(truePool).toBeUint(stake1);
    expect(falsePool).toBeUint(stake2);

    const batchEntry = simnet.getMapEntry(
      CONTRACT_NAME,
      "batch-operations",
      Cl.tuple({ "batch-id": Cl.uint(0) }),
    );
    expect(batchEntry).toBeSome(
      Cl.tuple({
        predictions,
        status: Cl.bool(true),
      }),
    );
  });
});

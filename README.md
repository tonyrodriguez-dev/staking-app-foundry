# Staking App Foundry

A staking smart contract built with Solidity 0.8.34, OpenZeppelin v5.7.0 and tested with [Foundry](https://book.getfoundry.sh/). Users deposit a fixed amount of an ERC-20 token (`STK`) and, every time a staking period passes, they can claim a fixed ETH reward. The owner funds the rewards.

The focus of the project is testing: 15 tests (14 for the app, 1 for the token), 100% coverage, and a mutation check that shows which tests really protect the code and which do not (see [Honest review of the tests](#honest-review-of-the-tests)).

Built while following a Blockchain Accelerator course, module 7. The contracts match the course material; the review, the mutation check and the documentation are my own work.

## Concepts practiced

- ERC-20 with OpenZeppelin (`ERC20`, `IERC20`) and access control with `Ownable` (v5: `Ownable(owner_)` in the constructor)
- Token flow: `approve` + `transferFrom` to deposit, `transfer` to withdraw
- Checks-Effects-Interactions (CEI) in `withdrawTokens` and `claimRewards`
- Sending ETH with `.call{value: x}("")` and checking the returned `bool`
- `receive()` restricted with `onlyOwner`
- Time-based logic with `block.timestamp`
- Foundry cheatcodes: `vm.addr`, `vm.startPrank` / `vm.stopPrank`, `vm.expectRevert("message")`, `vm.deal`, `vm.warp`
- Coverage with `forge coverage`, and mutation testing done by hand

## Contracts

Both follow the same file order: variables, events, modifiers, constructor, external functions, internal functions.

### `StakingToken` ([src/StakingToken.sol](src/StakingToken.sol))

An OpenZeppelin `ERC20` with a public `mint(uint256)` that mints to the caller. It is a test token: anyone can mint.

### `StakingApp` ([src/StakingApp.sol](src/StakingApp.sol))

Constructor: `(stakingToken_, owner_, stakingPeriod_, fixedStakingAmount_, rewardPerPeriod_)`.

| Function | Who | What it does |
| --- | --- | --- |
| `depositTokens(amount_)` | anyone | Requires `amount_ == fixedStakingAmount` ("Incorrect Amount") and no previous deposit ("User already deposited"). Pulls the tokens with `transferFrom` (the user must `approve` first), records the balance and the deposit time, emits `DepositTokens`. |
| `withdrawTokens()` | anyone | Caches the user balance, sets it to 0, sends the tokens back with `transfer` and emits `WithdrawTokens` (CEI order). With no deposit it sends 0 and does not revert. |
| `claimRewards()` | stakers | Requires an active deposit ("Not staking") and that `stakingPeriod` has passed since the last deposit or claim ("Need to wait"). Resets the timer, then sends `rewardPerPeriod` in ETH; reverts with "Transfer failed" if the payment fails. |
| `receive()` | owner only | Lets the owner fund the contract with ETH (emits `EtherSent`). |
| `changeStakingPeriod(newPeriod_)` | owner only | Changes `stakingPeriod` and emits `ChangeStakingPeriod`. |

Rules of the app: a fixed deposit amount, one reward per full period, full withdrawal only.

## Testing

```bash
forge test          # run everything
forge coverage      # coverage table
forge test -vvvv    # traces
```

Result (full output in [evidencias/coverage_final.txt](evidencias/coverage_final.txt)):

| File | Lines | Statements | Branches | Functions |
| --- | --- | --- | --- | --- |
| `src/StakingApp.sol` | 100% (29/29) | 100% (25/25) | 100% (10/10) | 100% (6/6) |
| `src/StakingToken.sol` | 100% (3/3) | 100% (1/1) | n/a | 100% (2/2) |

Every test, what it checks and how solid it is is explained one by one in [docs/TESTS.md](docs/TESTS.md). Summary:

| Test | What it checks |
| --- | --- |
| `testStakingTokenCorrectCorrectlyDeployed`, `testStakingAppCorrectCorrectlyDeployed` | Both contracts deploy (non-zero address) |
| `testShouldRevertIfNotOwner` | A non-owner cannot change the staking period |
| `testShouldChangeStakingPeriod` | The owner can, and the value changes |
| `testContractReceivesEtherCorrectly` | The owner can send ETH to the app |
| `testIncorrectAmountShouldRevert` | Depositing a wrong amount reverts with "Incorrect Amount" |
| `testDepositTokensCorrectly` | Deposit records the balance and the timestamp |
| `testUserCanNotDepositMoreThanOnce` | A second deposit reverts with "User already deposited" |
| `testCanOnlyWithdraw0WithoutDeposit` | Withdrawing without a deposit does nothing |
| `testWithdrawTokensCorrectly` | Withdraw returns the staked tokens |
| `testCanNotClaimIfNotStaking` | Claim without deposit reverts with "Not staking" |
| `testCanNotClaimIfNotElapsedTime` | Claim too early reverts with "Need to wait" |
| `testShouldRevertIfNotEther` | Claim when the app has no ETH reverts with "Transfer failed" |
| `testCanClaimRewardsCorrectly` | Claim pays `rewardPerPeriod` and updates the timer |
| `testStakingTokenMintsCorrectly` | `mint` increases the caller's balance |

## Honest review of the tests

100% coverage only means every line ran. To check that the tests really protect the code, I copied the contract, broke one thing at a time (a mutation) and ran the suite. 12 mutations, 9 caught and **3 survived**:

| Mutation | Result |
| --- | --- |
| Remove `onlyOwner` from `changeStakingPeriod` | caught |
| Remove each of the 5 `require`s (one by one) | all caught |
| Do not reset the timer when claiming | caught |
| Pay double reward | caught |
| Change `>=` to `>` in the period check | caught |
| Remove `onlyOwner` from `receive()` | **survived**: no test checks that a non-owner cannot send ETH |
| Do not set `userBalance` to 0 in `withdrawTokens` | **survived**: the test only checks the token balance, not that the record is cleared. A real bug like this would let someone withdraw and keep claiming rewards. |
| Do not emit `ChangeStakingPeriod` | **survived**: no test checks events (`vm.expectEmit`) |

Other things worth knowing about the design (course scope, not fixed here):

- `depositTokens` and `withdrawTokens` ignore the `bool` returned by `transferFrom` / `transfer` (OpenZeppelin tokens revert instead of returning `false`, but a different token might not). `SafeERC20` would cover it.
- `claimRewards` pays a fixed reward per valid claim: waiting several periods does not pay several rewards.
- Changing `stakingPeriod` also affects deposits that already exist.
- Unclaimed rewards are lost if the user withdraws.
- `fixedStakingAmount = 10` in the tests means 10 minimal units of the token, not 10 whole tokens.
- The test period (`100000000000000` seconds) is deliberately huge so `vm.warp` can jump past it.

## Possible next steps

- Add the three missing tests (non-owner cannot fund the app, `userBalance` is 0 after a withdraw, `vm.expectEmit` for each event).
- A test with two claims in a row and one where the owner refunds the app after a failed claim.
- Fuzz tests for the deposit amount and the elapsed time.

## Project structure

```
src/StakingApp.sol            staking logic
src/StakingToken.sol          ERC-20 test token
test/StakingAppTest.t.sol     14 tests
test/StakingTokenTest.t.sol   1 test
docs/TESTS.md                 every test explained
evidencias/                   real forge test + coverage output
```

## Run it

```bash
git clone --recurse-submodules <repo-url>
cd staking-app-foundry
forge test
```

## License

MIT

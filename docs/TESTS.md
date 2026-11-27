# Tests explained

Every test below passes (`forge test`: 15 passed, 0 failed). For each one: what it does, whether it is solid, and what a stronger version would add. "Mutation" refers to the check described in the README: I broke the contract on purpose and looked at which tests failed.

Setup shared by the app tests (`setUp`): deploy `StakingToken`, then `StakingApp` with `fixedStakingAmount = 10`, `stakingPeriod = 100000000000000`, `rewardPerPeriod = 1 ether`, `owner = vm.addr(1)`. The staker is `randomUser = vm.addr(2)`.

## Deployment and permissions

### `testStakingTokenCorrectCorrectlyDeployed` / `testStakingAppCorrectCorrectlyDeployed`
Check that each contract has a non-zero address. **Valid but weak**: they only prove deployment worked. Stronger: compare `stakingApp.stakingToken()`, `owner()`, `stakingPeriod()`, `fixedStakingAmount()` and `rewardPerPeriod()` with the constructor values.

### `testShouldRevertIfNotOwner`
Calls `changeStakingPeriod` with `vm.expectRevert()` and no prank. **Valid** (mutation "remove `onlyOwner`" is caught), with two limits: the caller is the test contract itself (not a random user), and `expectRevert()` without a message accepts any revert. Stronger: prank `randomUser` and expect `OwnableUnauthorizedAccount(randomUser)`.

### `testShouldChangeStakingPeriod`
As owner (`vm.startPrank`), changes the period to 1 and checks the value was different before and equal after. **Valid.** Does not check the `ChangeStakingPeriod` event (mutation "do not emit" survives); `vm.expectEmit` would fix it.

### `testContractReceivesEtherCorrectly`
Gives the owner 1 ether with `vm.deal`, sends it to the app with `.call{value}("")`, checks `success` and that the app balance grew by exactly that amount. **Valid for the happy path.** It does not prove a non-owner is rejected: mutation "remove `onlyOwner` from `receive`" **survives**.

## `depositTokens`

### `testIncorrectAmountShouldRevert`
`randomUser` deposits 1 (the fixed amount is 10) and expects the exact message "Incorrect Amount". **Valid and well written**: passing the message guarantees it reverts for that reason and not for a missing `approve` (when I removed this `require`, the test failed with `ERC20InsufficientAllowance`).

### `testDepositTokensCorrectly`
Mint, `approve`, deposit. Checks `userBalance` grew by the amount and the timestamp went from 0 to `block.timestamp`. **Valid.** Stronger: also check the user's token balance goes down and the app's token balance goes up.

### `testUserCanNotDepositMoreThanOnce`
Deposits once, mints and approves again, then expects "User already deposited". **Valid** (mutation "remove the require" is caught). Minting and approving again makes sure the only blocker is the existing deposit.

## `withdrawTokens`

### `testCanOnlyWithdraw0WithoutDeposit`
Withdraws with no deposit and checks `userBalance` is unchanged (0). **Valid but documents behavior rather than protecting a rule**: the function does not revert without a deposit. A `require(balance > 0)` would break this test on purpose. It also checks the mapping, not the token balance.

### `testWithdrawTokensCorrectly`
Deposits, stores the token balance and the recorded deposit, withdraws, and checks the token balance is the old one plus the recorded deposit. **Valid for what it checks, but incomplete**: it never checks `userBalance` is 0 afterwards. Mutation "do not zero `userBalance`" **survives**, and that is the most important gap. Stronger: `assertEq(stakingApp.userBalance(randomUser), 0)` and check the app's token balance dropped.

## `claimRewards`

### `testCanNotClaimIfNotStaking`
Claims with no deposit, expects "Not staking". **Valid** (mutation caught).

### `testCanNotClaimIfNotElapsedTime`
Deposits and claims in the same block, expects "Need to wait". **Valid** (mutation caught). Works because everything inside a test runs at the same `timestamp`.

### `testShouldRevertIfNotEther`
Deposits, `vm.warp(block.timestamp + stakingPeriod)`, claims on an app with no ETH, expects "Transfer failed". **Valid** (removing the `require` is caught). Note `expectRevert` goes right before `claimRewards`, not before `warp`, because it applies to the next call.

### `testCanClaimRewardsCorrectly`
Three actors: the user deposits, the owner funds the app (`vm.deal` + `.call`), the user warps one period and claims. Checks the user's ETH grew by exactly `rewardPerPeriod` and the timer was reset to `block.timestamp`. **The strongest test of the suite**: caught "double reward", "no timer reset" and `>=` vs `>`. Stronger: check the app's ETH went down by the same amount, that the token deposit is still there, and that an immediate second claim reverts with "Need to wait".

## `StakingToken`

### `testStakingTokenMintsCorrectly`
Mints 1 ether (1e18 units) as `randomUser` and checks the balance difference. **Valid.**

## Extra tests (`StakingAppGapsTest`)

- `testNonOwnerCanNotFundApp`: a user with ETH tries to send it to the app; `success` must be false and the app balance 0. Kills "remove `onlyOwner` from `receive`".
- `testWithdrawClearsUserBalance`: deposit, withdraw, then `userBalance` is 0 and the app holds no tokens. Kills "do not zero `userBalance`".
- `testChangeStakingPeriodEmitsEvent`: `vm.expectEmit` on `ChangeStakingPeriod`. Kills "do not emit".

All three pass on the real contract and fail on their mutation (12 of 12 mutations are now caught).

## Summary

| Result | Count |
| --- | --- |
| Tests passing | 18 / 18 (15 course + 3 extra) |
| Line / statement / branch / function coverage of `StakingApp` | 100% |
| Mutations caught | 9 of 12 with the course suite, 12 of 12 with the extra tests |
| Gaps found | `receive` access control, `withdrawTokens` clearing `userBalance`, events |

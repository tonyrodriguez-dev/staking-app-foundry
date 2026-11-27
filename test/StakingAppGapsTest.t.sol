// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/StakingToken.sol";
import "../src/StakingApp.sol";

// Extra tests that close the 3 gaps found by the mutation check.
contract StakingAppGapsTest is Test {
    StakingToken stakingToken;
    StakingApp stakingApp;

    address owner_ = vm.addr(1);
    address randomUser = vm.addr(2);
    uint256 stakingPeriod_ = 100000000000000;
    uint256 fixedStakingAmount_ = 10;
    uint256 rewardPerPeriod_ = 1 ether;

    event ChangeStakingPeriod(uint256 newStakingPeriod_);

    function setUp() external {
        stakingToken = new StakingToken("Staking Token", "STK");
        stakingApp =
            new StakingApp(address(stakingToken), owner_, stakingPeriod_, fixedStakingAmount_, rewardPerPeriod_);
    }

    // Gap 1: only the owner can fund the app (kills "remove onlyOwner from receive")
    function testNonOwnerCanNotFundApp() external {
        vm.deal(randomUser, 1 ether);

        vm.startPrank(randomUser);
        (bool success,) = address(stakingApp).call{value: 1 ether}("");
        vm.stopPrank();

        assertFalse(success);
        assertEq(address(stakingApp).balance, 0);
    }

    // Gap 2: withdraw clears the internal record (kills "do not zero userBalance")
    function testWithdrawClearsUserBalance() external {
        vm.startPrank(randomUser);
        stakingToken.mint(fixedStakingAmount_);
        stakingToken.approve(address(stakingApp), fixedStakingAmount_);
        stakingApp.depositTokens(fixedStakingAmount_);
        stakingApp.withdrawTokens();
        vm.stopPrank();

        assertEq(stakingApp.userBalance(randomUser), 0);
        assertEq(stakingToken.balanceOf(address(stakingApp)), 0);
    }

    // Gap 3: the event is emitted (kills "do not emit ChangeStakingPeriod")
    function testChangeStakingPeriodEmitsEvent() external {
        vm.startPrank(owner_);
        vm.expectEmit(false, false, false, true);
        emit ChangeStakingPeriod(1);
        stakingApp.changeStakingPeriod(1);
        vm.stopPrank();
    }
}

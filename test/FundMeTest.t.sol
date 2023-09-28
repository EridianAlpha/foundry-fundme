// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../src/FundMe.sol";
import {DeployFundMe} from "../script/DeployFundMe.s.sol";
import {TestHelper} from "../src/test/TestHelper.sol";
import {SelfDestructAttack} from "../src/test/SelfDestructAttack.sol";
import {SelfDestructHelper} from "../src/test/SelfDestructHelper.sol";
import {ReentrancyAttack} from "../src/test/ReentrancyAttack.sol";

error FundMe__RefundFailed();
error FundMe__RefundNoFunds();
error FundMe__IndexNotFound();
error FundMe__WithdrawFailed();
error FundMe__WithdrawNoFunds();
error FundMe__NotEnoughEthSent();
error FundMe__WithdrawSelfDestructFailed();

// Base contract for common setup
contract FundMeTestSetup is Test {
    FundMe fundMe;
    uint256 constant GAS_PRICE = 1;
    uint256 constant SEND_VALUE = 1 ether;
    uint256 constant STARTING_BALANCE = 10 ether;

    // Create users
    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    function setUp() external {
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run(owner);
        vm.deal(owner, STARTING_BALANCE);
        vm.deal(user1, STARTING_BALANCE);
        vm.deal(user2, STARTING_BALANCE);
        vm.deal(user3, STARTING_BALANCE);
    }
}

contract FundMeConstructorTest is FundMeTestSetup {
    function test_Constructor() public {
        assertEq(fundMe.getCreator(), msg.sender);
    }
}

// **************
// FUNDING TESTS
// **************
contract FundMeFundTest is FundMeTestSetup {
    function test_FundFailsNoEthSent() public {
        vm.expectRevert(FundMe__NotEnoughEthSent.selector);
        fundMe.fund();
    }

    function test_FundFailsNotEnoughEthSent() public {
        uint256 MINIMUM_ETH_LESS = fundMe.MINIMUM_ETH() - 1;
        vm.expectRevert(FundMe__NotEnoughEthSent.selector);
        fundMe.fund{value: (MINIMUM_ETH_LESS)}();
    }

    function test_FundSucceeds() public {
        fundMe.fund{value: fundMe.MINIMUM_ETH()}();
        assertEq(fundMe.getBalance(), fundMe.MINIMUM_ETH());
    }

    function test_UpdateAmountFundedDataStructure() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getAddressToAmountFunded(user1), SEND_VALUE);
    }

    function test_FunderAddedToFundersArray() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getFunderIndex(user1), 0);
    }

    function test_NoDuplicateFundersInFundersArray() public {
        vm.startPrank(user1);
        fundMe.fund{value: SEND_VALUE}();
        fundMe.fund{value: SEND_VALUE}();

        address[] memory funders = fundMe.getFunders();
        for (uint256 i = 0; i < funders.length; i++) {
            for (uint256 j = i + 1; j < funders.length; j++) {
                assertNotEq(funders[i], funders[j]);
            }
        }
    }

    function test_FunderAddressMatchesZeroIndexOfFundersArray() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getFunderAddress(0), user1);
    }
}

// *****************
// WITHDRAWAL TESTS
// *****************
contract FundMeWithdrawTest is FundMeTestSetup {
    function test_OwnerWithdrawOnce() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(fundMe.owner());
        fundMe.withdraw();

        assertEq(fundMe.getBalance(), 0);
    }

    function test_OwnerWithdrawMultiple() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(owner);
        fundMe.withdraw();

        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(owner);
        fundMe.withdraw();
        assertEq(fundMe.getBalance(), 0);
    }

    function test_OnlyOwnerCanWithdraw() public {
        fundMe.fund{value: SEND_VALUE}();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        fundMe.withdraw();
    }

    function test_WithdrawFailsZeroBalance() public {
        vm.expectRevert(FundMe__WithdrawNoFunds.selector);
        vm.prank(owner);
        fundMe.withdraw();
    }

    function test_WithdrawCallFailureThrowsError() public {
        // This covers the edge case where the .call fails
        // because the receiving contract doesn't have a
        // receive() or fallback() function
        // Very unlikely on the withdrawal function as only the
        // owner can call it and it withdraws all funds anyway
        // but it covers this test branch and is needed for the refund test

        // Deploy the helper contract
        TestHelper testHelper = new TestHelper(address(fundMe));

        // Fund the contract
        fundMe.fund{value: SEND_VALUE}();

        // Change the owner of fundMe to the helper contract address
        // so it can perform the withdrawal
        vm.prank(owner);
        fundMe.transferOwnership(address(testHelper));

        // Withdraw from the contract
        vm.expectRevert(FundMe__WithdrawFailed.selector);
        testHelper.fundMeWithdraw();

        // If the withdraw fails, the s_funders address array should not be reset
        // (This test isn't really needed, it's just showing that revert works by
        // undoing all changes made to the state during the transaction)
        assertEq(testHelper.fundMeGetFunderAddress(0), address(this));
    }

    function test_WithdrawEthFromMultipleFunders() public {
        // Fund the contract
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            fundMe.fund{value: SEND_VALUE}();
        }

        // Check the balance is users.length * SEND_VALUE
        assertEq(fundMe.getBalance(), users.length * SEND_VALUE);

        // Withdraw from the contract
        vm.prank(owner);
        fundMe.withdraw();

        // Check the balance is zero
        assertEq(fundMe.getBalance(), 0);

        // Check the s_funders array is empty
        // TODO: This doesn't work with vm.expectRevert("Index out of bounds");
        vm.expectRevert();
        fundMe.getFunderAddress(0);

        // Check that s_addressToAmountFunded mapping is reset for all addresses
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(fundMe.getAddressToAmountFunded(users[i]), 0);
        }
    }

    function test_WithdrawSelfdestructAttackFunds() public {
        // Fund the contract
        fundMe.fund{value: SEND_VALUE}();

        // Check funds can't be withdrawn before the attack
        vm.expectRevert(FundMe__WithdrawSelfDestructFailed.selector);
        vm.prank(owner);
        fundMe.withdrawSelfdestructFunds();

        // Deploy SelfDestructAttack contract and pass fundMe.address to constructor
        SelfDestructAttack selfDestructAttack = new SelfDestructAttack(
            address(fundMe)
        );

        // Fund and perform the attack
        selfDestructAttack.attack{value: SEND_VALUE}();

        // Check extra funds exist before starting withdrawal
        require(address(fundMe).balance > fundMe.getBalance());

        // Check only owner can withdraw selfdestruct funds
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        fundMe.withdrawSelfdestructFunds();

        // Withdraw selfdestruct funds
        vm.prank(owner);
        fundMe.withdrawSelfdestructFunds();

        // Check selfdestruct funds are withdrawn correctly
        assertEq(fundMe.getBalance(), address(fundMe).balance);
    }

    function test_SelfDestructWithdrawCallFailureThrowsError() public {
        // This covers the edge case where the .call fails
        // because the receiving contract doesn't have a
        // receive() or fallback() function
        // Very unlikely on the withdrawal function as only the
        // owner can call it and it withdraws all funds anyway
        // but it covers this test branch and is needed for the refund test

        // Deploy the helper contract
        SelfDestructHelper selfDestructHelper = new SelfDestructHelper(
            address(fundMe)
        );

        // Fund the contract
        fundMe.fund{value: SEND_VALUE}();

        // Send funds and perform attack
        selfDestructHelper.attack{value: SEND_VALUE}();

        // Transfer contract ownership to allow withdrawal attempt
        vm.prank(owner);
        fundMe.transferOwnership(address(selfDestructHelper));
        selfDestructHelper.fundMeTransferOwnership();

        // Withdraw from the contract
        vm.expectRevert(FundMe__WithdrawSelfDestructFailed.selector);
        selfDestructHelper.fundMeSelfDestructWithdraw();
    }
}

// *************
// REFUND TESTS
// *************
contract FundMeWRefundTest is FundMeTestSetup {
    function test_RefundSucceeds() public {
        // User1 - Funds with no refund
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();

        // User2 - Funds once then refunds
        vm.prank(user2);
        fundMe.fund{value: SEND_VALUE}();

        // User3 - Funds twice then refunds
        vm.startPrank(user3);
        fundMe.fund{value: SEND_VALUE}();
        fundMe.fund{value: SEND_VALUE}();
        vm.stopPrank();

        // Refund user2
        uint256 user2BalanceBefore = user2.balance;
        vm.prank(user2);
        fundMe.refund();
        uint256 user2BalanceAfter = user2.balance;
        uint256 user2BalanceDiff = user2BalanceAfter - user2BalanceBefore;
        assertEq(user2BalanceDiff, SEND_VALUE);

        // Refund user3
        uint256 user3BalanceBefore = user3.balance;
        vm.prank(user3);
        fundMe.refund();
        uint256 user3BalanceAfter = user3.balance;
        uint256 user3BalanceDiff = user3BalanceAfter - user3BalanceBefore;
        assertEq(user3BalanceDiff, 2 * SEND_VALUE);

        // Check funder amount has been reset to 0
        assertEq(fundMe.getAddressToAmountFunded(user2), 0);
        assertEq(fundMe.getAddressToAmountFunded(user3), 0);

        // Check funder has been removed from the s_funders index
        vm.expectRevert(FundMe__IndexNotFound.selector);
        fundMe.getFunderIndex(user2);
        vm.expectRevert(FundMe__IndexNotFound.selector);
        fundMe.getFunderIndex(user3);

        // Check s_balance is correct (Only contains user1 funds)
        assertEq(fundMe.getBalance(), SEND_VALUE);
    }

    function test_RefundZeroBalanceFails() public {
        vm.expectRevert(FundMe__RefundNoFunds.selector);
        vm.prank(user1);
        fundMe.refund();
    }

    function test_RefundWithNonFunder() public {
        // Step 1: Fund the contract from multiple addresses
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(user2);
        fundMe.fund{value: SEND_VALUE}();

        // Step 2: Attempt to invoke the refund function from an address that didn't fund
        vm.prank(user3);
        vm.expectRevert(FundMe__RefundNoFunds.selector);
        fundMe.refund();
    }

    function test_RefundCallFailureThrowsError() public {
        // This covers the edge case where the .call fails
        // because the receiving contract doesn't have a
        // receive() or fallback() function

        // Deploy the helper contract
        TestHelper testHelper = new TestHelper(address(fundMe));

        // Fund the helper contract
        testHelper.initialFunding{value: SEND_VALUE}();

        // Fund the contract
        vm.prank(address(testHelper));
        fundMe.fund{value: SEND_VALUE}();

        // Change the owner of fundMe to the helper contract address
        // so it can perform the refund
        vm.prank(owner);
        fundMe.transferOwnership(address(testHelper));

        // Refund from the contract
        vm.expectRevert(FundMe__RefundFailed.selector);
        testHelper.fundMeRefund();
    }

    function test_RefundFunctionBlocksReentrancyAttack() public {
        // Deploy the ReentrancyAttack contract
        ReentrancyAttack reentrancyAttack = new ReentrancyAttack(
            payable(address(fundMe))
        );

        // Fund the contract
        // Deposit multiple accounts to confirm that isn't refunded in the attack
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();

        // Refund from the contract
        vm.expectRevert(FundMe__RefundFailed.selector);
        reentrancyAttack.attack{value: SEND_VALUE}();
    }
}

// Test all the getter functions
contract FundMeGettersTest is FundMeTestSetup {
    function test_GetCreator() public {
        // The deploy script for some reason doesn't use the expected
        // msg.sender as the creator, so this test requires a separate
        // contract to be deployed and tested against
        // TODO: Understand why the deploy script doesn't use the expected
        // msg.sender as the creator
        FundMe fundMeCreatorTest = new FundMe(address(this));
        assertEq(fundMeCreatorTest.getCreator(), address(this));
    }

    function test_GetOwner() public {
        assertEq(fundMe.owner(), owner);
    }

    function test_GetFunderIndex() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getFunderIndex(user1), 0);
    }

    function test_GetFunderAddress() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getFunderAddress(0), user1);
    }

    function test_GetAddressToAmountFunded() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getAddressToAmountFunded(user1), SEND_VALUE);
    }

    function test_GetBalance() public {
        assertEq(fundMe.getBalance(), 0);
    }

    function test_GetFunders() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(user2);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(user3);
        fundMe.fund{value: SEND_VALUE}();

        address[] memory funders = fundMe.getFunders();
        assertEq(funders.length, 3);
        assertEq(funders[0], user1);
        assertEq(funders[1], user2);
        assertEq(funders[2], user3);
    }
}

contract FundMeMiscTest is FundMeTestSetup {
    function test_MinimumEthAmount() public {
        assertEq(fundMe.MINIMUM_ETH(), 0.001 ether);
    }

    function test_IsMsgSender() public {
        assertEq(fundMe.getBalance(), 0);
    }

    function test_CoverageForReceiveFunction() public {
        (bool success, ) = address(fundMe).call{value: SEND_VALUE}("");
        require(success, "Call failed");
        assertEq(fundMe.getBalance(), SEND_VALUE);
    }

    function test_CoverageForFallbackFunction() public {
        (bool success, ) = address(fundMe).call{value: SEND_VALUE}("123");
        require(success, "Call failed");
        assertEq(fundMe.getBalance(), SEND_VALUE);
    }
}

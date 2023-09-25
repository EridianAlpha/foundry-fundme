// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../src/FundMe.sol";
import {DeployFundMe} from "../script/DeployFundMe.s.sol";
import {TestHelper} from "../src/test/TestHelper.sol";
import {SelfDestructAttack} from "../src/test/SelfDestructAttack.sol";
import {SelfDestructHelper} from "../src/test/SelfDestructHelper.sol";

error FundMe__WithdrawSelfDestructFailed();

// Base contract for common setup
contract FundMeTestSetup is Test {
    FundMe fundMe;
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
        vm.expectRevert();
        fundMe.fund();
    }

    function test_FundFailsNotEnoughEthSent() public {
        uint256 MINIMUM_ETH_LESS = fundMe.MINIMUM_ETH() - 1;
        vm.expectRevert();
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
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(user1);
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
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(owner);
        fundMe.withdraw();
        assertEq(fundMe.getBalance(), 0);
    }

    function test_OwnerWithdrawMultiple() public {
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(owner);
        fundMe.withdraw();
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(owner);
        fundMe.withdraw();
        assertEq(fundMe.getBalance(), 0);
    }

    function test_OnlyOwnerCanWithdraw() public {
        fundMe.fund{value: SEND_VALUE}();
        vm.expectRevert();
        vm.prank(user1);
        fundMe.withdraw();
    }

    function test_WithdrawFailsZeroBalance() public {
        vm.expectRevert();
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
        vm.expectRevert();
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
        vm.expectRevert();
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
        vm.expectRevert();
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

// Test all the getter functions
contract FundMeTest is FundMeTestSetup {
    function test_MinimumEthAmount() public {
        assertEq(fundMe.MINIMUM_ETH(), 0.001 ether);
    }

    function test_IsMsgSender() public {
        assertEq(fundMe.getBalance(), 0);
    }
}

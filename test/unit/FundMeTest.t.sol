// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";
import {TestHelper} from "../../src/test/TestHelper.sol";
import {SelfDestructAttack} from "../../src/test/SelfDestructAttack.sol";
import {SelfDestructHelper} from "../../src/test/SelfDestructHelper.sol";
import {ReentrancyAttack} from "../../src/test/ReentrancyAttack.sol";

// ================================================================
// │                 COMMON SETUP AND CONSTRUCTOR                 │
// ================================================================
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

// ================================================================
// │                        FUNDING TESTS                         │
// ================================================================
contract FundMeFundTest is FundMeTestSetup {
    /// Tests that the `fund` function reverts when no ETH is sent with the transaction.
    /// Expects a revert with the `FundMe__NotEnoughEthSent` error selector.
    function test_FundFailsNoEthSent() public {
        vm.expectRevert(FundMe.FundMe__NotEnoughEthSent.selector);
        fundMe.fund();
    }

    /// @notice Tests that the `fund` function reverts when an amount less than the minimum
    /// ETH required is sent. This ensures proper enforcement of minimum funding requirements.
    /// @dev Calculates an amount of ETH that is 1 less than the minimum required,
    /// then expects a revert with the `FundMe__NotEnoughEthSent` error selector.
    function test_FundFailsNotEnoughEthSent() public {
        uint256 MINIMUM_ETH_LESS = fundMe.MINIMUM_ETH() - 1;
        vm.expectRevert(FundMe.FundMe__NotEnoughEthSent.selector);
        fundMe.fund{value: (MINIMUM_ETH_LESS)}();
    }

    /// @notice Tests that the `fund` function successfully processes
    /// a transaction when the minimum ETH requirement is met.
    /// @dev Calls the `fund` function with exactly the minimum ETH
    /// required and checks if the contract's balance is updated correctly.
    function test_FundSucceeds() public {
        fundMe.fund{value: fundMe.MINIMUM_ETH()}();
        assertEq(fundMe.getBalance(), fundMe.MINIMUM_ETH());
    }

    /// @notice Tests that funding updates the amount funded
    /// data structure correctly.
    /// @dev Pranks a user to fund and then checks if the
    /// mapping of the address to the amount funded is updated correctly.
    function test_UpdateAmountFundedDataStructure() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getAddressToAmountFunded(user1), SEND_VALUE);
    }

    /// @notice Tests that a funder is correctly added to the funders array.
    /// @dev Pranks a user to fund and then checks if their index in the
    /// funders array is correct.
    function test_FunderAddedToFundersArray() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getFunderIndex(user1), 0);
    }

    /// @notice Ensures that no duplicate funders are added to the funders array.
    /// @dev Starts a prank running as a user, calls the fund function twice,
    /// and checks for duplicates in the funders array.
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

    /// @notice Verifies that the first funder's address in the funders array
    /// matches the provided address.
    /// @dev Pranks a user to fund and then checks if their address matches
    /// the zero index of the funders array.
    function test_FunderAddressMatchesZeroIndexOfFundersArray() public {
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        assertEq(fundMe.getFunderAddress(0), user1);
    }
}

// ================================================================
// │                      WITHDRAWAL TESTS                        │
// ================================================================
contract FundMeWithdrawTest is FundMeTestSetup {
    /// @notice Tests that the contract owner can withdraw funds once.
    /// @dev Funds the contract, then performs a withdrawal by the owner,
    /// and checks if the contract balance is zero after withdrawal.
    function test_OwnerWithdrawOnce() public {
        uint256 gasStart = gasleft();
        vm.txGasPrice(GAS_PRICE);
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(fundMe.owner());
        fundMe.withdraw();

        uint256 gasEnd = gasleft();
        uint256 gasUsed = (gasStart - gasEnd) * GAS_PRICE;
        console.log("Gas used: ", gasUsed);

        assertEq(fundMe.getBalance(), 0);
    }

    /// @notice Tests that the contract owner can perform multiple withdrawals.
    /// As the contract balance is zero after the first withdrawal, a second
    /// funding is required to test multiple withdrawals.
    /// @dev Funds the contract, withdraws, funds again, and withdraws again,
    /// finally checking if the contract balance is zero.
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

    /// @notice Ensures that only the contract owner can perform withdrawals.
    /// @dev Expects a revert when a non-owner tries to withdraw funds.
    function test_OnlyOwnerCanWithdraw() public {
        fundMe.fund{value: SEND_VALUE}();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        fundMe.withdraw();
    }

    /// @notice Tests that withdrawal fails when the contract balance is zero.
    /// @dev Expects a revert when attempting to withdraw with zero contract balance.
    function test_WithdrawFailsZeroBalance() public {
        vm.expectRevert(FundMe.FundMe__WithdrawNoFunds.selector);
        vm.prank(owner);
        fundMe.withdraw();
    }

    /// @notice Tests withdrawal failure in case of a call failure.
    /// @dev Simulates a call failure during withdrawal and expects a revert.
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
        vm.expectRevert(FundMe.FundMe__WithdrawFailed.selector);
        testHelper.fundMeWithdraw();

        // If the withdraw fails, the s_funders address array should not be reset
        // (This test isn't really needed, it's just showing that revert works by
        // undoing all changes made to the state during the transaction)
        assertEq(testHelper.fundMeGetFunderAddress(0), address(this));
    }

    /// @notice Tests withdrawal of ETH from multiple funders.
    /// @dev Funds the contract from multiple addresses, withdraws, and then
    /// checks if the contract balance and funders are reset correctly.
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

    /// @notice Tests withdrawal of self-destruct sent funds.
    /// @dev Simulates a self-destruct attack, then attempts withdrawal of
    /// these funds, checking for correct handling and owner restrictions.
    function test_WithdrawSelfdestructAttackFunds() public {
        // Fund the contract
        fundMe.fund{value: SEND_VALUE}();

        // Check funds can't be withdrawn before the attack
        vm.expectRevert(FundMe.FundMe__WithdrawSelfDestructFailed.selector);
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

    /// @notice Tests withdrawal failure in case of a call failure after a
    /// self-destruct attack.
    /// @dev Simulates a call failure during withdrawal after a self-destruct attack
    /// and expects a revert. Covers an edge case where the .call fails because
    /// the receiving contract doesn't have a // receive() or fallback() function.
    /// Very unlikely on the withdrawal function as only the owner can call it
    /// and it withdraws all funds anyway but it covers this test branch
    /// and is needed for the refund test.
    function test_SelfDestructWithdrawCallFailureThrowsError() public {
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
        vm.expectRevert(FundMe.FundMe__WithdrawSelfDestructFailed.selector);
        selfDestructHelper.fundMeSelfDestructWithdraw();
    }
}

// ================================================================
// │                         REFUND TESTS                         │
// ================================================================
contract FundMeWRefundTest is FundMeTestSetup {
    /// @notice Tests that the refund function succeeds under normal conditions.
    /// @dev Funds the contract with multiple users, then refunds each user and
    /// checks if balances and funders' data are correctly updated.
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
        vm.expectRevert(FundMe.FundMe__IndexNotFound.selector);
        fundMe.getFunderIndex(user2);
        vm.expectRevert(FundMe.FundMe__IndexNotFound.selector);
        fundMe.getFunderIndex(user3);

        // Check s_balance is correct (Only contains user1 funds)
        assertEq(fundMe.getBalance(), SEND_VALUE);
    }

    /// @notice Tests that refunding fails when the contract has a zero balance.
    /// @dev Attempts a refund with a user who has not funded, expecting a
    /// revert due to no funds to refund.
    function test_RefundZeroBalanceFails() public {
        vm.expectRevert(FundMe.FundMe__RefundNoFunds.selector);
        vm.prank(user1);
        fundMe.refund();
    }

    /// @notice Tests refund failure when invoked by a non-funder.
    /// @dev Funds the contract from some addresses, then attempts a refund
    /// from an address that did not fund, expecting a revert.
    function test_RefundWithNonFunder() public {
        // Fund the contract from multiple addresses
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(user2);
        fundMe.fund{value: SEND_VALUE}();

        // Attempt to invoke the refund function from an address that didn't fund
        vm.prank(user3);
        vm.expectRevert(FundMe.FundMe__RefundNoFunds.selector);
        fundMe.refund();
    }

    /// @notice Tests that a refund call failure triggers an error.
    /// @dev Simulates an edge case scenario where the refund call fails
    /// due to lack of a receive() or fallback() function, expecting a revert.
    function test_RefundCallFailureThrowsError() public {
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
        vm.expectRevert(FundMe.FundMe__RefundFailed.selector);
        testHelper.fundMeRefund();
    }

    /// @notice Tests the refund function's resilience to reentrancy attacks.
    /// @dev Attempts a reentrancy attack on the refund function and expects
    /// a revert, confirming security against such attacks.
    function test_RefundFunctionBlocksReentrancyAttack() public {
        // Deploy the ReentrancyAttack contract
        ReentrancyAttack reentrancyAttack = new ReentrancyAttack(
            payable(address(fundMe))
        );

        // Fund the contract from a user that will be different to the attacker
        // to show that only the attackers funds are returned
        vm.prank(user1);
        fundMe.fund{value: SEND_VALUE}();

        // Attack the contract with the ReentrancyAttack contract
        vm.expectRevert(FundMe.FundMe__RefundFailed.selector);
        reentrancyAttack.attack{value: SEND_VALUE}();
    }
}

// ================================================================
// │                        GETTERS TESTS                         │
// ================================================================
contract FundMeGettersTest is FundMeTestSetup {
    function test_GetCreator() public {
        assertEq(fundMe.getCreator(), msg.sender);
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

// ================================================================
// │                          MISC TESTS                          │
// ================================================================
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

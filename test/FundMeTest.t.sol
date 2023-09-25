// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../src/FundMe.sol";

contract FundMeTest is Test {
    FundMe fundMe;

    function setUp() external {
        fundMe = new FundMe();
    }

    function testMinimumEthAmount() public {
        assertEq(fundMe.MINIMUM_ETH(), 1 * 10 ** 15);
    }

    function testIsMsgSender() public {
        assertEq(fundMe.getBalance(), 0);
    }
}

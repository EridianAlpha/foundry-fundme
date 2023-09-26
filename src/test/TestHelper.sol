// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../FundMe.sol";

error TestHelper__FundMeFundFailed();

/**
 * This contract is used to test the .call functions failing in FundMe.sol
 * The test is found in FundMeTest.t.sol:
 * - "Withdraw .call failure throws error"
 * - "Refund .call failure throws error"
 *
 * The reason this contract causes the .call to fail is because it doesn't have a receive()
 * or fallback() function so the withdrawn and refunded ETH can't be accepted
 */
contract TestHelper {
    FundMe fundMeContract;

    constructor(address fundMeContractAddress) {
        fundMeContract = FundMe(payable(fundMeContractAddress));
    }

    function initialFunding() public payable {}

    function fundMeFund() public payable {
        fundMeContract.fund{value: msg.value}();
    }

    function fundMeWithdraw() public payable {
        fundMeContract.withdraw();
    }

    function fundMeRefund() public payable {
        fundMeContract.refund();
    }

    function fundMeGetFunderAddress(
        uint256 funderIndex
    ) public view returns (address) {
        return (fundMeContract.getFunderAddress(funderIndex));
    }
}

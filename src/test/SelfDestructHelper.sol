// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../FundMe.sol";
import "./SelfDestructAttack.sol";

/**
 * This contract is used to test the .call failing in FundMe.sol function withdrawSelfdestructFunds().
 *
 * The reason this contract causes the .call to fail is because it doesn't have a receive()
 * or fallback() function so the withdrawn and refunded ETH can't be accepted
 * This contract also requires multiple deployments of the SelfDestructAttack contract
 * which are needed to setup the attack conditions to allow the withdrawal to be accessible.
 */
contract SelfDestructHelper {
    FundMe fundMeContract;
    SelfDestructAttack selfDestructAttackContract1;
    SelfDestructAttack selfDestructAttackContract2;
    uint256 attackValue = 1 ether;

    constructor(address fundMeAddress) {
        // Deploy a new FundMe contract
        fundMeContract = FundMe(payable(fundMeAddress));

        // First contract needed to perform attack
        selfDestructAttackContract1 = new SelfDestructAttack(
            payable(address(fundMeContract))
        );

        // Second contract needed to perform withdrawal
        selfDestructAttackContract2 = new SelfDestructAttack(
            payable(address(fundMeContract))
        );
    }

    // Exposes the ownership transfer function in FundMe for the test
    function fundMeTransferOwnership() public {
        fundMeContract.transferOwnership(address(selfDestructAttackContract2));
    }

    // Exposes the attack function in FundMe for the test
    function attack() public payable {
        selfDestructAttackContract1.attack{value: attackValue}();
    }

    // Exposes the withdrawal function in FundMe for the test
    function fundMeSelfDestructWithdraw() public payable {
        selfDestructAttackContract2.fundMeContractWithdrawSelfdestructFunds();
    }
}

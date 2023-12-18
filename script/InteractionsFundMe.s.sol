// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";
import {FundMe} from "src/FundMe.sol";

contract FundFundMe is Script {
    uint256 SEND_VALUE = 0.1 ether;

    function fundFundMe(address fundMeAddress) public {
        console.log("Funding FundMe with %s", SEND_VALUE);

        vm.startBroadcast();
        FundMe(payable(fundMeAddress)).fund{value: SEND_VALUE}();
        vm.stopBroadcast();

        console.log(
            "FundMe balance after funding %s",
            address(fundMeAddress).balance
        );
    }

    function run() external {
        address fundMeAddress = DevOpsTools.get_most_recent_deployment(
            "FundMe",
            block.chainid
        );
        fundFundMe(fundMeAddress);
    }
}

contract WithdrawFundMe is Script {
    function withdrawFundMe(address fundMeAddress) public {
        console.log(
            "FundMe balance before withdraw %s",
            address(fundMeAddress).balance
        );

        vm.startBroadcast();
        FundMe(payable(fundMeAddress)).withdraw();
        vm.stopBroadcast();

        console.log(
            "FundMe balance after withdraw %s",
            address(fundMeAddress).balance
        );
    }

    function run() external {
        address fundMeAddress = DevOpsTools.get_most_recent_deployment(
            "FundMe",
            block.chainid
        );
        withdrawFundMe(fundMeAddress);
    }
}

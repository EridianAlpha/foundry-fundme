// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";
import {FundMe} from "src/FundMe.sol";

contract Setup is Script {
    address public fundMeAddress;

    constructor() {
        fundMeAddress = getFundMeAddress();
    }

    function getFundMeAddress() internal view returns (address) {
        address _fundMeAddress = DevOpsTools.get_most_recent_deployment(
            "FundMe",
            block.chainid
        );
        require(_fundMeAddress != address(0), "FundMe address is invalid");
        return _fundMeAddress;
    }
}

contract FundFundMe is Script, Setup {
    uint256 SEND_VALUE = 0.1 ether;

    function fundFundMe(address fundMeAddress) public {
        vm.startBroadcast();
        FundMe(payable(fundMeAddress)).fund{value: SEND_VALUE}();
        vm.stopBroadcast();
    }

    function run() public {
        fundFundMe(fundMeAddress);
    }
}

contract WithdrawFundMe is Script, Setup {
    function withdrawFundMe(address fundMeAddress) public {
        vm.startBroadcast();
        FundMe(payable(fundMeAddress)).withdraw();
        vm.stopBroadcast();
    }

    function run() public {
        withdrawFundMe(fundMeAddress);
    }
}

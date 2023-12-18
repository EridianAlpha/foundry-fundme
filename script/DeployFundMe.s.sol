// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {FundMe} from "../src/FundMe.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployFundMe is Script {
    // Overload the run function to allow owner address to be optional
    function run() public returns (FundMe) {
        return run(msg.sender);
    }

    function run(address owner) public returns (FundMe) {
        HelperConfig helperConfig = new HelperConfig();
        address priceFeed = helperConfig.activeNetworkConfig();

        vm.startBroadcast();
        FundMe fundMe = new FundMe(owner, priceFeed);
        vm.stopBroadcast();

        return fundMe;
    }
}

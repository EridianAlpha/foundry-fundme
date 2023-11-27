// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {FundMe} from "../src/FundMe.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployFundMe is Script {
    function run(address owner) external returns (FundMe) {
        // Before startBroadcast -> Not a "real" tx
        HelperConfig helperConfig = new HelperConfig();
        address priceFeed = helperConfig.activeNetworkConfig();

        // After startBroadcast -> "Real" tx
        // Specify the user deploying the contract as the initial owner
        vm.startBroadcast(owner);
        FundMe fundMe = new FundMe(owner, priceFeed);

        vm.stopBroadcast();
        return fundMe;
    }
}

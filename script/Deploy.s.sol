// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";
import "../src/MyGovernor.sol";
import "../src/Treasury.sol";
import "../src/Box.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployDAO is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        GovernanceToken govToken = new GovernanceToken(
            100_000_000e18,
            deployer,
            deployer,
            deployer,
            deployer
        );

        TokenVesting vesting = new TokenVesting(
            address(govToken),
            deployer,
            block.timestamp,
            365 days
        );

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock = new TimelockController(
            2 days,
            proposers,
            executors,
            deployer
        );

        MyGovernor governor = new MyGovernor(govToken, timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        Treasury treasury = new Treasury(address(timelock));
        Box box = new Box(address(timelock));

        console.log("GovernanceToken deployed at:", address(govToken));
        console.log("MyGovernor deployed at:", address(governor));
        console.log("TimelockController deployed at:", address(timelock));
        console.log("Treasury deployed at:", address(treasury));
        console.log("Box deployed at:", address(box));

        vm.stopBroadcast();
    }
}

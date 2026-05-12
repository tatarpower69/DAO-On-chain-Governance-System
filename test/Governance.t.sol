// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";
import "../src/MyGovernor.sol";
import "../src/Treasury.sol";
import "../src/Box.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract GovernanceTest is Test {
    GovernanceToken govToken;
    TokenVesting vesting;
    MyGovernor governor;
    TimelockController timelock;
    Treasury treasury;
    Box box;

    address admin = address(1);
    address team = address(2);
    address treasuryAddr = address(3);
    address airdrop = address(4);
    address liquidity = address(5);
    address voter1 = address(6);
    address voter2 = address(7);

    uint256 constant INITIAL_SUPPLY = 100_000_000e18;
    uint256 constant VESTING_DURATION = 365 days;

    function setUp() public {
        govToken = new GovernanceToken(INITIAL_SUPPLY, team, treasuryAddr, airdrop, liquidity);

        vesting = new TokenVesting(address(govToken), team, block.timestamp, VESTING_DURATION);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        timelock = new TimelockController(2 days, proposers, executors, admin);

        governor = new MyGovernor(govToken, timelock);

        vm.startPrank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();

        treasury = new Treasury(address(timelock));
        box = new Box(address(timelock));

        uint256 teamBalance = govToken.balanceOf(team);
        vm.prank(team);
        govToken.transfer(address(vesting), teamBalance);

        vm.prank(treasuryAddr);
        govToken.transfer(voter1, 10_000_000e18);
        vm.prank(treasuryAddr);
        govToken.transfer(voter2, 5_000_000e18);

        vm.prank(voter1);
        govToken.delegate(voter1);
        vm.prank(voter2);
        govToken.delegate(voter2);

        vm.roll(block.number + 1);
    }

    function testInitialDistribution() public {
        assertEq(govToken.balanceOf(address(vesting)), INITIAL_SUPPLY * 40 / 100);
        assertEq(govToken.balanceOf(airdrop), INITIAL_SUPPLY * 20 / 100);
    }

    function testDelegation() public {
        vm.prank(airdrop);
        govToken.delegate(voter1);
        assertEq(govToken.getVotes(voter1), 10_000_000e18 + 20_000_000e18);
    }

    function testVotingPowerSnapshots() public {
        uint256 startVotes = govToken.getVotes(voter1);
        vm.prank(voter1);
        govToken.transfer(voter2, 1_000_000e18);
        assertEq(govToken.getVotes(voter1), startVotes - 1_000_000e18);
    }

    function testVestingStart() public {
        vm.expectRevert("No tokens are due for release");
        vesting.release();
    }

    function testVestingHalfway() public {
        vm.warp(block.timestamp + VESTING_DURATION / 2);
        uint256 expected = (INITIAL_SUPPLY * 40 / 100) / 2;
        vesting.release();
        assertEq(govToken.balanceOf(team), expected);
    }

    function testVestingFull() public {
        vm.warp(block.timestamp + VESTING_DURATION + 1);
        vesting.release();
        assertEq(govToken.balanceOf(team), INITIAL_SUPPLY * 40 / 100);
    }

    function testPermit() public {}

    function testFullProposalLifecycle() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 42);
        string memory description = "Proposal #1: Store 42 in Box";

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + 2 days + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(box.retrieve(), 42);
    }

    function testProposalFailureQuorum() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 100);
        string memory description = "Fail Proposal";

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.roll(block.number + governor.votingPeriod() + 1);

        vm.expectRevert();
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testTreasuryTransfer() public {
        vm.deal(address(treasury), 10 ether);

        address recipient = address(99);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("withdrawEth(address,uint256)", recipient, 5 ether);

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Withdraw 5 ETH");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        governor.queue(targets, values, calldatas, keccak256(bytes("Withdraw 5 ETH")));
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes("Withdraw 5 ETH")));

        assertEq(recipient.balance, 5 ether);
    }

    function testProposalDefeated() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 99);

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Defeated Proposal");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 0);

        vm.roll(block.number + governor.votingPeriod() + 1);

        vm.expectRevert();
        governor.queue(targets, values, calldatas, keccak256(bytes("Defeated Proposal")));
    }

    function testProposalCanceled() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 11);

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Cancel Proposal");

        vm.prank(voter1);
        governor.cancel(targets, values, calldatas, keccak256(bytes("Cancel Proposal")));

        assertEq(uint8(governor.state(proposalId)), 2);
    }

    function testVoteAbstain() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 22);

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Abstain Proposal");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 2);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(abstainVotes, 10_000_000e18);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
    }

    function testDelegateToOther() public {
        vm.prank(airdrop);
        govToken.delegate(voter2);
        assertEq(govToken.getVotes(voter2), 5_000_000e18 + 20_000_000e18);
    }

    function testProposeWithoutEnoughVotes() public {
        vm.prank(address(999));
        vm.expectRevert();
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "Invalid Proposal");
    }

    function testQueueBeforeVotingEnds() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 33);

        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "Early Queue");

        vm.expectRevert();
        governor.queue(targets, values, calldatas, keccak256(bytes("Early Queue")));
    }

    function testExecuteBeforeTimelockDelay() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 44);
        string memory desc = "Early Execute";

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        governor.queue(targets, values, calldatas, keccak256(bytes(desc)));

        vm.expectRevert();
        governor.execute(targets, values, calldatas, keccak256(bytes(desc)));
    }

    function testTreasuryWithdrawToken() public {
        vm.prank(treasuryAddr);
        govToken.transfer(address(treasury), 1000e18);

        address recipient = address(99);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] =
            abi.encodeWithSignature("withdrawToken(address,address,uint256)", address(govToken), recipient, 500e18);

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Withdraw Tokens");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        governor.queue(targets, values, calldatas, keccak256(bytes("Withdraw Tokens")));
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes("Withdraw Tokens")));

        assertEq(govToken.balanceOf(recipient), 500e18);
    }

    function testGovernorSettings() public {
        assertEq(governor.votingDelay(), 0);
        assertEq(governor.votingPeriod(), 50400);
        assertEq(governor.quorumNumerator(), 4);
    }

    function testTimelockMinDelay() public {
        assertEq(timelock.getMinDelay(), 2 days);
    }
}

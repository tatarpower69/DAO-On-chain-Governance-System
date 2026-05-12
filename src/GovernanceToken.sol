// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    constructor(uint256 initialSupply, address team, address treasury, address airdrop, address liquidity)
        ERC20("Governance Token", "GTK")
        ERC20Permit("Governance Token")
        Ownable(msg.sender)
    {
        uint256 teamAmount = (initialSupply * 40) / 100;
        uint256 treasuryAmount = (initialSupply * 30) / 100;
        uint256 airdropAmount = (initialSupply * 20) / 100;
        uint256 liquidityAmount = initialSupply - teamAmount - treasuryAmount - airdropAmount;

        _mint(team, teamAmount);
        _mint(treasury, treasuryAmount);
        _mint(airdrop, airdropAmount);
        _mint(liquidity, liquidityAmount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

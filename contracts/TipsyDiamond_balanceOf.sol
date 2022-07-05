// SPDX-License-Identifier: MIT
// Super basic contract to combine TipsyCoin + TipsyStake balance for TipsyDiamond checks

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ITipsyStakeBal {
    function getUserBal(address user) external view returns (uint);
}

contract TipsyDiamond_Balance is IERC20, IERC20Metadata, Ownable {

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint256 internal _totalSupply;
    address public tipsyCoin;
    address public tipsyStake;
    //100mill = 100e6 * 1e18 == 100e24
    uint public tipsyDiamondMin = 100e24;

    constructor (address _tipsyCoin, address _tipsyStake)
    {
        _symbol = "$tipsy";
        _name = "TipsyCoin";
        _decimals = 18;
        _totalSupply = ~uint256(0);
        tipsyCoin = _tipsyCoin;
        tipsyStake = _tipsyStake;

    }

    function setTipsyCoinAddress(address newAddy) onlyOwner public returns (address) 
    {
        tipsyCoin = newAddy;
        return tipsyCoin;
    }

    function setTipsyStakeAddress(address newAddy) onlyOwner public returns (address) 
    {
        tipsyStake = newAddy;
        return tipsyStake;
    }


    function setTipsyDiamondMin(uint newAmount) onlyOwner public returns (uint)
    {
        tipsyDiamondMin = newAmount;
        return tipsyDiamondMin;
    }

    function name(
    ) public view returns (string memory)
    {
        return _name;
    }

    function symbol(
    ) public view returns (string memory)
    {
        return _symbol;
    }

        function decimals(
    ) public view returns (uint8)
    {
        return _decimals;
    }
    function totalSupply(
    ) public view returns (uint256)
    {
        return _totalSupply;
    }

        function balanceOf(address account) public view returns (uint256)
    {
        uint comboBalance = IERC20(tipsyCoin).balanceOf(account) + ITipsyStakeBal(tipsyStake).getUserBal(account);
        return comboBalance;
    }

    function isDiamond(address account) public view returns (bool)
    {
        uint comboBalance = IERC20(tipsyCoin).balanceOf(account) + ITipsyStakeBal(tipsyStake).getUserBal(account);
        return comboBalance >= tipsyDiamondMin;
    }

    function approve(
       address _spender, 
       uint256 _value
    ) public override
      returns (bool) 
    {
        revert("Balance + Stake balance viewer only, you may not transfer");
        return true;
   }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        revert("Balance + Stake balance viewer only, you may not transfer");
        return true;
    }

    function allowance(
        address _owner, 
        address _spender
    ) public override view 
      returns (uint256) 
    {
        return ~uint256(0);
    }


    function transfer(address recipient, uint256 amount) public returns (bool) {
        revert("Balance + Stake balance viewer only, you may not transfer");
        return true;
    }

}

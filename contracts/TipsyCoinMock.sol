//SPDX-License-Identifier: MIT

//This file is not part of the audit, but is useful for testing the functionality of our staking platform
//Without the need to deploy TipsyCoin proper on a testnet. Which is a pain, because TipsyCoin integrates with PancakeSwap
//This file manages the relevant reflex and real space functions without the need for PCS
//It also has a mintTo function, so it can be used as our Gin stand-in, too 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract ERC20 is IERC20 {

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint256 internal _totalSupply;
    uint256 public _rTotal;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowed;

    event Mint(address indexed minter, address indexed account, uint256 amount);
    event Burn(address indexed burner, address indexed account, uint256 amount);

    constructor ()
    {
        _symbol = "TestC";
        _name = "TestCoin1";
        _decimals = 18;
        _totalSupply = 100e6 * 1e18;
        _balances[msg.sender] = 100e6 * 1e18;
        _rTotal = 1e18;
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

    function setRTotal(uint newR) public returns (uint)
    {
        _rTotal = newR;
        return newR;
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

    function _realToReflex(uint _realSpaceTokens) public view returns (uint256 _reflexSpaceTokens)
    {
        return _realSpaceTokens * _rTotal / 1e18;
    }

    function _reflexToReal(uint _reflexSpaceTokens) public view returns (uint256 _realSpaceTokens)
    {
    return _reflexSpaceTokens * 1e18 / _rTotal;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "tipsy: transfer from the zero address");
        //require(amount > 0, "tipsy: transfer amount must be greater than zero"); Probably don't need to worry about this
        //If sender or recipient are immune from fee, don't use maxTxAmount
        //Usage of excludedFromFee means regular user to PCS enforces maxTxAmount

        uint256 realAmount = _reflexToReal(amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= realAmount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - realAmount;
        }
        _balances[recipient] += realAmount;

    }
    function balanceOf(address account) public view returns (uint256)
    {
        return _balances[account] * _rTotal / 1e18;
    }

    function approve(
       address _spender, 
       uint256 _value
    ) public override
      returns (bool) 
    {
        _allowed[msg.sender][_spender] = _value;
        
        emit Approval(msg.sender, _spender, _value);
        
        return true;
   }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {

        //Skip collecting fee if sender (person's tokens getting pulled) is excludedFromFee
        _transfer(sender, recipient, amount);
        //Emit Transfer Event. _taxTransaction emits a seperate sell fee collected event, _reflect also emits a reflect ratio changed event

        return true;
    }

    function allowance(
        address _owner, 
        address _spender
    ) public override view 
      returns (uint256) 
    {
        return _allowed[_owner][_spender];
    }

    function increaseApproval(
        address _spender, 
        uint _addedValue
    ) public
      returns (bool)
    {
        _allowed[msg.sender][_spender] = _allowed[msg.sender][_spender] - _addedValue;
        
        emit Approval(msg.sender, _spender, _allowed[msg.sender][_spender]);
        
        return true;
    }

    function decreaseApproval(
        address _spender, 
        uint _subtractedValue
    ) public
      returns (bool) 
    {
        uint oldValue = _allowed[msg.sender][_spender];
        
        if (_subtractedValue > oldValue) {
            _allowed[msg.sender][_spender] = 0;
        } else {
            _allowed[msg.sender][_spender] = oldValue - _subtractedValue;
        }
        
        emit Approval(msg.sender, _spender, _allowed[msg.sender][_spender]);
        
        return true;
   }

    function mintTo(
        address _to,
        uint _amount
    ) public returns (bool)
    {
        require(_to != address(0), 'ERC20: to address is not valid');
        require(_amount > 0, 'ERC20: amount is not valid');

        _totalSupply = _totalSupply + _amount;
        _balances[_to] = _balances[_to] + _amount;

        emit Mint(msg.sender, _to, _amount);
        return true;
    }

    function burnFrom(
        address _from,
        uint _amount
    ) internal
    {
        require(_from != address(0), 'ERC20: from address is not valid');
        require(_balances[_from] >= _amount, 'ERC20: insufficient balance');
        
        _balances[_from] = _balances[_from] - _amount;
        _totalSupply = _totalSupply - _amount;

        emit Burn(msg.sender, _from, _amount);
    }

}

//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract ERC20 is IERC20, Ownable, Pausable {


    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint256 internal _totalSupply;
    uint256 public _rTotal;

    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowed;

    event Mint(address indexed minter, address indexed account, uint256 amount);
    event Burn(address indexed burner, address indexed account, uint256 amount);

    constructor ()
    {
        _symbol = "TestC";
        _name = "TestCoin1";
        _decimals = 18;
        _totalSupply = 1000e18;
        _balances[msg.sender] = 1000e18;
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


    function transfer(
        address _to, 
        uint256 _value
    ) public override
        whenNotPaused 
      returns (bool)
    {
        require(_to != address(0), 'ERC20: to address is not valid');
        require(_value <= _balances[msg.sender], 'ERC20: insufficient balance');
        
        _balances[msg.sender] = _balances[msg.sender] - _value;
        _balances[_to] = _balances[_to] + _value;
        
        emit Transfer(msg.sender, _to, _value);
        
        return true;
    }

   function balanceOf(
       address _owner
    ) public override view returns (uint256 balance) 
    {
        return _balances[_owner];
    }

    function approve(
       address _spender, 
       uint256 _value
    ) public override
        whenNotPaused
      returns (bool) 
    {
        _allowed[msg.sender][_spender] = _value;
        
        emit Approval(msg.sender, _spender, _value);
        
        return true;
   }

   function transferFrom(
        address _from, 
        address _to, 
        uint256 _value
    ) public override
        whenNotPaused
      returns (bool) 
    {
        require(_from != address(0), 'ERC20: from address is not valid');
        require(_to != address(0), 'ERC20: to address is not valid');
        require(_value <= _balances[_from], 'ERC20: insufficient balance');
        //require(_value <= _allowed[_from][msg.sender], 'ERC20: from not allowed');

        _balances[_from] = _balances[_from] -  _value;
        _balances[_to] = _balances[_to] + _value;
        
        emit Transfer(_from, _to, _value);
        
        return true;
   }

    function allowance(
        address _owner, 
        address _spender
    ) public override view 
        whenNotPaused
      returns (uint256) 
    {
        return _allowed[_owner][_spender];
    }

    function increaseApproval(
        address _spender, 
        uint _addedValue
    ) public
        whenNotPaused
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
        whenNotPaused
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
    ) public
        whenNotPaused
    {
        require(_to != address(0), 'ERC20: to address is not valid');
        require(_amount > 0, 'ERC20: amount is not valid');

        _totalSupply = _totalSupply + _amount;
        _balances[_to] = _balances[_to] + _amount;

        emit Mint(msg.sender, _to, _amount);
    }

    function burnFrom(
        address _from,
        uint _amount
    ) public
        whenNotPaused
    {
        require(_from != address(0), 'ERC20: from address is not valid');
        require(_balances[_from] >= _amount, 'ERC20: insufficient balance');
        
        _balances[_from] = _balances[_from] - _amount;
        _totalSupply = _totalSupply - _amount;

        emit Burn(msg.sender, _from, _amount);
    }

}

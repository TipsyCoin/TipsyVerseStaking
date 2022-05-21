// SPDX-License-Identifier: MIT
// Based on Synthetix and PancakeSwap staking contracts
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


interface IGinMinter {
    function mintGin(
        address _mintTo,
        uint256 _amount
    ) external;

    function allocateGin(
        address _mintTo,
        uint256 _allocatedAmount
    ) external;
}

interface ITipsy is IERC20 {
    function _reflexToReal(
        uint _amount
    ) external view returns (uint256);

    function _realToReflex(
        uint _amount
    ) external view returns (uint256);
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
	//transfer to non 0 addy during constructor when deploying 4real to prevent our base contracts being taken over. Ensures only our proxy is usable
        //_transferOwnership(address(~uint160(0)));
        _transferOwnership(address(uint160(0)));
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable123: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() external virtual onlyOwner {
        _transferOwnership(address(0x000000000000000000000000000000000000dEaD));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function initOwnership(address newOwner) public virtual {
        require(_owner == address(0), "Ownable: owner already set");
        require(newOwner != address(0), "Ownable: new owner can't be 0 address");
        _owner = newOwner;
        emit OwnershipTransferred(address(0), newOwner);
    }

}
/**
 * @title Storage
 * @dev Store & retrieve value in a variable
 */
contract TipsyStaking is Ownable, Initializable, Pausable {

    //mapping(address => uint) private stakedBalances;
    mapping(address => UserAction) public userInfoMap;

    mapping(uint8 => UserLevel2) public UserLevels; 
    mapping(uint8 => string) LevelNames; 

    uint256 public totalWeight;

    uint8 private _levelCount;

    address private WETH;

    //address public lpTimelock;
    
    address internal TipsyAddress;
    ITipsy public TipsyCoin;
    address internal gin;
    IGinMinter public GinBridge;

    uint public lockDuration;

    //uint public ginDripRate = 1e6; //Total amount of Gin to drip per second
    uint public ginDripPerUser; //Max amount per user to drip per second

    bool actualMint; //Are we actually live yet?

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

        struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of CAKEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCakePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCakePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct UserAction{
        uint256 lastAction;
        uint256 lastWeight;
        uint256 rewardDebt;
        uint256 lastRewardBlock;
        uint256 rewardEarnedNotMinted;
        uint8 userLevel;
        uint256 userMulti;
    }

//        struct UserLevel{
//       uint256 amountStaked;
//        uint256 stakingLevel;   }

    struct UserLevel2{
        //Minimum staked is in reflexSpace, and must be converted to realSpace before comparisons are used
        uint256 minimumStaked;
        uint256 multiplier; //1e4
    }

        event GinAllocated(
        address indexed user,
        address indexed amount
    );

        event LiveGin(
        address indexed ginAddress,
        bool indexed live
    );

        event LockDurationChanged(
        uint indexed oldLock,
        uint indexed newLock
    );

        event Staked(
        address indexed from,
        uint indexed amount,
        uint indexed newTotal
    );

        event Unstaked(
        address indexed to,
        uint indexed amount,
        uint indexed newTotal
    );

        event LevelModified(
        address indexed to,
        uint indexed amount,
        uint indexed newTotal
    );

    function reflexToReal(uint _reflexAmount) public view returns (uint){
        //Mittens note, mockup. RealVersion should use ITipsy interface
        //ITipsy(tipsy).reflexToReal(_reflexAmount);
        //return _reflexAmount * 1e18 / _rTotal;
        return ITipsy(TipsyAddress)._reflexToReal(_reflexAmount);
    }  

    function realToReflex(uint _realAmount) public view returns (uint){
        //Mittens note, mockup. RealVersion should use ITipsy interface
        //ITipsy(tipsy).realToReflex(_reflexAmount);
        //return _realAmount * _rTotal / 1e18;
        return ITipsy(TipsyAddress)._realToReflex(_realAmount);
    }  

    function ginReward(uint time, uint multiplier) public view returns(uint)
    {
        return (block.timestamp - time * ginDripPerUser * multiplier / 1e4);
    }

    function setGinAddress(address _gin) private onlyOwner
    {
        require (_gin != address(0));
        actualMint = true;
        gin = _gin;
        emit LiveGin(gin, actualMint);
    }

    //New stake strategy is to convert reflex amount to real_amount and use real_amount as weight 
    //Need to store user tier after staking so tier adjustments don't mess it ass
    function Stake(uint amount) internal whenNotPaused returns (uint)
    {
        //We have to be careful about a first harvest, because userLevel inits to 0, which is an actual real level
        //And lastRewardBlock will init to 0, too, so a billion tokens will be allocated
 
        Harvest();
        uint realAmount = reflexToReal(amount);

        //IERC20(tipsy).transferFrom(msg.sender, address(this), amount);
        //Measure all weightings in real space

        userInfoMap[msg.sender].lastAction = block.timestamp;
        userInfoMap[msg.sender].lastWeight += realAmount;
        userInfoMap[msg.sender].userLevel = getLevel(userInfoMap[msg.sender].lastWeight);
        userInfoMap[msg.sender].userMulti = UserLevels[userInfoMap[msg.sender].userLevel].multiplier;
        //Require user's stake be at a minimum level
        require(userInfoMap[msg.sender].userLevel < 255);

        totalWeight += realAmount;
        emit Staked(msg.sender, amount, userInfoMap[msg.sender].lastWeight);
        return amount;
    }

    function Kick() public whenNotPaused
    {
        Harvest();
        userInfoMap[msg.sender].userLevel = getLevel(TipsyCoin._realToReflex(userInfoMap[msg.sender].lastWeight));
        userInfoMap[msg.sender].userMulti = UserLevels[userInfoMap[msg.sender].userLevel].multiplier/1e3;
    }

    function AdminKick(address _user) public onlyOwner
    {
        userInfoMap[_user].userLevel = getLevel(TipsyCoin._realToReflex(userInfoMap[_user].lastWeight));
        userInfoMap[_user].userMulti = UserLevels[userInfoMap[_user].userLevel].multiplier/1e3;
    }

    function setLockDuration(uint _newDuration) public onlyOwner
    {
        lockDuration = _newDuration;
    }

    function GetLockDurationOK(address _user) public view returns (bool)
    {
        return userInfoMap[_user].lastAction + lockDuration <= block.timestamp;   
    }

    //New unstake strategy is to convert real_amount weight to reflex amount and use real_amount as weight 
    //In live version, Unstake will be internal only, users must unstake all
    function Unstake(uint _amount) public whenNotPaused returns(uint _tokenToReturn)
    {   
        uint realAmount = reflexToReal(_amount);
        require(GetLockDurationOK(msg.sender), "Can't unstake before lock is up!");
        require(_amount > 0, "Can't unstake 0");
        require (userInfoMap[msg.sender].lastWeight >= realAmount, "Can't unstake this much");
        Harvest();

        //_tokenToReturn = IERC20(tipsy).balanceOf(address(this)) * totalWeight / realAmount;
        //instead assume tokens == totalWeight
        
        _tokenToReturn = totalWeight * realAmount / totalWeight;
        totalWeight -= realAmount;
        userInfoMap[msg.sender].lastWeight -= realAmount;
        //userInfoMap[msg.sender].lastAction = block.timestamp;

        //do a transfer to user
        //IERC20(tipsy).transfer(msg.sender, _tokenToReturn);
        emit Unstaked(msg.sender, _amount, userInfoMap[msg.sender].lastWeight);
        return _tokenToReturn;
    }

    function UnstakeAll() public whenNotPaused returns (uint _tokenToReturn)
    {
        require(GetLockDurationOK(msg.sender), "Can't unstake before lock is up!");
        require(userInfoMap[msg.sender].lastWeight > 0, "Can't unstake 0");
        Harvest();
        //userInfoMap[msg.sender].lastAction = block.timestamp;
        //_tokenToReturn = TipsyCoin.balanceOf(address(this)) * realAmount / totalWeight;
        //instead assume 100 tokens. change to balanceOf(this)
        _tokenToReturn = totalWeight * userInfoMap[msg.sender].lastWeight / totalWeight;
        emit Unstaked(msg.sender, _tokenToReturn, 0);
        totalWeight -= userInfoMap[msg.sender].lastWeight;
        userInfoMap[msg.sender].lastWeight = 0;

        //do a transfer to user
        //TipsyCoin.transfer(msg.sender, _tokenToReturn);
        
        return _tokenToReturn;
    }

    function EmergencyUnstake() public whenPaused returns (uint _tokenToReturn)
    //Maybe? Only allow emergency withdraw if paused, and 
    {
        require(userInfoMap[msg.sender].lastWeight > 0, "Can't unstake 0");
        //userInfoMap[msg.sender].lastAction = block.timestamp;
        //_tokenToReturn = TipsyCoin.balanceOf(address(this)) * realAmount / totalWeight;
        //instead assume 100 tokens
        _tokenToReturn = totalWeight * userInfoMap[msg.sender].lastWeight / totalWeight;
        emit Unstaked(msg.sender, _tokenToReturn, 0);
        totalWeight -= userInfoMap[msg.sender].lastWeight;
        userInfoMap[msg.sender].lastWeight = 0;

        //do a transfer to user
        //TipsyCoin.transfer(msg.sender, _tokenToReturn);

        return _tokenToReturn;
    }

    //Front end needs to know how much gin has been allocated to a user, but not sent out yet
    function getAllocatedGin(address _user) public view returns (uint _amount)
    {
        return realToReflex(userInfoMap[_user].rewardEarnedNotMinted);
    }

    function getUserLevelText(address _user) public view returns (string memory _level)
    {
        _level = getLevelByStaked(TipsyCoin._realToReflex(userInfoMap[_user].lastWeight));
        return _level;
    }

    function HarvestCalc(address _user) public view returns (uint _amount)
    {
        //return (block.timestamp - userInfoMap[_user].lastRewardBlock) * ginDripPerUser * UserLevels[userInfoMap[_user].userLevel].multiplier/1e3;
        return (block.timestamp - userInfoMap[_user].lastRewardBlock) * ginDripPerUser * userInfoMap[_user].userMulti/1e3;
    }

    function Harvest() public whenNotPaused returns(uint _harvested)
    {
        _harvested = HarvestCalc(msg.sender);
        userInfoMap[msg.sender].lastRewardBlock = block.timestamp;
        if (_harvested == 0) return _harvested;

        if (!actualMint)
        {
            userInfoMap[msg.sender].rewardEarnedNotMinted += _harvested;
        }
        else if (actualMint && userInfoMap[msg.sender].rewardEarnedNotMinted > 0)
        {
            userInfoMap[msg.sender].rewardEarnedNotMinted = 0;
            _harvested = _harvested + userInfoMap[msg.sender].rewardEarnedNotMinted;
            userInfoMap[msg.sender].rewardDebt += _harvested;
            IGinMinter(gin).mintGin(msg.sender, _harvested);
        }
        else
        {
            userInfoMap[msg.sender].rewardDebt += _harvested;
            IGinMinter(gin).mintGin(msg.sender, _harvested);
        }
        return _harvested;
    }

    function GetStakeReal(address user) public view returns (uint) {

        return userInfoMap[user].lastWeight;
    }

    function GetStakeReflex(address user) public view returns (uint)
    {
        return TipsyCoin._realToReflex(userInfoMap[user].lastWeight);
    }

    constructor(address _tipsyAddress)
    {   
        //Testing only. Real version should be initialized()
        initialize(msg.sender, _tipsyAddress);
        addLevel(0, 5, 1000);
        addLevel(1, 10, 2000);
        addLevel(2, 100, 3000);
        setLevelName(0, "Tipsy Bronze");
        setLevelName(1, "Tipsy Silver");
        setLevelName(2, "Tipsy Gold");
        setLevelName(~uint8(0), "No Level");
        ginDripPerUser = 100;
        Stake(1000);
        require(getAllocatedGin(msg.sender) == 0, "Shoudn't be more than zero here");
    }

    function addLevel(uint8 _stakingLevel, uint amountStaked, uint multiplier) public onlyOwner
    {
        require(UserLevels[_stakingLevel].minimumStaked == 0, "Not a new level");
        setLevel(_stakingLevel, amountStaked, multiplier);
        _levelCount++;
    }

    function setLevel(uint8 stakingLevel, uint amountStaked, uint _multiplier) public onlyOwner
    {
        //uint256 _realAmount = ITipsy(TipsyAddress)._reflexToReal(amountStaked); 
        //SET LEVEL AMOUNT MUST BE IN REFLEX SPACE
        require(stakingLevel < ~uint8(0), "reserved for no stake status");
        if (stakingLevel == 0)
        {
            require(UserLevels[stakingLevel+1].minimumStaked == 0 || 
                    UserLevels[stakingLevel+1].minimumStaked > amountStaked, "tipsy: staking amount too low for 0");
        }
        else{
            require(UserLevels[stakingLevel-1].minimumStaked < amountStaked, "tipsy: staking amount too low for level");
        }
        UserLevels[stakingLevel].minimumStaked = amountStaked;
        UserLevels[stakingLevel].multiplier = _multiplier;
    }

    function setLevelName(uint8 stakingLevel, string memory _name) public onlyOwner
    {
        LevelNames[stakingLevel] = _name;
    }

    function deleteLevel(uint8 stakingLevel) public onlyOwner returns (bool)
    {
        require(stakingLevel == _levelCount-1, "must delete from last level");
        UserLevels[stakingLevel].minimumStaked = 0;
        UserLevels[stakingLevel].multiplier = 0;
        _levelCount--;
        return true;
    }


    function getLevel(uint amountStaked) internal view returns (uint8)
    {
        //amountStaked MUST BE IN reflexSpace
        //MinimumStake MUST BE IN reflexSpace

        //for loop not ideal here, but there will only be 3 levels, so not a big deal
        uint baseLine = UserLevels[0].minimumStaked;

        if (amountStaked < baseLine) return ~uint8(0);
        else {
            for (uint8 i = 1; i < _levelCount; i++)
            {
                if (UserLevels[i].minimumStaked > amountStaked) return i-1;
            }
        return _levelCount-1;
        }
    }

    function getLevelByStaked(uint amountStaked) public view returns (string memory)
    {
        //AMOUNT STAKED MUST BE IN REFLEX SPACE
        uint8 _stakingLevel =  getLevel(amountStaked);
        return LevelNames[_stakingLevel];
    }

    function initialize(address owner_, address _tipsyAddress) public initializer
    {   
        require(owner_ != address(0), "tipsy: owner can't be 0 address");
        require(_tipsyAddress != address(0), "tipsy: Tipsy can't be 0 address");
        TipsyAddress = _tipsyAddress;
        initOwnership(owner_);
        lockDuration = 90 days;
        actualMint = false;
        TipsyCoin = ITipsy(TipsyAddress);
        require(TipsyCoin._realToReflex(1e18) >= 1e18, "TipsyCoin function check failed");
    }
}

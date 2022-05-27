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
    function mintTo(
        address _mintTo,
        uint256 _amount
    ) external returns (bool);

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

    mapping(address => UserInfo) public userInfoMap;
    mapping(uint8 => StakingLevel) public UserLevels; 
    mapping(uint8 => string) LevelNames; 
    uint256 public totalWeight;
    uint8 private _levelCount;
    address internal TipsyAddress;
    ITipsy public TipsyCoin;
    address internal ginAddress;
    IGinMinter public GinBridge;
    uint public lockDuration;

    //uint public ginDripRate = 1e6; //Total amount of Gin to drip per second
    uint public ginDripPerUser; //Max amount per user to drip per second
    bool actualMint; //Are we actually live yet?
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    struct UserInfo{
        uint256 lastAction;
        uint256 lastWeight;
        uint256 rewardDebt;
        uint256 lastRewardBlock;
        uint256 rewardEarnedNotMinted;
        uint8 userLevel;
        uint256 userMulti;
    }

    struct StakingLevel{
        //Minimum staked is in reflexSpace, and must be converted to realSpace before comparisons are made internally
        uint256 minimumStaked; //REFLEX SPACE
        uint256 multiplier; //1e4 == 1000 == 1x
    }

    //Events
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

    //Views

    function reflexToReal(uint _reflexAmount) public view returns (uint){
        return TipsyCoin._reflexToReal(_reflexAmount);
    }  

    function realToReflex(uint _realAmount) public view returns (uint){

        return TipsyCoin._realToReflex(_realAmount);
    }  

    function setGinAddress(address _gin) private onlyOwner
    {
        require (_gin != address(0));
        GinBridge = IGinMinter(_gin);
        actualMint = true;
        ginAddress = _gin;
        require (GinBridge.mintTo(DEAD_ADDRESS, 1e18), "Tipsy: Couldn't test mint Gin");
        emit LiveGin(_gin, actualMint);
    }

    //New stake strategy is to convert reflex amount to real_amount and use real_amount as weight 
    //Need to store user tier after staking so tier adjustments don't mess it ass
    function Stake(uint amount) public whenNotPaused returns (uint)
    {
        //We have to be careful about a first harvest, because userLevel inits to 0, which is an actual real level
        //And lastRewardBlock will init to 0, too, so a billion tokens will be allocated
 
        Harvest();
        uint realAmount = reflexToReal(amount + 1);

        require(TipsyCoin.transferFrom(msg.sender, address(this), amount), "Tipsy: transferFrom user failed");
        //Measure all weightings in real space

        userInfoMap[msg.sender].lastAction = block.timestamp;
        userInfoMap[msg.sender].lastWeight += realAmount;
        userInfoMap[msg.sender].userLevel = getLevel(GetStakeReflex(msg.sender));
        userInfoMap[msg.sender].userMulti = UserLevels[userInfoMap[msg.sender].userLevel].multiplier;
        //Require user's stake be at a minimum level
        require(userInfoMap[msg.sender].userLevel < 255, "Tipsy: Amount staked insufficient for rewards");

        totalWeight += realAmount;
        emit Staked(msg.sender, amount, userInfoMap[msg.sender].lastWeight);
        return amount;
    }

    //New unstake strategy is to convert real_amount weight to reflex amount and use real_amount as weight 
    //In live version, Unstake will be removed. Decided that Users must Unstake all
    function Unstake(uint _amount) public whenNotPaused returns(uint _tokenToReturn)
    {   
        uint realAmount = reflexToReal(_amount);
        require(GetLockDurationOK(msg.sender), "Tipsy: Lock duration not expired");
        require(_amount > 0, "Tipsy: May not Unstake 0");
        require (userInfoMap[msg.sender].lastWeight >= realAmount, "Tipsy: Attempted to unstake more amount than balance");
        Harvest();
        _tokenToReturn = TipsyCoin.balanceOf(address(this)) * totalWeight / realAmount;
        //instead assume tokens == totalWeight
        _tokenToReturn = totalWeight * realAmount / totalWeight;
        totalWeight -= realAmount;
        userInfoMap[msg.sender].lastWeight -= realAmount;
        TipsyCoin.transfer(msg.sender, _tokenToReturn);
        userInfoMap[msg.sender].userLevel = 255; //~0 is no level
        userInfoMap[msg.sender].userMulti = 0; //No multi
        emit Unstaked(msg.sender, _amount, userInfoMap[msg.sender].lastWeight);
        return _tokenToReturn;
    }

    //Users may only unstake all tokens they have staked
    //Unstaking does not reset 3 month timer (pointless) 
    function UnstakeAll() public whenNotPaused returns (uint _tokenToReturn)
    {
        require(GetLockDurationOK(msg.sender), "Tipsy: Can't unstake before Lock is over");
        require(userInfoMap[msg.sender].lastWeight > 0, "Tipsy: Your staked amount is already Zero");
        Harvest();
        //todo fix the problem child
        _tokenToReturn = TipsyCoin.balanceOf(address(this)) * userInfoMap[msg.sender].lastWeight / totalWeight;
        //instead assume 100 tokens. change to balanceOf(this)
        //_tokenToReturn = totalWeight * userInfoMap[msg.sender].lastWeight / totalWeight;
        emit Unstaked(msg.sender, _tokenToReturn, 0);
        totalWeight -= userInfoMap[msg.sender].lastWeight;
        userInfoMap[msg.sender].lastWeight = 0;
        userInfoMap[msg.sender].userLevel = 255; //~0 is no level
        userInfoMap[msg.sender].userMulti = 0; //No multi

        //do a transfer to user
        require(TipsyCoin.transfer(msg.sender, _tokenToReturn), "Tipsy: transfer to user failed");
        return _tokenToReturn;
    }

    function EmergencyUnstake() public whenPaused returns (uint _tokenToReturn)
    //Maybe? Only allow emergency withdraw if paused, and user forfeits any pending harvest
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
        TipsyCoin.transfer(msg.sender, _tokenToReturn);
        return _tokenToReturn;
    }

        function Harvest() public whenNotPaused returns(uint _harvested)
    {
        _harvested = HarvestCalc(msg.sender);
        userInfoMap[msg.sender].lastRewardBlock = block.timestamp;
        if (_harvested == 0) return 0;

        if (!actualMint)
        {
            userInfoMap[msg.sender].rewardEarnedNotMinted += _harvested;
        }
        else if (actualMint && userInfoMap[msg.sender].rewardEarnedNotMinted > 0)
        {
            userInfoMap[msg.sender].rewardEarnedNotMinted = 0;
            _harvested = _harvested + userInfoMap[msg.sender].rewardEarnedNotMinted;
            userInfoMap[msg.sender].rewardDebt += _harvested;
            GinBridge.mintTo(msg.sender, _harvested);
        }
        else
        {
            userInfoMap[msg.sender].rewardDebt += _harvested;
            GinBridge.mintTo(msg.sender, _harvested);
        }
        return _harvested;
    }

    function Kick() public whenNotPaused
    {
        //User may use this to recheck their level and multiplier, without needing to stake more tokens and reset their lock
        Harvest();
        userInfoMap[msg.sender].userLevel = getLevel(GetStakeReflex(msg.sender));
        userInfoMap[msg.sender].userMulti = UserLevels[userInfoMap[msg.sender].userLevel].multiplier;
    }

    function AdminKick(address _user) public onlyOwner whenPaused
    {
        //Admin Kick() for any user. Just so we can update old weights and multipliers if they're not behaving properly
        //May only be used when Paused
        userInfoMap[_user].userLevel = getLevel(TipsyCoin._realToReflex(userInfoMap[_user].lastWeight));
        userInfoMap[_user].userMulti = UserLevels[userInfoMap[_user].userLevel].multiplier;
    }

    function setLockDuration(uint _newDuration) public onlyOwner
    {
        //Sets lock duration in seconds. Default is 90 days, or 7776000 seconds
        lockDuration = _newDuration;
    }

    function GetLockDurationOK(address _user) public view returns (bool)
    {
        //Returns whether lock duration is over. Staking resets duration, unstaking won't.
        return userInfoMap[_user].lastAction + lockDuration <= block.timestamp;   
    }

    //Front end needs to know how much gin has been allocated to a user, but not sent out yet
    //This function returns EARNED, BUT NOT LIVE Gin 
    //Function should not be used once Gin distribution begins on Polygon
    function getAllocatedGin(address _user) public view returns (uint _amount)
    {
        return userInfoMap[_user].rewardEarnedNotMinted;
    }

    //Important method, used to calculate how much gin to give to user
    function HarvestCalc(address _user) public view returns (uint _amount)
    {
        if (userInfoMap[_user].lastWeight == 0)
        {
            return 0;
        }
        else
        {
        //return (block.timestamp - userInfoMap[_user].lastRewardBlock) * ginDripPerUser * UserLevels[userInfoMap[_user].userLevel].multiplier/1e3;
        return (block.timestamp - userInfoMap[_user].lastRewardBlock) * ginDripPerUser * userInfoMap[_user].userMulti/1e3;
        }
    }

    function GetStakeReflex(address user) public view returns (uint)
    {
        return TipsyCoin._realToReflex(userInfoMap[user].lastWeight + 1);
    }

    function getLevelByWeight(uint realWeight) internal view returns (uint8)
    {
        return getLevel(TipsyCoin._realToReflex(realWeight + 1));
    }

    function getLevel(uint amountStaked) public view returns (uint8)
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

    function getLevelName(uint amountStaked) public view returns (string memory)
    {
        //AMOUNT STAKED MUST BE IN REFLEX SPACE
        uint8 _stakingLevel =  getLevel(amountStaked + 1);
        return LevelNames[_stakingLevel];
    }

    //Not used in contract, may still be useful for FrontEnd
    function getUserLevelText(address _user) public view returns (string memory _level)
    {
        _level = getLevelName(GetStakeReflex(_user));
        return _level;
    }

        function addLevel(uint8 _stakingLevel, uint amountStaked, uint multiplier) public onlyOwner
    {
        require(UserLevels[_stakingLevel].minimumStaked == 0, "Not a new level");
        setLevel(_stakingLevel, amountStaked, multiplier);
        _levelCount++;
    }

    function setLevel(uint8 stakingLevel, uint amountStaked, uint _multiplier) public onlyOwner
    {
        //SET LEVEL AMOUNT MUST BE IN REFLEX SPACE
        require(stakingLevel < ~uint8(0), "reserved for no stake status");
        if (stakingLevel == 0)
        {
            require(UserLevels[stakingLevel+1].minimumStaked == 0 || 
                    UserLevels[stakingLevel+1].minimumStaked > amountStaked, "Tipsy: staking amount set too high for Lv0");
        }
        else{
            require(UserLevels[stakingLevel-1].minimumStaked < amountStaked, "Tipsy: staking amount too low for level");
            require(UserLevels[stakingLevel+1].minimumStaked > amountStaked || UserLevels[stakingLevel+1].minimumStaked == 0, "Tipsy: staking amount too high for level");
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
        require(stakingLevel == _levelCount-1, "Tipsy: Must delete Highest level first");
        UserLevels[stakingLevel].minimumStaked = 0;
        UserLevels[stakingLevel].multiplier = 0;
        _levelCount--;
        return true;
    }

    constructor(address _tipsyAddress)
    {   
        //Testing only. Real version should be initialized() as we're using proxies
        initialize(msg.sender, _tipsyAddress);
        Stake(50e6);
        //First harvest test check
        require(getAllocatedGin(msg.sender) == 0, "Shoudn't be more than zero here");
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
        //AddLevel amount MUST BE IN REAL SPACE
        //AddLevel multiplier 1000 = 1x
        addLevel(0, 10e6, 1000); //10 Million $tipsy, 1x
        addLevel(1, 50e6, 5500); //50 Million $tipsy, 5.5x
        addLevel(2, 100e6, 12000); //100 Million $tipsy, 12x
        setLevelName(0, "Tipsy Silver");
        setLevelName(1, "Tipsy Gold");
        setLevelName(2, "Tipsy Platinum");
        setLevelName(~uint8(0), "No Stake");
        //AddLevel = Level, Amount Staked, Multiplier
        //GinDrip is PER SECOND, PER USER, based on a multiplier of 1000 (1x)
        ginDripPerUser = 1157407407407407; //100 Gin per day = 100×1e18 / 24 / 60 / 60
        require(TipsyCoin._realToReflex(1e18) >= 1e18, "TipsyCoin function check failed");
    }

    function pause() public onlyOwner whenNotPaused
    {
        _pause();
    }

    function unpause() public onlyOwner whenPaused
    {
        _unpause();
    }

    //Testing Params
        //added for TESTING
    function getUserRewardBlock(address _user) public view returns (uint256) 
    {
        return userInfoMap[_user].lastRewardBlock;
    }

    function getUserRewardDebt(address _user) public view returns (uint256) 
    {
        return userInfoMap[_user].rewardDebt;
    }

}

// SPDX-License-Identifier: MIT
// Based on Synthetix and PancakeSwap staking contracts
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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

interface ITipsy is IERC20Metadata {
    function _reflexToReal(
        uint _amount
    ) external view returns (uint256);

    function _realToReflex(
        uint _amount
    ) external view returns (uint256);

}
//We use a slightly customised Ownable contract, to ensure it works nicely with our proxy setup
//And to prevent randos from initializing / taking over the base contract
abstract contract Ownable is Context {
    address private _owner;
    address public keeper;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event KeeperTransferred(address indexed previousKeeper, address indexed newKeeper);

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
        require(owner() == _msgSender(), "TipsyOwnable: caller is not the owner");
        _;
    }

    modifier onlyOwnerOrKeeper()
    {
      require(owner() == _msgSender() || keeper == _msgSender(), "TipsyOwnable: caller is not the owner or not a keeper");   
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

    function transferKeeper(address _newKeeper) external virtual onlyOwner {
        require(_newKeeper != address(0), "Ownable: new Keeper is the zero address");
        emit KeeperTransferred(keeper, _newKeeper);
        keeper = _newKeeper;
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

contract TipsyStaking is Ownable, Initializable, Pausable, ReentrancyGuard {

    //Private / Internal Vars
    //Not private for security reasons, just to prevent clutter in bscscan
    uint8 internal _levelCount;
    address internal TipsyAddress;
    address internal ginAddress;

    //Public Vars
    mapping(address => UserInfo) public userInfoMap;
    mapping(uint8 => StakingLevel) public UserLevels; 
    mapping(uint8 => string) public LevelNames; 
    uint256 public totalWeight;
    ITipsy public TipsyCoin;
    IGinMinter public GinBridge;
    uint public lockDuration;
    uint public ginDripPerUser; //Max amount per user to drip per second
    bool actualMint; //Are we actually live yet?
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    //Structs
    struct UserInfo {
        uint256 lastAction;
        uint256 lastWeight;
        //RewardDebt currently written but not read. May be used in part of future ecosystem - don't remove
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

    event UserKicked(
        address indexed userKicked,
        uint8 indexed newLevel,
        uint indexed newMultiplier,
        bool adminKick
    );

    //View Functions
    function reflexToReal(uint _reflexAmount) public view returns (uint){
        return TipsyCoin._reflexToReal(_reflexAmount);
    }  

    function realToReflex(uint _realAmount) public view returns (uint){

        return TipsyCoin._realToReflex(_realAmount);
    }

    function getLockDurationOK(address _user) public view returns (bool)
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
    //Easy to get the math wrong here
    function harvestCalc(address _user) public view returns (uint _amount)
    {
        if (userInfoMap[_user].lastWeight == 0)
        {
            return 0;
        }
        else
        {
        //return (block.timestamp - userInfoMap[_user].lastRewardBlock) * ginDripPerUser * UserLevels[userInfoMap[_user].userLevel].multiplier/1e3;
        //Use cached User level multi
        return (block.timestamp - userInfoMap[_user].lastRewardBlock) * ginDripPerUser * userInfoMap[_user].userMulti/1e3;
        }
    }

    function getStakeReflex(address user) public view returns (uint)
    {
        return TipsyCoin._realToReflex(userInfoMap[user].lastWeight + 1);
    }

    //Unused by contract now, but may be useful for frontend
    function getLevelByWeight(uint realWeight) public view returns (uint8)
    {
        return getLevel(TipsyCoin._realToReflex(realWeight + 1));
    }

    function getLevel(uint amountStaked) public view returns (uint8)
    {
        //amountStaked MUST BE IN reflexSpace
        //MinimumStake MUST BE IN reflexSpace
        //for loop not ideal here, but are only 3 levels planned, so not a big deal
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

    //Not used in code, but may be useful for front end to easily show reflex space staked balance to user
    function getUserBal(address _user) public view returns (uint)
    {
        return (TipsyCoin._realToReflex(userInfoMap[_user].lastWeight));
    }

    //Testing View Params
    //added for TESTING
    function getUserRewardBlock(address _user) public view returns (uint256) 
    {
        return userInfoMap[_user].lastRewardBlock;
    }

    function getUserRewardDebt(address _user) public view returns (uint256) 
    {
        return userInfoMap[_user].rewardDebt;
    }

    function getLevelName(uint amountStaked) public view returns (string memory)
    {
        //AMOUNT STAKED MUST BE IN REFLEX SPACE
        uint8 _stakingLevel = getLevel(amountStaked + 1);
        return LevelNames[_stakingLevel];
    }

    //Not used in contract, may still be useful for FrontEnd
    function getUserLvlTxt_Cached(address _user) public view returns (string memory _level)
    {
        _level = LevelNames[ userInfoMap[_user].userLevel ];
        return _level;
    }

    //Public Write Functions


    //New stake strategy is to convert reflex 'amount' to real_amount and use real_amount as weight 
    //Need to store user tier after staking so tier adjustments don't mess it
    function stake(uint _amount) public whenNotPaused returns (uint)
    {
        //We have to be careful about a first harvest, because userLevel inits to 0, which is an actual real level
        //And lastRewardBlock will init to 0, too, so a bazillion tokens will be allocated
        harvest();
        //Convert reflex space _amount, into real space amount. +1 to prevent annoying division rounding errors
        //uint realAmount = reflexToReal(_amount + 1);
        //TipsyCoin public methods like transferFrom take reflex space params
        uint _prevBal = TipsyCoin.balanceOf(address(this));
        require(TipsyCoin.transferFrom(msg.sender, address(this), _amount), "Tipsy: transferFrom user failed");
        uint realAmount = TipsyCoin._reflexToReal(TipsyCoin.balanceOf(address(this))+1 - _prevBal);

        //Measure all weightings in real space
        userInfoMap[msg.sender].lastAction = block.timestamp;
        userInfoMap[msg.sender].lastWeight += realAmount;
        userInfoMap[msg.sender].userLevel = getLevel(getStakeReflex(msg.sender));
        userInfoMap[msg.sender].userMulti = UserLevels[userInfoMap[msg.sender].userLevel].multiplier;

        //Require user's stake be at a minimum level. Reminder that 255 is no level
        require(userInfoMap[msg.sender].userLevel < 255, "Tipsy: Amount staked insufficient for rewards");

        totalWeight += realAmount;
        emit Staked(msg.sender, _amount, userInfoMap[msg.sender].lastWeight);
        return _amount;
    }

    //Users may only unstake all tokens they have staked
    //Unstaking does not reset 3 month timer (pointless) 
    function unstakeAll() public whenNotPaused returns (uint _tokenToReturn)
    {
        require(getLockDurationOK(msg.sender), "Tipsy: Can't unstake before Lock is over");
        require(userInfoMap[msg.sender].lastWeight > 0, "Tipsy: Your staked amount is already Zero");
        harvest();
        //Calculate balance to return. Gets a bit difficult with reflex rewards
        //_tokenToReturn = TipsyCoin.balanceOf(address(this)) * userInfoMap[msg.sender].lastWeight / totalWeight;
	_tokenToReturn = TipsyCoin._realToReflex(userInfoMap[msg.sender].lastWeight) - 1;
        emit Unstaked(msg.sender, _tokenToReturn, 0);

        totalWeight -= userInfoMap[msg.sender].lastWeight;
        userInfoMap[msg.sender].lastWeight = 0;
        userInfoMap[msg.sender].userLevel = 255; //~0 is no level
        userInfoMap[msg.sender].userMulti = 0; //No multi

        //Transfer to user, check return
        require(TipsyCoin.transfer(msg.sender, _tokenToReturn), "Tipsy: transfer to user failed");
        return _tokenToReturn;
    }

    //Maybe? Only allow emergency withdraw if paused, and user forfeits any pending harvest
    function EmergencyUnstake() public whenPaused nonReentrant returns (uint _tokenToReturn)
    {
        require(userInfoMap[msg.sender].lastWeight > 0, "Tipsy: Can't unstake (no active stake)");
        _tokenToReturn = TipsyCoin._realToReflex(userInfoMap[msg.sender].lastWeight) - 1;
        emit Unstaked(msg.sender, _tokenToReturn, 0);
        totalWeight -= userInfoMap[msg.sender].lastWeight;
        userInfoMap[msg.sender].lastWeight = 0;
        userInfoMap[msg.sender].userLevel = 255; //~0 is no level
        userInfoMap[msg.sender].userMulti = 0; //No multi

        //do a transfer to user
        require(TipsyCoin.transfer(msg.sender, _tokenToReturn), "Tipsy: transfer to user failed");
        return _tokenToReturn;
    }

        function harvest() public whenNotPaused nonReentrant returns(uint _harvested)
    {
        //Calculate how many tokens have been earned
        _harvested = harvestCalc(msg.sender);
        userInfoMap[msg.sender].lastRewardBlock = block.timestamp;
        if (_harvested == 0) return 0;
        //Do a switch based on whether we're live Minting or just Allocating
        if (!actualMint)
        {
            userInfoMap[msg.sender].rewardEarnedNotMinted += _harvested;
        }
        else if (actualMint && userInfoMap[msg.sender].rewardEarnedNotMinted > 0)
        {
            _harvested = _harvested + userInfoMap[msg.sender].rewardEarnedNotMinted;
            userInfoMap[msg.sender].rewardEarnedNotMinted = 0;
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

    function kick() public whenNotPaused
    {
        //User may use this to sync their level and multiplier, without needing to stake more tokens and reset their lock
        //Used if for e.g. we adjust the tiers to require a lower amount of Tipsy or increase the rewards per tier
        harvest();
        userInfoMap[msg.sender].userLevel = getLevel(getStakeReflex(msg.sender));
        userInfoMap[msg.sender].userMulti = UserLevels[userInfoMap[msg.sender].userLevel].multiplier;
        emit UserKicked(msg.sender, userInfoMap[msg.sender].userLevel, userInfoMap[msg.sender].userMulti, false);
    }

    //Restricted Write Functions

    function setGinAddress(address _gin) public onlyOwner
    {
        require (_gin != address(0));
        GinBridge = IGinMinter(_gin);
        actualMint = true;
        ginAddress = _gin;
        require (GinBridge.mintTo(DEAD_ADDRESS, 1e18), "Tipsy: Couldn't test-mint some Gin");
        emit LiveGin(_gin, actualMint);
    }


    function adminKick(address _user) public onlyOwnerOrKeeper whenPaused
    {
        //Admin Kick() for any user. Just so we can update old weights and multipliers if they're not behaving properly
        //May only be used when Paused
        userInfoMap[_user].userLevel = getLevel(getStakeReflex(_user));
        userInfoMap[_user].userMulti = UserLevels[userInfoMap[_user].userLevel].multiplier;
        emit UserKicked(_user, userInfoMap[_user].userLevel, userInfoMap[_user].userMulti, true);
    }

    function setLockDuration(uint _newDuration) public onlyOwner
    {
        //Sets lock duration in seconds. Default is 90 days, or 7776000 seconds
        lockDuration = _newDuration;
    }


    function addLevel(uint8 _stakingLevel, uint amountStaked, uint multiplier) public
    {
        require(UserLevels[_stakingLevel].minimumStaked == 0, "Not a new level");
        setLevel(_stakingLevel, amountStaked, multiplier);
        _levelCount++;
    }

    function setLevel(uint8 stakingLevel, uint amountStaked, uint _multiplier) public onlyOwnerOrKeeper
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

    function setLevelName(uint8 stakingLevel, string memory _name) public onlyOwnerOrKeeper
    {
        LevelNames[stakingLevel] = _name;
    }

    function deleteLevel(uint8 stakingLevel) public onlyOwnerOrKeeper returns (bool)
    {
        require(stakingLevel == _levelCount-1, "Tipsy: Must delete Highest level first");
        UserLevels[stakingLevel].minimumStaked = 0;
        UserLevels[stakingLevel].multiplier = 0;
        _levelCount--;
        return true;
    }

    function pause() public onlyOwnerOrKeeper whenNotPaused
    {
        _pause();
    }

    function unpause() public onlyOwnerOrKeeper whenPaused
    {
        _unpause();
    }

    //Initializer Functions

    //Constructor is for Testing only. Real version should be initialized() as we're using proxies
    constructor(address _tipsyAddress)
    {   
        //Owner() = 48 hours Timelock owned by multisig will be used
        //Timelock found here: https://bscscan.com/address/0xe50B0004DC067E5D2Ff6EC0f7bf9E9d8Eb1E83a6
        //Multisig here: https://bscscan.com/address/0x884c908ea193b0bb39f6a03d8f61c938f862e153
        //Keeper will be an EOA

        initialize(msg.sender, msg.sender, _tipsyAddress);
        //stake(50e6 * 10 ** TipsyCoin.decimals());
        //require(getAllocatedGin(msg.sender) == 0, "Shoudn't be more than zero here");
        //Do anyother setup here
        //_transferOwnership(0xe50B0004DC067E5D2Ff6EC0f7bf9E9d8Eb1E83a6);
    }

    function initialize(address owner_, address _keeper, address _tipsyAddress) public initializer
    {   
        require(_keeper != address(0), "Tipsy: keeper can't be 0 address");
        require(owner_ != address(0), "Tipsy: owner can't be 0 address");
        require(_tipsyAddress != address(0), "Tipsy: Tipsy can't be 0 address");
        keeper = _keeper;
        TipsyAddress = _tipsyAddress;
        initOwnership(owner_);
        lockDuration = 90 days;
        actualMint = false;
        TipsyCoin = ITipsy(TipsyAddress);
        //AddLevel amount MUST BE IN REAL SPACE
        //AddLevel multiplier 1000 = 1x
        addLevel(0, 20e6 * 10 ** TipsyCoin.decimals()-100, 1000); //10 Million $tipsy, 1x
        addLevel(1, 100e6 * 10 ** TipsyCoin.decimals()-100, 6000); //100 Million $tipsy, 6x
        addLevel(2, 200e6 * 10 ** TipsyCoin.decimals()-100, 14000); //200 Million $tipsy, 14x
        setLevelName(0, "Tier I");
        setLevelName(1, "Tier II");
        setLevelName(2, "Tier III");
        setLevelName(~uint8(0), "No Stake");
        //AddLevel = Level, Amount Staked, Multiplier
        //GinDrip is PER SECOND, PER USER, based on a multiplier of 1000 (1x)
        ginDripPerUser = 1157407407407407; //100 Gin per day = 100×1e18 / 24 / 60 / 60
        //require(TipsyCoin._realToReflex(1e18) >= 1e18, "TipsyCoin: test check fail");
    }
}

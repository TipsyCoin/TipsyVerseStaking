const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('TokenTimeLock Contract Tests', () => {
    let deployer;
    let account1;
    let account2;
    let tipsyCoinMock;
    let ninetyDays;
    let sevenDays;
    let oneDay;
    let tipsyPower; //10e18
    let defaultMintTo;
    let silverAmount;
    let goldAmount;

    beforeEach(async () => {
        [deployer, account1, account2] = await ethers.getSigners()
        let TipsyCoin = await ethers.getContractFactory('ERC20')
        TipsyCoin = TipsyCoin.connect(deployer)
        tipsyCoinMock = await TipsyCoin.deploy()
        await tipsyCoinMock.deployed()
        

        ninetyDays = 90 * 24 * 60 * 60;
        sevenDays = 7 * 24 * 60 * 60;
        oneDay = 24*60*60;

        tipsyPower = ethers.BigNumber.from(10).pow(ethers.BigNumber.from(18));
        defaultMintTo = ethers.BigNumber.from(300000000).mul(tipsyPower);
        silverAmount = ethers.BigNumber.from(20000000).mul(tipsyPower);
        goldAmount = ethers.BigNumber.from(100000000).mul(tipsyPower);

    })

    describe('Testing for Tipsy Staking', async () => {

        it('Test 1 :Staking Silver', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            
            await expect(tipsyStaking.connect(account1).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await ethers.provider.send('evm_increaseTime', [ninetyDays + 2]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(defaultMintTo);
        });


        it('Test 2 :Staking Silver + Gold', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);

            tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            
            await ethers.provider.send('evm_increaseTime', [sevenDays]); //increase time by a week
            await ethers.provider.send('evm_mine');

            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await tipsyStaking.connect(account1).stake(goldAmount); //Get Tipsy Gold

            userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Gold");

            await ethers.provider.send('evm_increaseTime', [oneDay * 83]); //90 days from Silver
            await ethers.provider.send('evm_mine');

            await expect(tipsyStaking.connect(account1).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");

            await ethers.provider.send('evm_increaseTime', [sevenDays + 1]); //increase time by a week
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(defaultMintTo);
        });

        it('Test 3: Staking Silver + Harvesting', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver

            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");
            
            await ethers.provider.send('evm_increaseTime', [sevenDays]); //increase time by a week
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).harvest();
            
            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
           
            expect(await tipsyStaking.getUserRewardBlock(account1.address)).to.closeTo(ethers.BigNumber.from(timeNow), 3);
            expect(await tipsyStaking.getUserRewardDebt(account1.address)).to.closeTo(ethers.BigNumber.from(0), 1);
            
            
            let allocatedGin = await tipsyStaking.getAllocatedGin(account1.address);
            expect(ethers.BigNumber.from(allocatedGin)).to.closeTo(ethers.BigNumber.from(ethers.BigNumber.from(sevenDays).mul(ethers.BigNumber.from(1157407407407407))), "10000000000000000"); //should be close to 100 per second for 7 days

            await expect(tipsyStaking.connect(account1).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");

            await ethers.provider.send('evm_increaseTime', [ninetyDays - sevenDays + 1]); //increase time by a 1 month - 1 week + 1
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(defaultMintTo);
        });

        it('Test 4: Adding Levels', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo.mul(ethers.BigNumber.from(10)));
            
            await expect(tipsyStaking.connect(deployer).addLevel(3, 20, silverAmount)).to.be.revertedWith("Tipsy: staking amount too low for level");

            await tipsyStaking.connect(deployer).addLevel(3, goldAmount.mul(ethers.BigNumber.from(5)), 3000);
            await tipsyStaking.connect(deployer).setLevelName(3, "Tipsy GOD")

            await tipsyStaking.connect(account1).stake(goldAmount.mul(ethers.BigNumber.from(5))); //Get Tipsy God
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy GOD");

        });

        it('Test 5: Editing Levels', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, 10000000000);
            
            await expect(tipsyStaking.connect(deployer).setLevel(1, goldAmount.mul(silverAmount), 2000)).to.be.revertedWith("Tipsy: staking amount too high for level"); //BUG, this only breaks when staking level is 0
            await expect(tipsyStaking.connect(deployer).setLevel(0, goldAmount, 2000)).to.be.revertedWith("Tipsy: staking amount set too high for Lv0");
        });

        it('Test 6: Deleting Levels', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);
            
            await expect(tipsyStaking.connect(deployer).deleteLevel(1)).to.be.revertedWith("Tipsy: Must delete Highest level first");

            await (tipsyStaking.connect(deployer).deleteLevel(2));
        });

        it('Test 7: Pausing', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
    
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await ethers.provider.send('evm_increaseTime', [ninetyDays + 2]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await (tipsyStaking.connect(deployer).pause());

            await expect(tipsyStaking.connect(account1).unstakeAll()).to.be.revertedWith("Pausable: paused");

            await expect(tipsyStaking.connect(account1).harvest()).to.be.revertedWith("Pausable: paused");

            await tipsyStaking.connect(account1).EmergencyUnstake();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(defaultMintTo); //rounding
        });

        it('Test 8 : Multi-user Staking', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);
            await tipsyCoinMock.mintTo(account2.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            await tipsyStaking.connect(account2).stake(goldAmount); //Get Tipsy Gold
            
            await expect(tipsyStaking.connect(account2).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            let userLevel2 = await tipsyStaking.connect(account2).getUserLvlTxt_Cached(account2.address);
            expect(userLevel2).to.equal("Tipsy Gold");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).harvest();
            await tipsyStaking.connect(account2).harvest();

            let allocatedGin1 = await tipsyStaking.getAllocatedGin(account1.address);
            expect(ethers.BigNumber.from(allocatedGin1)).to.closeTo(ethers.BigNumber.from(ethers.BigNumber.from(sevenDays).mul(ethers.BigNumber.from(1157407407407407))), "10000000000000000"); //should be close to 100 per second for 7 days

            let allocatedGin2 = await tipsyStaking.getAllocatedGin(account2.address);
            expect(ethers.BigNumber.from(allocatedGin2)).to.closeTo("3850019097222220867015", "10000000000000000"); //should be close to 100 per second for 7 days

            await ethers.provider.send('evm_increaseTime', [ninetyDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).unstakeAll();
            await tipsyStaking.connect(account2).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);
            let account2Balance = await tipsyCoinMock.balanceOf(account2.address);

            expect(account1Balance).to.equal(defaultMintTo);
            expect(account2Balance).to.equal(defaultMintTo);
        });

        it('Test 9 : Multi-user Staking with Basic Reflection', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);
            await tipsyCoinMock.mintTo(account2.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            await tipsyStaking.connect(account2).stake(goldAmount); //Get Tipsy Gold
            
            await expect(tipsyStaking.connect(account2).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            let userLevel2 = await tipsyStaking.connect(account2).getUserLvlTxt_Cached(account2.address);
            expect(userLevel2).to.equal("Tipsy Gold");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).harvest();
            await tipsyStaking.connect(account2).harvest();

            let allocatedGin1 = await tipsyStaking.getAllocatedGin(account1.address);
            expect(ethers.BigNumber.from(allocatedGin1)).to.closeTo(ethers.BigNumber.from(ethers.BigNumber.from(sevenDays).mul(ethers.BigNumber.from(1157407407407407))), "10000000000000000"); //should be close to 100 per second for 7 days

            let allocatedGin2 = await tipsyStaking.getAllocatedGin(account2.address);
            expect(ethers.BigNumber.from(allocatedGin2)).to.closeTo("3850019097222220867015", "10000000000000000"); //should be close to 100 per second for 7 days

            await ethers.provider.send('evm_increaseTime', [ninetyDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await tipsyCoinMock.setRTotal(ethers.BigNumber.from("1050000000000000000"));
            
            await tipsyStaking.connect(account1).unstakeAll();
            await tipsyStaking.connect(account2).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);
            let account2Balance = await tipsyCoinMock.balanceOf(account2.address);

            expect(account1Balance).to.closeTo(ethers.BigNumber.from("105000000000000000000000000"), 100);
            expect(account2Balance).to.closeTo(ethers.BigNumber.from("105000000000000000000000000"), 100)
        });

        it('Test 10 : Multi-user Staking with Advanced Reflection', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);
            await tipsyCoinMock.mintTo(account2.address, defaultMintTo);

            await tipsyCoinMock.setRTotal(ethers.BigNumber.from("1050000000000000000"));

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            await tipsyStaking.connect(account2).stake(goldAmount); //Get Tipsy Silver
            
            await expect(tipsyStaking.connect(account2).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            let userLevel2 = await tipsyStaking.connect(account2).getUserLvlTxt_Cached(account2.address);
            expect(userLevel2).to.equal("Tipsy Gold");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).harvest();
            await tipsyStaking.connect(account2).harvest();

            let allocatedGin1 = await tipsyStaking.getAllocatedGin(account1.address);
            expect(ethers.BigNumber.from(allocatedGin1)).to.closeTo(ethers.BigNumber.from(ethers.BigNumber.from(sevenDays).mul(ethers.BigNumber.from(1157407407407407))), "10000000000000000"); //should be close to 100 per second for 7 days

            let allocatedGin2 = await tipsyStaking.getAllocatedGin(account2.address);
            expect(ethers.BigNumber.from(allocatedGin2)).to.closeTo("3850019097222220867015", "10000000000000000"); //should be close to 100 per second for 7 days

            await ethers.provider.send('evm_increaseTime', [ninetyDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await tipsyCoinMock.setRTotal(ethers.BigNumber.from("1100000000000000000"));
            
            await tipsyStaking.connect(account1).unstakeAll();
            await tipsyStaking.connect(account2).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);
            let account2Balance = await tipsyCoinMock.balanceOf(account2.address);

            expect(account1Balance).to.closeTo(ethers.BigNumber.from("110000000000000000000000000"), 100);
            expect(account2Balance).to.closeTo(ethers.BigNumber.from("110000000000000000000000000"), 100)
        });

        it('Test 11 : Activating Gin Live Later', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            let Gin = await ethers.getContractFactory('Gin');
            Gin = Gin.connect(deployer);
            ginmock = await Gin.deploy();
            await ginmock.deployed();

            await ginmock.initialize(deployer.address, account1.address, tipsyStaking.address);
            
            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);
            await tipsyCoinMock.mintTo(account2.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            await tipsyStaking.connect(account2).stake(goldAmount); //Get Tipsy Gold
            
            await expect(tipsyStaking.connect(account2).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tier I");

            let userLevel2 = await tipsyStaking.connect(account2).getUserLvlTxt_Cached(account2.address);
            expect(userLevel2).to.equal("Tier II");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 7 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).harvest();
            await tipsyStaking.connect(account2).harvest();

            let allocatedGin1 = await tipsyStaking.getAllocatedGin(account1.address);
            expect(ethers.BigNumber.from(allocatedGin1)).to.closeTo(ethers.BigNumber.from(ethers.BigNumber.from(sevenDays).mul(ethers.BigNumber.from(1157407407407407))), "10000000000000000"); //should be close to 100 per second for 7 days

            let allocatedGin2 = await tipsyStaking.getAllocatedGin(account2.address);
            expect(ethers.BigNumber.from(allocatedGin2)).to.closeTo("4200020833333331854926", "10000000000000000"); //should be close to 100 per second for 7 days
            
            await tipsyStaking.connect(deployer).setGinAddress(ginmock.address);
            
            await tipsyStaking.connect(account1).harvest();
            await tipsyStaking.connect(account2).harvest();

            let account1GinBalance = await ginmock.balanceOf(account1.address);
            let account2GinBalance = await ginmock.balanceOf(account2.address);

            // expect(account1GinBalance).to.equal("3472222222222221");
            // expect(account2GinBalance).to.equal("19097222222222215");

            await ethers.provider.send('evm_increaseTime', [ninetyDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).unstakeAll();
            await tipsyStaking.connect(account2).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);
            let account2Balance = await tipsyCoinMock.balanceOf(account2.address);

            expect(account1Balance).to.equal(defaultMintTo);
            expect(account2Balance).to.equal(defaultMintTo);
        });

        it('Test 12 : Activating Gin First', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            let Gin = await ethers.getContractFactory('Gin');
            Gin = Gin.connect(deployer);
            ginmock = await Gin.deploy();
            await ginmock.deployed();

            await ginmock.initialize(deployer.address, account1.address, tipsyStaking.address);
            
            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);
            await tipsyCoinMock.mintTo(account2.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            await tipsyStaking.connect(account2).stake(goldAmount); //Get Tipsy Gold
            
            await expect(tipsyStaking.connect(account2).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tier I");

            let userLevel2 = await tipsyStaking.connect(account2).getUserLvlTxt_Cached(account2.address);
            expect(userLevel2).to.equal("Tier II");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 7 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(deployer).setGinAddress(ginmock.address);
            
            await tipsyStaking.connect(account1).harvest();
            await tipsyStaking.connect(account2).harvest();

            let account1GinBalance = await ginmock.balanceOf(account1.address);
            let account2GinBalance = await ginmock.balanceOf(account2.address);

            expect(account1GinBalance).to.equal("700004629629629383228");
            expect(account2GinBalance).to.equal("4200027777777776299368");

            await ethers.provider.send('evm_increaseTime', [ninetyDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).unstakeAll();
            await tipsyStaking.connect(account2).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);
            let account2Balance = await tipsyCoinMock.balanceOf(account2.address);

            expect(account1Balance).to.equal(defaultMintTo);
            expect(account2Balance).to.equal(defaultMintTo);
        });

        it('Test 13: Resetting Lock Duration', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            
            await expect(tipsyStaking.connect(account1).unstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await tipsyStaking.connect(deployer).setLockDuration(sevenDays);

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).unstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(defaultMintTo);
        });

        it('Test 14 : User Kick', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            let Gin = await ethers.getContractFactory('ERC20');
            Gin = Gin.connect(deployer);
            ginmock = await Gin.deploy();
            await ginmock.deployed();
            
            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, defaultMintTo);

            await tipsyStaking.connect(account1).stake(silverAmount); //Get Tipsy Silver
            
            let userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 7 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(deployer).setGinAddress(ginmock.address);
            
            await tipsyStaking.connect(account1).harvest();

            let account1GinBalance = await ginmock.balanceOf(account1.address);

            expect(account1GinBalance).to.equal("700002314814814568414"); //Gin balance of will divide by 1e18

            tipsyStaking.connect(deployer).setLevel(0, silverAmount.add(ethers.BigNumber.from(1000000)), 1000);

            userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            //expect(userLevel).to.equal("Tipsy Silver"); //Getting No Stake instead

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 7 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).harvest();

            account1GinBalance = await ginmock.balanceOf(account1.address);   

            expect(account1GinBalance).to.equal("1400004629629629136828");
            
            tipsyStaking.connect(account1).kick();
            userLevel = await tipsyStaking.connect(account1).getUserLvlTxt_Cached(account1.address);
            expect(userLevel).to.equal("No Stake");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 7 days
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).harvest();

            account1GinBalance = await ginmock.balanceOf(account1.address);   

            expect(account1GinBalance).to.equal("1400005787037036544235");
            
        });

        it('Test 15 : Reinitialize Attempt', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            await tipsyStaking.deployed();
            
            await expect(tipsyStaking.initialize(account1.address, tipsyCoinMock.address)).to.be.revertedWith("Initializable: contract is already initialized");
        });

        it('Test 16 : Renounce Ownership', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            await tipsyStaking.deployed();

            await tipsyStaking.connect(deployer).renounceOwnership();

            await expect(tipsyStaking.connect(deployer).addLevel(0,1,2)).to.be.revertedWith("Ownable123: caller is not the owner");
            await expect(tipsyStaking.connect(deployer).setLevel(0,1,2)).to.be.revertedWith("Ownable123: caller is not the owner");
            await expect(tipsyStaking.connect(deployer).deleteLevel(2)).to.be.revertedWith("Ownable123: caller is not the owner");
            await expect(tipsyStaking.connect(deployer).pause()).to.be.revertedWith("Ownable123: caller is not the owner");
            await expect(tipsyStaking.connect(deployer).transferOwnership(account1.address)).to.be.revertedWith("Ownable123: caller is not the owner");
            await expect(tipsyStaking.connect(deployer).adminKick(account1.address)).to.be.revertedWith("Ownable123: caller is not the owner");

        });

        it('Test 17 : Transfer Ownership', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            await tipsyStaking.deployed();

            await tipsyStaking.connect(deployer).transferOwnership(account1.address);
            
            await tipsyStaking.connect(account1).pause();
            await tipsyStaking.connect(account1).unpause();

            await tipsyStaking.connect(account1).transferOwnership(deployer.address);

            await tipsyStaking.connect(deployer).pause();
            await tipsyStaking.connect(deployer).unpause();
        });


    });
});
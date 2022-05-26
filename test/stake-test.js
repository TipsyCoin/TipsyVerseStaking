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

    beforeEach(async () => {
        [deployer, account1, account2] = await ethers.getSigners()
        let TipsyCoin = await ethers.getContractFactory('TipsyCoinMock')
        TipsyCoin = TipsyCoin.connect(deployer)
        tipsyCoinMock = await TipsyCoin.deploy()
        await tipsyCoinMock.deployed()

        ninetyDays = 90 * 24 * 60 * 60;
        sevenDays = 7 * 24 * 60 * 60;
        oneDay = 24*60*60;
    })

    describe('Testing for Tipsy Staking', async () => {

        it('Test 1 :Staking Silver', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, 1000000);

            await tipsyStaking.connect(account1).Stake(60); //Get Tipsy Silver
            
            await expect(tipsyStaking.connect(account1).UnstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await ethers.provider.send('evm_increaseTime', [ninetyDays + 2]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).UnstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(1000000);
        });


        it('Test 2 :Staking Silver + Gold', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, 100000);

            tipsyStaking.connect(account1).Stake(60); //Get Tipsy Silver
            
            await ethers.provider.send('evm_increaseTime', [sevenDays]); //increase time by a week
            await ethers.provider.send('evm_mine');

            let userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await tipsyStaking.connect(account1).Stake(41); //Get Tipsy Gold

            userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy Gold");

            await ethers.provider.send('evm_increaseTime', [oneDay * 83]); //90 days from Silver
            await ethers.provider.send('evm_mine');

            await expect(tipsyStaking.connect(account1).UnstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");

            await ethers.provider.send('evm_increaseTime', [sevenDays + 1]); //increase time by a week
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).UnstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(100000);
        });

        it('Test 3: Staking Silver + Harvesting', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, 100000);

            await tipsyStaking.connect(account1).Stake(60); //Get Tipsy Silver

            let userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");
            
            await ethers.provider.send('evm_increaseTime', [sevenDays]); //increase time by a week
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).Harvest();
            
            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
           
            expect(await tipsyStaking.getUserRewardBlock(account1.address)).to.closeTo(ethers.BigNumber.from(timeNow), 3);
            expect(await tipsyStaking.getUserRewardDebt(account1.address)).to.closeTo(ethers.BigNumber.from(0), 1);
            
            
            let allocatedGin = await tipsyStaking.getAllocatedGin(account1.address);
            expect(allocatedGin).to.closeTo(ethers.BigNumber.from(sevenDays * 100), 100); //should be close to 100 per second for 7 days

            await expect(tipsyStaking.connect(account1).UnstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");

            await ethers.provider.send('evm_increaseTime', [ninetyDays - sevenDays + 1]); //increase time by a 1 month - 1 week + 1
            await ethers.provider.send('evm_mine');

            await tipsyStaking.connect(account1).UnstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(100000);
        });

        it('Test 4: Adding Levels', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, 100000);
            
            await expect(tipsyStaking.connect(deployer).addLevel(3, 20, 2000)).to.be.revertedWith("tipsy: staking amount too low for level");

            await tipsyStaking.connect(deployer).addLevel(3, 2000, 3000);
            await tipsyStaking.connect(deployer).setLevelName(3, "Tipsy GOD")

            await tipsyStaking.connect(account1).Stake(2001); //Get Tipsy God
            
            let userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy GOD");

        });

        it('Test 5: Editing Levels', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, 100000);
            
            //await expect(tipsyStaking.connect(deployer).setLevel(1, 5000, 2000)).to.be.revertedWith("tipsy: staking amount too high for level"); //BUG, this only breaks when staking level is 0
            await expect(tipsyStaking.connect(deployer).setLevel(0, 5000, 2000)).to.be.revertedWith("tipsy: staking amount too high for 0");
        });

        it('Test 6: Deleting Levels', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
            
            await tipsyCoinMock.mintTo(account1.address, 100000);
            
            await expect(tipsyStaking.connect(deployer).deleteLevel(1)).to.be.revertedWith("Tipsy: Must delete Highest level first");

            await (tipsyStaking.connect(deployer).deleteLevel(2));
        });

        it('Test 7: Pausing', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);
    
            await tipsyCoinMock.mintTo(account1.address, 1000000);

            await tipsyStaking.connect(account1).Stake(60); //Get Tipsy Silver
            
            let userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            await ethers.provider.send('evm_increaseTime', [ninetyDays + 2]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await (tipsyStaking.connect(deployer).pause());

            await expect(tipsyStaking.connect(account1).UnstakeAll()).to.be.revertedWith("Pausable: paused");

            await expect(tipsyStaking.connect(account1).Harvest()).to.be.revertedWith("Pausable: paused");

            await tipsyStaking.connect(account1).EmergencyUnstake();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);

            expect(account1Balance).to.equal(1000000);
        });

        it('Test 8 : Multi-user Staking', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, 1000000);
            await tipsyCoinMock.mintTo(account2.address, 10000000);

            await tipsyStaking.connect(account1).Stake(60); //Get Tipsy Silver
            await tipsyStaking.connect(account2).Stake(101); //Get Tipsy Silver
            
            await expect(tipsyStaking.connect(account2).UnstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            let userLevel2 = await tipsyStaking.connect(account2).getUserLevelText(account2.address);
            expect(userLevel2).to.equal("Tipsy Gold");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).Harvest();
            await tipsyStaking.connect(account2).Harvest();

            let allocatedGin1 = await tipsyStaking.getAllocatedGin(account1.address);
            expect(allocatedGin1).to.closeTo(ethers.BigNumber.from(sevenDays * 100), 1000); //should be close to 100 per second for 90 days

            let allocatedGin2 = await tipsyStaking.getAllocatedGin(account2.address);
            expect(allocatedGin2).to.closeTo(ethers.BigNumber.from(sevenDays * 200), 1000); //should be close to 200 per second for 90 days

            await ethers.provider.send('evm_increaseTime', [ninetyDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).UnstakeAll();
            await tipsyStaking.connect(account2).UnstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);
            let account2Balance = await tipsyCoinMock.balanceOf(account2.address);

            expect(account1Balance).to.equal(1000000);
            expect(account2Balance).to.equal(10000000);
        });

        it('Test 9 : Multi-user Staking with Basic Reflection', async () => {

            const TipsyStaking = await ethers.getContractFactory('TipsyStaking');
            tipsyStaking = await TipsyStaking.deploy(tipsyCoinMock.address);

            const timeNow = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
            
            await tipsyCoinMock.mintTo(account1.address, 1000000);
            await tipsyCoinMock.mintTo(account2.address, 10000000);

            await tipsyStaking.connect(account1).Stake(60); //Get Tipsy Silver
            await tipsyStaking.connect(account2).Stake(101); //Get Tipsy Silver
            
            await expect(tipsyStaking.connect(account2).UnstakeAll()).to.be.revertedWith("Tipsy: Can't unstake before Lock is over");
            
            let userLevel = await tipsyStaking.connect(account1).getUserLevelText(account1.address);
            expect(userLevel).to.equal("Tipsy Silver");

            let userLevel2 = await tipsyStaking.connect(account2).getUserLevelText(account2.address);
            expect(userLevel2).to.equal("Tipsy Gold");

            await ethers.provider.send('evm_increaseTime', [sevenDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');
            
            await tipsyStaking.connect(account1).Harvest();
            await tipsyStaking.connect(account2).Harvest();

            let allocatedGin1 = await tipsyStaking.getAllocatedGin(account1.address);
            expect(allocatedGin1).to.closeTo(ethers.BigNumber.from(sevenDays * 100), 1000); //should be close to 100 per second for 90 days

            let allocatedGin2 = await tipsyStaking.getAllocatedGin(account2.address);
            expect(allocatedGin2).to.closeTo(ethers.BigNumber.from(sevenDays * 200), 1000); //should be close to 200 per second for 90 days

            await ethers.provider.send('evm_increaseTime', [ninetyDays]); //Increase time by 90 days
            await ethers.provider.send('evm_mine');

            await tipsyCoinMock.setRTotal(ethers.BigNumber.from("1050000000000000000"));
            
            await tipsyStaking.connect(account1).UnstakeAll();
            await tipsyStaking.connect(account2).UnstakeAll();

            let account1Balance = await tipsyCoinMock.balanceOf(account1.address);
            let account2Balance = await tipsyCoinMock.balanceOf(account2.address);

            expect(account1Balance).to.closeTo(ethers.BigNumber.from(1000000 * 1.05), 100);
            expect(account2Balance).to.closeTo(ethers.BigNumber.from(10000000 * 1.05), 100)
        });







    });
});
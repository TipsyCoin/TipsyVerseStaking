# TipsyCoin

Solidity contracts and Hardhat tests for TipsyCoin's staking feature

## Introduction
TipsyCoin is a Safemoon style token (with a number of design changes) used as the governance token for the TipsyVerse game and ecosystem. The code for this token is available here: https://github.com/TipsyCoin/TipsyCoin . TipsyCoin launched on PCS in March 2022, and was audited by CertiK.

TipsyCoin staking (TipsyStake) is the next step towards the release of the TipsyVerse blockchain integrated Minecraft game. TipsyStake allows users to stake their TipsyCoin for a period of 90 days and farm Gin, the in game currency in TipsyVerse, that players can use for things like buying in-game items.

Users staking TipsyCoin will also receive a discount for in-game items based on their staking tier, and may also be integrated with upcoming projects in the TipsyVerse ecosystem.

## Contract Address
- Mainnet: bscscan.com/address/0xAd1C1A04bB050530c2511d4113b81eD7396E3Fb3
- Testnet: bscscan.com/address/0xba09486a76319dd97742700da784d3f25402fcdd 

## Design notes
- The TipsyVerse Minecraft game is to be released on the Polygon network, but the tokenomic design and BSC -> Polygon bridge design have not yet been finalized, so there is a period of time where Gin rewards will be tracked on TipsyStake, but cannot be collected or bridged to Polygon.

- TipsyStake has functionality included in the harvest() function where once the BSC -> Polygon Gin bridge is ready, the contract can be switched over from internal tracking and allocation of Gin, to minting of Gin with a single function call, setGinAddress().

- TipsyCoin uses token reflection on sells to increase user token balances over time. TipsyStake has been designed to ensure that when users Unstake, their reflected tokens are also unstaked and distributed back to them. As an example, a user might Stake 100 Tipsy, collect Gin for 3 months, and then be able to Unstake 110 Tipsy, because the reflection factor has increased by 10%.

- TipsyStake uses staking tiers, and sets the staking tier in reflection space, as this is how the TipsyCoin.balanceOf() returns. This means a 100 Tipsy minimum stake (balanceOf() == 100 Tipsy) might be 90 real space tokens now, but in 3 months, balanceOf() == 100 Tipsy may be 80 real space tokens. Random +1's in the code are usually to try and prevent rounding errors when doing conversions like this.

- TipsyStake will use The Transparent Upgradable Proxy pattern (@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol). Proxies are used so additional features can be added, bugfixes applied, or integration of contracts into other parts of the Tipsy ecosystem can be preformed.

- As with TipsyCoin, based on feedback from CertiK, privileged proxy admin access will be done through a governance timelock via a Gnosis safe multi-sig to ensure the risks of using Proxy based contract patterns are minimized. More details on how proxies are handled can be found on the TipsyCoin github, or in the CertiK audit (copy also included in TipsyCoin github).

- The proxy contract used is on the main TipsyCoin github (https://github.com/TipsyCoin/TipsyCoin/blob/main/contracts/UpgradeableProxy.sol)

- The governance timelock to be used is also on the main TipsyCoin gitub (https://github.com/TipsyCoin/TipsyCoin/blob/main/contracts/TimelockController.sol)

- The governance timelock is the proxy contract Admin, and a gnosis safe multisig owns the governance timelock.

- Critique of our usage or implementation of the proxy / governance timelock is appreciated, but the code for those contracts is not within the scope of the audit.

- Because TipsyStaking is to be integrated further into our ecosystem over time, the contract may have more public views than typical, and has a couple of unused functions / variables which may not be currently used. This, by itself, should not be considered a bug, unless the usage is clearly unintentional or dangerous.

- The staking 'text' and values are also important, because we plan to reflect the user's tier ingame, as well as offer discounts, based on a user's staking tier. 


## Staking Rules

- Users receive Gin rewards based on their staking 'tier' of TipsyCoin. For example, the Tipsy Silver tier requires a stake of 10e6 Tipsy, and rewards ~100 Gin per day.

- Rewards are not linear like many other staking platforms. This means 100 Gin is rewarded for Tipsy Silver regardless of whether a user stakes 10e6 Tipsy or 20e6. Front end integration will be used to help users stake only the minimum amount they require to reach a particular tier

- Rewards are not split between all staked users. Instead, each user receives the amount of Gin listed below, regardless of how many other users stake.

- Tipsy Silver (10e6 Tipsy staked): ~100 Gin per day. This is considered the 1x Gin rate
- Tipsy Gold (50e6 Tipsy staked): ~550 Gin per day
- Tipsy Platinum (100e6 Tipsy staked): ~1200 Gin per day

- The 90 day lock duration is enforced based on the last time a user Staked TipsyCoin. This means a user increasing their TipsyCoin stake has the lock duration refreshed

- All tokens (plus reflection rewards) are unstaked when calling the Unstake function. Partial Unstakes are not allowed (and have been removed entirely in the latest version of the code).

- Unstaking does not refresh the lock duration

- A User's tier and that tier's Gin multiplier are 'locked in' when a user Stakes. This means a future change to a particular tier, for example, increasing the staking requirement from 10e6 Tipsy to 20e6, would not update the user's tier and multiplier. This allows to keep their current tier of Gin distribution and in-game discounts if they don’t stake or unstake, even if we adjust the tiers.

- A 'Kick' function exists for users to manually sync their Staking tier if they would find it beneficial

- An emergency pause function exists so we can halt the contract if we need to upgrade it to fix bugs or add features

- An admin 'Kick' function also exists, and can be used to kick any user while the contract is paused

- Users may emergency withdraw without harvesting, if the contract has been paused


## Contract list
### TipsyCoin.sol 
The main contract, contains all staking functionality. Requires a TipsyCoin address during initialization().

### TipsyCoinMock.sol
Not part of the audit. It provides basic and non permissioned TipsyCoin and Gin functionality to help test reflection factors and test mints. Minting to anyone is allowed, as are transferFrom's without approval.

# Advanced Sample Hardhat Project

This project demonstrates an advanced Hardhat use case, integrating other tools commonly used alongside Hardhat in the ecosystem.

The project comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts. It also comes with a variety of other tools, preconfigured to work with the project code.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat help
REPORT_GAS=true npx hardhat test
npx hardhat coverage
npx hardhat run scripts/deploy.js
node scripts/deploy.js
npx eslint '**/*.js'
npx eslint '**/*.js' --fix
npx prettier '**/*.{json,sol,md}' --check
npx prettier '**/*.{json,sol,md}' --write
npx solhint 'contracts/**/*.sol'
npx solhint 'contracts/**/*.sol' --fix
```

# Etherscan verification

To try out Etherscan verification, you first need to deploy a contract to an Ethereum network that's supported by Etherscan, such as Ropsten.

In this project, copy the .env.example file to a file named .env, and then edit it to fill in the details. Enter your Etherscan API key, your Ropsten node URL (eg from Alchemy), and the private key of the account which will send the deployment transaction. With a valid .env file in place, first deploy your contract:

```shell
hardhat run --network ropsten scripts/deploy.js
```

Then, copy the deployment address and paste it in to replace `DEPLOYED_CONTRACT_ADDRESS` in this command:

```shell
npx hardhat verify --network ropsten DEPLOYED_CONTRACT_ADDRESS "Hello, Hardhat!"
```

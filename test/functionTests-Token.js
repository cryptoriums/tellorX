const { AbiCoder } = require("@ethersproject/abi");
const { expect } = require("chai");
const h = require("./helpers/helpers");
var assert = require('assert');
const web3 = require('web3');
const fetch = require('node-fetch')

describe("TellorX Function Tests - Token", function() {

    const tellorMaster = "0x88dF592F8eb5D7Bd38bFeF7dEb0fBc02cf3778a0"
    const DEV_WALLET = "0x39E419bA25196794B595B2a595Ea8E527ddC9856"
    const BIGWALLET = "0xf977814e90da44bfa03b6295a0616a897441acec";
    let accounts = null
    let tellor = null
    let cfac,ofac,tfac,gfac,devWallet
    let govSigner = null
    let run = 0;
    let mainnetBlock = 0;

  beforeEach("deploy and setup TellorX", async function() {
    this.timeout(20000000)
    if(run == 0){
      const directors = await fetch('https://api.blockcypher.com/v1/eth/main').then(response => response.json());
      mainnetBlock = directors.height - 20;
      console.log("     Forking from block: ",mainnetBlock)
      run = 1;
    }
    accounts = await ethers.getSigners();
    await hre.network.provider.request({
      method: "hardhat_reset",
      params: [{forking: {
            jsonRpcUrl: hre.config.networks.hardhat.forking.url,
            blockNumber: mainnetBlock
          },},],
      });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [DEV_WALLET]}
    )
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [BIGWALLET]}
    )
        //Steps to Deploy:
        //Deploy Governance, Oracle, Treasury, and Controller.
        //Fork mainnet Ethereum, changeTellorContract to Controller
        //run init in Controller

    oldTellorInstance = await ethers.getContractAt("contracts/tellor3/ITellor.sol:ITellor", tellorMaster)
    gfac = await ethers.getContractFactory("contracts/testing/TestGovernance.sol:TestGovernance");
    ofac = await ethers.getContractFactory("contracts/Oracle.sol:Oracle");
    tfac = await ethers.getContractFactory("contracts/Treasury.sol:Treasury");
    cfac = await ethers.getContractFactory("contracts/testing/TestController.sol:TestController");
    governance = await gfac.deploy();
    oracle = await ofac.deploy();
    treasury = await tfac.deploy();
    controller = await cfac.deploy(governance.address, oracle.address, treasury.address);
    await governance.deployed();
    await oracle.deployed();
    await treasury.deployed();
    await controller.deployed();
    await accounts[0].sendTransaction({to:DEV_WALLET,value:ethers.utils.parseEther("1.0")});
    devWallet = await ethers.provider.getSigner(DEV_WALLET);
    const bigWallet = await ethers.provider.getSigner(BIGWALLET);
    master = await oldTellorInstance.connect(devWallet)
    await master.proposeFork(controller.address);
    let _id = await master.getUintVar(h.hash("_DISPUTE_COUNT"))
    await master.vote(_id,true)
    master = await oldTellorInstance.connect(bigWallet)
    await master.vote(_id,true);
    await h.advanceTime(86400 * 8)
    await master.tallyVotes(_id)
    await h.advanceTime(86400 * 2.5)
    await master.updateTellor(_id)
    tellor = await ethers.getContractAt("contracts/interfaces/ITellor.sol:ITellor",tellorMaster, devWallet);
    await tellor.deployed();
    await tellor.init()
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [governance.address]}
    )
    await accounts[1].sendTransaction({to:governance.address,value:ethers.utils.parseEther("1.0")});
    govSigner = await ethers.provider.getSigner(governance.address);
  });

	  it("approve and allowance", async function() {
      this.timeout(20000000)
		  //create user account, mint it tokens
		  let acc = await ethers.getSigner()
		  await tellor.connect(devWallet).transfer(acc.address, BigInt(5E20))

		  //approve dev wallet to spend for the user
		  await tellor.connect(acc).approve(DEV_WALLET, BigInt(2E20))

		  //check allowances
		  let allowance = BigInt(await tellor.allowance(acc.address, DEV_WALLET))
		  expect(allowance).to.equal(BigInt(2E20))
	  })

	  it("allowed to trade", async function() {
		  let mintedTokens = BigInt(101E18)
		  let stake = BigInt(100E18)
		  //create user account, mint it tokens
		  let acc = await ethers.getSigner()
		  await tellor.connect(devWallet).transfer(acc.address, mintedTokens)

		  //if not staked, returns true if balance >= amount
		  let allowedToTrade = await tellor.allowedToTrade(acc.address, BigInt(40E18))
		  expect(allowedToTrade).to.be.true

		  //stake the user
		  await tellor.connect(acc).depositStake()

		  //returns false if amount > (total balance - stake)
		  allowedToTrade = await tellor.allowedToTrade(acc.address, BigInt(2E18))
		  expect(allowedToTrade).to.be.false

		  //returns true if amount <= (total balance - stake)
		  allowedToTrade = await tellor.allowedToTrade(acc.address, BigInt(1E18))
		  expect(allowedToTrade).to.be.true
	  })

	  it("balance of", async function() {
		  let mintedTokens = BigInt(2E18)

		  //create user, mint it tokens
		  let acc = await ethers.getSigner()
		  await tellor.connect(devWallet).transfer(acc.address, mintedTokens)

		  //check balance is same as minted amount
		  let balance = await tellor.balanceOf(acc.address)
		  expect(balance).to.equal(mintedTokens)
	  })

	  it("balance of at", async function() {
		  //an account with a balance
		  let userAddress = "0xA97cd82A05386eAdaFCE2bbD2e6a0CbBa7A53a6c"
		  let blockNumber = 12500000 // may 24 2021
		  //expect balance has been ~1.537 TRB
		  expect(
			Math.floor(Number(await tellor.balanceOfAt(userAddress, blockNumber))/1E15)
		).to.be.approximately(
			1537,
			0.5,
			"balance recorded improperly")
	  })

	  it("burn", async function() {
		  //an account with a balance
		  let mintedTokens = BigInt(2E18)
		  let burnedTokens = BigInt(1E18)
		  let acc = await ethers.getSigner()
		  await tellor.connect(devWallet).transfer(acc.address, mintedTokens)

		  //burn some of the balance
		  await tellor.connect(acc).burn(burnedTokens)

		  //expect balance has decreased by amount burned
		  balance = await tellor.balanceOf(acc.address)
		  expect(balance).to.equal(mintedTokens - burnedTokens)

	  })

	  it("transfer", async function() {
		  //two accounts
		  let [acc1, acc2] = await ethers.getSigners()
		  await tellor.connect(devWallet).transfer(acc1.address, BigInt(5E18))

		  //transfer an amount to second account
		  await tellor.connect(acc1).transfer(acc2.address, BigInt(3E18))

		  //expect second account's balance to be transferred amount
		  let balance = await tellor.balanceOf(acc2.address)
		  expect(balance).to.equal(BigInt(3E18))

		  //expect first account's balance to be original balance - transferred amount
		  balance = await tellor.balanceOf(acc1.address)
		  expect(balance).to.equal(BigInt(2E18))

	  })

	  it("transfer from", async function() {
		  //mint an account tokens
		  let [acc1, acc2] = await ethers.getSigners()
		  let mintedTokens = BigInt(502E18)
		  await tellor.connect(devWallet).transfer(acc1.address, mintedTokens)
		  //expect sender can't transfer funds for another use without permission
		  await expect(tellor.connect(acc1).transferFrom(acc2.address, acc1.address, 1)).to.be.reverted
		  //stake account
		  await tellor.connect(acc1).depositStake()
		  //expect successful transfer decreases _from balance by _amount
		  await tellor.connect(acc1).approve(acc2.address, BigInt(4E18))
		  let balance = await tellor.balanceOf(acc1.address)
		  expect(balance).to.equal(mintedTokens)
		  await tellor.connect(acc2).transferFrom(acc1.address, acc2.address,BigInt(4E18))
		  //expect successful transfer increases _to balance by _amount
		  balance = await tellor.balanceOf(acc2.address)
		  expect(balance).to.equal(BigInt(4E18))

	  })
})

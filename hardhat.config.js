/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 require("@nomiclabs/hardhat-waffle");
 
require("@nomiclabs/hardhat-truffle5");
require("hardhat-gas-reporter");
require('hardhat-contract-sizer');
require("solidity-coverage");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("dotenv").config();
require("@nomiclabs/hardhat-web3");

//Run this commands to deploy tellor playground:
//npx hardhat deploy --name "tellor" --symbol "TRB" --net rinkeby --network rinkeby
//npx hardhat deploy --name "tellor" --symbol "TRB" --net mainnet --network mainnet


task("deploy", "Deploy and verify the contracts")
  .addParam("name", "coin name")
  .addParam("symbol", "coin symbol")
  .addParam("net", "network to deploy in")
  .setAction(async taskArgs => {


    console.log("deploy tellor playground with access")
    var name = taskArgs.name
    var symbol = taskArgs.symbol
    var net = taskArgs.network

    await run("compile");

    
    const tellorMaster = "0x88dF592F8eb5D7Bd38bFeF7dEb0fBc02cf3778a0"
    const DEV_WALLET = "0x39E419bA25196794B595B2a595Ea8E527ddC9856"
    let accounts = null
    let tellor = null
    let cfac,ofac,tfac,gfac
    let govSigner = null
    

oldTellorInstance = await ethers.getContractAt("contracts/interfaces/ITellor.sol:ITellor", tellorMaster)

    gfac = await ethers.getContractFactory("contracts/testing/TestGovernance.sol:TestGovernance")
governance = await gfac.deploy()
await governance.deployed()

    if (net == "mainnet"){
        console.log(“Governance contract deployed to:", "https://etherscan.io/address/" + tellor.address);
        console.log("   Governance transaction hash:", "https://etherscan.io/tx/" + governance.deployTransaction.hash);
    } else if (net == "rinkeby") {
        console.log("Governance contract deployed to:", "https://rinkeby.etherscan.io/address/" + governance.address);
        console.log("    Governance transaction hash:", "https://rinkeby.etherscan.io/tx/" + governance.deployTransaction.hash);
    } else {
        console.log("Please add network explorer details")
    }

    // Wait for few confirmed transactions.
    // Otherwise the etherscan api doesn't find the deployed contract.
    console.log('waiting for governance tx confirmation...');
    await tellor.deployTransaction.wait(3)

    console.log('submitting governance contract for verification...');

    await run("verify:verify", {
      address: governance.address,
      //constructorArguments: [name, symbol]
    },
    )

    console.log("governance contract verified")



    ofac = await ethers.getContractFactory("contracts/Oracle.sol:Oracle")
    oracle = await ofac.deploy()
await oracle.deployed();


    if (net == "mainnet"){
        console.log("oracle contract deployed to:", "https://etherscan.io/address/" + oracle.address);
        console.log("    oracle transaction hash:", "https://etherscan.io/tx/" + oracle.deployTransaction.hash);
    } else if (net == "rinkeby") {
        console.log("oracle contract deployed to:", "https://rinkeby.etherscan.io/address/" + oracle.address);
        console.log("    oracle transaction hash:", "https://rinkeby.etherscan.io/tx/" + oracle.deployTransaction.hash);
    } else {
        console.log("Please add network explorer details")
    }

    // Wait for few confirmed transactions.
    // Otherwise the etherscan api doesn't find the deployed contract.
    console.log('waiting for oracle tx confirmation...');
    await oracle.deployTransaction.wait(3)

    console.log('submitting oracle contract for verification...');

    await run("verify:verify", {
      address: oracle.address,
      //constructorArguments: [name, symbol]
    },
    )

    console.log("oracle contract verified")


    tfac = await ethers.getContractFactory("contracts/Treasury.sol:Treasury")
    treasury = await tfac.deploy()
    await treasury.deployed()

    if (net == "mainnet"){
        console.log("treasury contract deployed to:", "https://etherscan.io/address/" + tellor.address);
        console.log("    treasury transaction hash:", "https://etherscan.io/tx/" + treasury.deployTransaction.hash);
    } else if (net == "rinkeby") {
        console.log("treasury contract deployed to:", "https://rinkeby.etherscan.io/address/" + treasury.address);
        console.log("    treasury transaction hash:", "https://rinkeby.etherscan.io/tx/" + treasury.deployTransaction.hash);
    } else {
        console.log("Please add network explorer details")
    }

    // Wait for few confirmed transactions.
    // Otherwise the etherscan api doesn't find the deployed contract.
    console.log('waiting for treasury tx confirmation...');
    await treasury.deployTransaction.wait(3)

    console.log('submitting treasury contract for verification...');

    await run("verify:verify", {
      address: treasury.address,
      //constructorArguments: [name, symbol]
    },
    )

    console.log("treasury Contract verified")

_________________________________________

    cfac = await ethers.getContractFactory("contracts/testing/TestController.sol:TestController")
    controller = await cfac.deploy()
    await controller.deployed()

    if (net == "mainnet"){
        console.log("Tellor contract deployed to:", "https://etherscan.io/address/" + tellor.address);
        console.log("    transaction hash:", "https://etherscan.io/tx/" + tellor.deployTransaction.hash);
    } else if (net == "rinkeby") {
        console.log("Tellor contract deployed to:", "https://rinkeby.etherscan.io/address/" + tellor.address);
        console.log("    transaction hash:", "https://rinkeby.etherscan.io/tx/" + tellor.deployTransaction.hash);
    } else {
        console.log("Please add network explorer details")
    }

    // Wait for few confirmed transactions.
    // Otherwise the etherscan api doesn't find the deployed contract.
    console.log('waiting for tx confirmation...');
    await tellor.deployTransaction.wait(3)

    console.log('submitting contract for verification...');

    await run("verify:verify", {
      address: tellor.address,
      constructorArguments: [name, symbol]
    },
    )

    console.log("Contract verified")


    
    
    
    
    

    const devWallet = await ethers.provider.getSigner(DEV_WALLET);
    master = await oldTellorInstance.connect(devWallet)
    await master.changeTellorContract(controller.address);
    tellor = await ethers.getContractAt("contracts/interfaces/ITellor.sol:ITellor",tellorMaster, devWallet);
    await tellor.deployed();
    await tellor.init(governance.address,oracle.address,treasury.address)





















  });

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.3",
        settings: {
          optimizer: {
            enabled: true,
            runs: 300
          }
        }
      },
      {
        version: "0.7.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 300
          }
        }
      }
    ]
  },
  networks: {
    hardhat: {
      accounts: {
        mnemonic:
          "nick lucian brenda kevin sam fiscal patch fly damp ocean produce wish",
        count: 40,
      },
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/7dW8KCqWwKa1vdaitq-SxmKfxWZ4yPG6"
      },
      allowUnlimitedContractSize: true
    }
  }
}

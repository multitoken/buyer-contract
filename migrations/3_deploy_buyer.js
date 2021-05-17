const Buyer = artifacts.require('Buyer')

module.exports = async function (deployer, network, accounts) {
  if (network === 'kovan' || network === 'kovan-fork') {
    weth = '0xd0A1E359811322d97991E03f863a0C30C2cF029C';
    pancakeRouterMock = '0x32e0b57758Da892dC2389241902923fEA6d990f6'
    await deployer.deploy(Buyer, weth, pancakeRouterMock);
  }
}

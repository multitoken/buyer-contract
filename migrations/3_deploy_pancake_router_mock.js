const PancakeRouterMock = artifacts.require('PancakeRouterMock')

module.exports = async function (deployer, network, accounts) {
  if (network === 'kovan' || network === 'kovan-fork') {
    weth = '0xd0A1E359811322d97991E03f863a0C30C2cF029C';
    await deployer.deploy(PancakeRouterMock, weth);
  }
}

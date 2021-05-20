const Buyer = artifacts.require('Buyer')
const PancakeRouterMock = artifacts.require('PancakeRouterMock')

module.exports = async function (deployer, network, accounts) {
  if (network === 'kovan' || network === 'kovan-fork') {
    await deployer.deploy(Buyer, PancakeRouterMock.address);
  }
}

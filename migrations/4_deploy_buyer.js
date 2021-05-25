const Buyer = artifacts.require('Buyer')
const PancakeRouterMock = artifacts.require('PancakeRouterMock')

module.exports = async function (deployer, network, accounts) {
  if (network === 'kovan' || network === 'kovan-fork') {
    // await deployer.deploy(Buyer, PancakeRouterMock.address);
    const uniswap = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'
    await deployer.deploy(Buyer, uniswap);
  }
}

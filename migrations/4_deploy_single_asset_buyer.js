const SingleAssetBuyer = artifacts.require('SingleAssetBuyer')
const PancakeRouterMock = artifacts.require('PancakeRouterMock')

module.exports = async function (deployer, network, accounts) {
  if (network === 'kovan' || network === 'kovan-fork') {
    // await deployer.deploy(SingleAssetBuyer, PancakeRouterMock.address);
    const uniswap = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'
    await deployer.deploy(SingleAssetBuyer, uniswap);
  }
}

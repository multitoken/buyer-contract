const RightsManager = artifacts.require('RightsManager')
const SmartPoolManager = artifacts.require('SmartPoolManager')
const CRPFactory = artifacts.require('CRPFactory')
const BFactory = artifacts.require('BFactory')
const BalancerSafeMath = artifacts.require('BalancerSafeMath')
const BalancerSafeMathMock = artifacts.require('BalancerSafeMathMock')
const TMath = artifacts.require('TMath')
const Weth9 = artifacts.require('WETH9')
const PancakeRouterMock = artifacts.require('PancakeRouterMock')
const Buyer = artifacts.require('Buyer')

module.exports = async function (deployer, network, accounts) {
  if (network === 'development' || network === 'coverage') {
    await deployer.deploy(Weth9)
    await deployer.deploy(PancakeRouterMock, Weth9.address)
    await deployer.deploy(Buyer, Weth9.address, PancakeRouterMock.address)
    
    await deployer.deploy(TMath)
    await deployer.deploy(BFactory)
    await deployer.deploy(BalancerSafeMathMock)

    await deployer.deploy(BalancerSafeMath)
    await deployer.deploy(RightsManager)
    await deployer.deploy(SmartPoolManager)

    deployer.link(BalancerSafeMath, CRPFactory)
    deployer.link(RightsManager, CRPFactory)
    deployer.link(SmartPoolManager, CRPFactory)

    await deployer.deploy(CRPFactory)
  }
}

const truffleAssert = require('truffle-assertions')
const BFactory = artifacts.require('BFactory')
const CRPFactory = artifacts.require('CRPFactory')
const Exchanger = artifacts.require('PancakeRouterMock')
const TToken = artifacts.require('TToken')
const Weth9 = artifacts.require('WETH9')
const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool')
const Buyer = artifacts.require('Buyer')

contract('Buyer', async (accounts) => {
  const { toWei } = web3.utils
  const { fromWei } = web3.utils
  const admin = accounts[0]
  const user1 = accounts[1]
  const user2 = accounts[2]
  const tokens = [] // {token, weight, balance}
  const MAX_TOKENS = 20
  const DEFAULT_SWAP_FEE = '1500000000000000'
  let weth9
  let bFactory
  let smartPoolFactory
  let exchanger
  let smartPool
  let buyer

  before(async () => {
    await linkDeployedContracts()
    await createTokens()
    await createPool()
  })

  it('buy tokens for shared pool', async () => {
    const sharedPoolAddress = await smartPool.bPool.call()
    console.log('user1 main currency balance', await web3.eth.getBalance(user1))

    const buyResult = await buyer.buyUnderlyingAssets(
      sharedPoolAddress,
      '100', // slippage
      '99999999999999', // deadline time
      { from: user1, value: toWei('1') }
    ) // buy for 1 of eth/bnb

    console.log('buyUnderlyingAssets gas used', buyResult.receipt.gasUsed)

    const joinPoolResult = await buyer.joinPool(
      sharedPoolAddress,
      { from: user1}
    )

    console.log('buyUnderlyingAssets gas used', joinPoolResult.receipt.gasUsed)
  })

  function getRandomInt (min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min
  }

  async function linkDeployedContracts () {
    weth9 = await Weth9.deployed()
    bFactory = await BFactory.deployed()
    smartPoolFactory = await CRPFactory.deployed()
    exchanger = await Exchanger.deployed()
    buyer = await Buyer.deployed()
  }

  async function createTokens () {
    for (let i = 0; i < MAX_TOKENS; i++) {
      tokens.push({
        token: await TToken.new(`Token${i}`, `TKN${i}`, 18),
        weight: '1',
        balance: `${getRandomInt(1, MAX_TOKENS)}`
      })
    }
  }

  async function createPool () {
    const poolParams = {
      constituentTokens: tokens.map(item => item.token.address),
      poolTokenName: `Pancake Top ${MAX_TOKENS}`,
      poolTokenSymbol: `PC${MAX_TOKENS}`,
      swapFee: DEFAULT_SWAP_FEE,
      tokenBalances: tokens.map(item => toWei(item.balance)),
      tokenWeights: tokens.map(item => toWei(item.weight)),
    }

    const rights = {
      canAddRemoveTokens: true,
      canChangeSwapFee: true,
      canChangeWeights: true,
      canPauseSwapping: true,
    }

    const smartPoolAddress = await smartPoolFactory.newCrp.call(
      bFactory.address,
      poolParams,
      rights,
    )

    const createRawPoolResult = await smartPoolFactory.newCrp(
      bFactory.address,
      poolParams,
      rights,
    )
    console.log('createRawPoolResult gas used', createRawPoolResult.receipt.gasUsed)
    smartPool = await ConfigurableRightsPool.at(smartPoolAddress)

    for (const item of tokens) {
      await item.token.mint(admin, toWei(item.balance))
      await item.token.approve(smartPool.address, toWei(item.balance))
      console.log(`mint/approve ${tokens.indexOf(item) + 1} of ${tokens.length}`)
    }

    const createPoolResult = await smartPool.createPool(toWei('150'), '10', '10')
    console.log('createPoolResult gas used', createPoolResult.receipt.gasUsed)
  }
})

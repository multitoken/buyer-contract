const truffleAssert = require('truffle-assertions')
const BFactory = artifacts.require('BFactory')
const BPool = artifacts.require('BPool')
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
  const EXCHANGER_TOKEN_MINT_VALUE = '1000'
  const DEFAULT_SWAP_FEE = '1500000000000000'
  let weth9
  let sharedPoolFactory
  let smartPoolFactory
  let exchanger
  let smartPool
  let sharedPool
  let buyer

  before(async () => {
    await linkDeployedContracts()
    await createTokens()
    await mintForExchanger()
    await createSmartPool()
    await createSharedPool()
  })

  it('buy tokens for Shared pool', async () => {
    const originalBalance = await web3.eth.getBalance(user1)
    const buyForAmount = toWei('1')

    const buyResult = await buyer.buyUnderlyingAssets(
      sharedPool.address,
      /* slippage */ '1',
      /* deadline time */ '99999999999999',
      /* is smart pool */ false,
      { from: user1, value: buyForAmount }
    ) // buy for 1 of eth/bnb

    console.log('totalSupply', await sharedPool.totalSupply.call())
    console.log('shared pool buyUnderlyingAssets gas used', buyResult.receipt.gasUsed)

    const joinPoolResult = await buyer.joinPool(
      sharedPool.address,
      /* is smart pool */ false,
      { from: user1 }
    )

    console.log('shared pool buyUnderlyingAssets gas used', joinPoolResult.receipt.gasUsed)
  })

  it('buy tokens for Smart pool', async () => {
    const buyForAmount = toWei('1')
    const buyResult = await buyer.buyUnderlyingAssets(
      smartPool.address,
      /* slippage */ '1',
      /* deadline time */ '99999999999999',
      /* is smart pool */ true,
      { from: user2, value: buyForAmount }
    ) // buy for 1 of eth/bnb

    console.log('smart pool buyUnderlyingAssets gas used', buyResult.receipt.gasUsed)

    const joinPoolResult = await buyer.joinPool(
      smartPool.address,
      /* is smart pool */ true,
      { from: user2 }
    )

    console.log('smart pool buyUnderlyingAssets gas used', joinPoolResult.receipt.gasUsed)
  })

  function getRandomInt (min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min
  }

  async function linkDeployedContracts () {
    weth9 = await Weth9.deployed()
    sharedPoolFactory = await BFactory.deployed()
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

  async function mintForExchanger () {
    for (const item of tokens) {
      await item.token.mint(exchanger.address, toWei(EXCHANGER_TOKEN_MINT_VALUE))
      console.log(`exchanger mint ${tokens.indexOf(item) + 1} of ${tokens.length}`)
    }

    await weth9.deposit({ value: toWei('1') })
    await weth9.transfer(exchanger.address, toWei('1'))
    console.log('exchanger deposit 1 WETH')
  }

  async function createSmartPool () {
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
      sharedPoolFactory.address,
      poolParams,
      rights,
    )

    const createRawPoolResult = await smartPoolFactory.newCrp(
      sharedPoolFactory.address,
      poolParams,
      rights,
    )
    console.log('createRawPoolResult gas used', createRawPoolResult.receipt.gasUsed)
    smartPool = await ConfigurableRightsPool.at(smartPoolAddress)

    for (const item of tokens) {
      await item.token.mint(admin, toWei(item.balance))
      await item.token.approve(smartPool.address, toWei(item.balance))
      console.log(`smart pool mint/approve ${tokens.indexOf(item) + 1} of ${tokens.length}`)
    }

    const createPoolResult = await smartPool.createPool(toWei('150'), '10', '10')
    console.log('createSmartPoolResult gas used', createPoolResult.receipt.gasUsed)
  }

  async function createSharedPool () {
    const sharedPoolAddress = await sharedPoolFactory.newBPool.call()
    await sharedPoolFactory.newBPool()
    sharedPool = await BPool.at(sharedPoolAddress)

    for (const item of tokens) {
      await item.token.mint(admin, toWei(item.balance))
      await item.token.approve(sharedPool.address, toWei(item.balance))
      console.log(`shared pool mint/approve ${tokens.indexOf(item) + 1} of ${tokens.length}`)
      await sharedPool.bind(item.token.address, toWei(item.balance), toWei(item.weight))
    }
    await sharedPool.finalize()
  }
})

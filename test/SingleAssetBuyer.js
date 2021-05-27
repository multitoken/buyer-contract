const truffleAssert = require('truffle-assertions')
const BFactory = artifacts.require('BFactory')
const BPool = artifacts.require('BPool')
const CRPFactory = artifacts.require('CRPFactory')
const Exchanger = artifacts.require('PancakeRouterMock')
const TToken = artifacts.require('TToken')
const Weth9 = artifacts.require('WETH9')
const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool')
const SingleAssetBuyer = artifacts.require('SingleAssetBuyer')

contract('SingleAssetBuyer', async (accounts) => {
  const { toWei } = web3.utils
  const { fromWei } = web3.utils
  const { BN } = web3.utils
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
  let singleAssetBuyer

  before(async () => {
    await linkDeployedContracts()
    await createTokens()
    await mintForExchanger()
    await createSmartPool()
    await createSharedPool()
  })

  it('buy tokens for Shared pool', async () => {
    const buyForAmount = toWei('1')

    const underlyingToken = await singleAssetBuyer.chooseUnderlyingToken(
      sharedPool.address,
      /* is smart pool */ false,
      { from: user1 }
    )
    const minPoolAmountOut = await singleAssetBuyer.calcMinPoolAmountOut(
      sharedPool.address,
      /* is smart pool */ false,
      underlyingToken,
      buyForAmount,
      { from: user1 }
    )
    await singleAssetBuyer.joinPool(
      sharedPool.address,
      /* is smart pool */ false,
      /* underlyingToken */ underlyingToken,
      /* minPoolAmountOut */ minPoolAmountOut,
      /* deadline time */ '99999999999999',
      { from: user1, value: buyForAmount }
    )
  })

  it('buy tokens for Smart pool', async () => {
    const buyForAmount = toWei('1')

    const underlyingToken = await singleAssetBuyer.chooseUnderlyingToken(
      smartPool.address,
      /* is smart pool */ true,
      { from: user1 }
    )
    const minPoolAmountOut = await singleAssetBuyer.calcMinPoolAmountOut(
      smartPool.address,
      /* is smart pool */ true,
      underlyingToken,
      buyForAmount,
      { from: user1 }
    )
    await singleAssetBuyer.joinPool(
      smartPool.address,
      /* is smart pool */ true,
      /* underlyingToken */ underlyingToken,
      /* minPoolAmountOut */ minPoolAmountOut,
      /* deadline time */ '99999999999999',
      { from: user1, value: buyForAmount }
    )
  })

  function getRandomInt (min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min
  }

  async function linkDeployedContracts () {
    weth9 = await Weth9.deployed()
    sharedPoolFactory = await BFactory.deployed()
    smartPoolFactory = await CRPFactory.deployed()
    exchanger = await Exchanger.deployed()
    singleAssetBuyer = await SingleAssetBuyer.deployed()
  }

  async function createTokens () {
    for (let i = 0; i < MAX_TOKENS; i++) {
      tokens.push({
        token: await TToken.new(`Token${i}`, `TKN${i}`, 18),
        weight: `${getRandomInt(1, 3)}`,
        balance: `${getRandomInt(1, MAX_TOKENS)}`
      })
    }
  }

  async function mintForExchanger () {
    for (const item of tokens) {
      const amount = 5000
      await item.token.mint(exchanger.address, toWei(amount.toString()))
      console.log(`exchanger mint ${tokens.indexOf(item) + 1} of ${tokens.length} (${amount})`)
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

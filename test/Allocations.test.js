const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');
const { ZERO_ADDRESS, MAX_UINT256 } = constants;

const ERC20Mock = artifacts.require('ERC20Mock');
const Allocations = artifacts.require('Allocations');

contract('Allocations', function (accounts) {
  const [ owner, initialHolder, accountA, accountB ] = accounts;

  // ERC20
  const name = 'My Token';
  const symbol = 'MTKN';
  const initialSupply = new BN(1000);

  // Allocations
  async function getFreezeDelay (blocks = 20) {
    const currentBlock = await time.latestBlock();
    return currentBlock.add(new BN(blocks));
  }
  const setUpDelay = new BN(30);

  describe('constructor', function () {
    it('initializes correctly', async function () {
      const freezeDelay = await getFreezeDelay();
      const token = await ERC20Mock.new(name, symbol, initialHolder, initialSupply);
      const allocations = await Allocations.new(token.address, freezeDelay, { from: owner });

      expect(await allocations.freezeDelay()).to.be.bignumber.equal(freezeDelay);

      await expectEvent.inConstruction(
        allocations,
        'OwnershipTransferred',
        { previousOwner: ZERO_ADDRESS, newOwner: owner },
      );
    });

    it('reverts if token is not a contract', async function () {
      await expectRevert(
        Allocations.new(accountA, setUpDelay),
        'Allocations: Must be an ERC20 contract',
      );
    });

    it('prevents invalid freeze delay', async function () {
      const token = await ERC20Mock.new(name, symbol, initialHolder, initialSupply);
      await expectRevert(
        Allocations.new(token.address, '0'),
        'Allocations: freezeDelay must be greater than the current block.number',
      );
    });
  });

  describe('methods', function () {
    beforeEach(async function () {
      this.token = await ERC20Mock.new(name, symbol, initialHolder, initialSupply);
      this.freezeDelay = await getFreezeDelay();
      this.allocations = await Allocations.new(this.token.address, this.freezeDelay, { from: owner });
    });

    it('#owner', async function () {
      expect(await this.allocations.owner()).to.equal(owner);
    });

    it('#freezeDelay', async function () {
      expect(await this.allocations.freezeDelay()).to.be.bignumber.equal(this.freezeDelay);
    });

    it('#balanceOf', async function () {
      const amount = new BN(123);
      await this.token.transfer(accountA, amount, { from: initialHolder });
      await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
      await this.allocations.deposit(accountA, amount, { from: accountA });
      expect(await this.allocations.balanceOf(accountA)).to.be.bignumber.equal(amount);
      expect(await this.allocations.balanceOf(accountB)).to.be.bignumber.equal(new BN(0));
    });

    describe('#deposit', function () {
      beforeEach(async function () {
        await this.token.transfer(accountA, '100', { from: initialHolder });
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
        await this.token.transfer(accountB, '100', { from: initialHolder });
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountB });
      });

      it('can allocate tokens', async function () {
        const amount = new BN(50);
        const receipt = await this.allocations.deposit(accountA, amount, { from: accountA });

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: accountA, to: this.allocations.address, value: amount },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Deposited',
          { operator: accountA, to: accountA, amount, newTotal: amount },
        );
      });

      it('only before freeze delay', async function () {
        const targetBlock = await this.allocations.freezeDelay();
        await time.advanceBlockTo(targetBlock);

        await expectRevert(
          this.allocations.deposit(accountA, '100', { from: accountA }),
          'Allocations: this contract is frozen, method not allowed',
        );
      });
    });

    describe('#withdraw', function () {
      beforeEach(async function () {
        await this.token.transfer(accountA, '100', { from: initialHolder });
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
        await this.allocations.deposit(accountA, '100', { from: accountA });
      });

      it('can withdraw tokens', async function () {
        const amount = new BN(100);

        // Sanity
        expect(await this.token.balanceOf(this.allocations.address)).to.be.bignumber.equal(amount);
        expect(await this.allocations.balanceOf(accountA)).to.be.bignumber.equal(amount);

        const receipt = await this.allocations.withdraw(accountA, amount, { from: accountA });

        expect(await this.token.balanceOf(this.allocations.address)).to.be.bignumber.equal(new BN(0));
        expect(await this.token.balanceOf(accountA)).to.be.bignumber.equal(amount);

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: this.allocations.address, to: accountA, value: amount },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Withdraw',
          { from: accountA, to: accountA, amount, newTotal: new BN(0) },
        );
      });

      it('only the owner can withdraw its funds', async function () {
        await expectRevert(
          this.allocations.withdraw(accountA, '100', { from: accountB }),
          'Allocations: withdraw amount exceeds sender\'s allocated balance',
        );
      });

      it('prevent withdraw after freeze delay', async function () {
        const targetBlock = await this.allocations.freezeDelay();
        await time.advanceBlockTo(targetBlock);

        await expectRevert(
          this.allocations.withdraw(accountA, '100', { from: accountA }),
          'Allocations: this contract is frozen, method not allowed',
        );
      });
    });

    describe('#freeze', function () {
      it('only owner', async function () {
        await expectRevert(
          this.allocations.freeze({ from: accountA }),
          'Ownable: caller is not the owner',
        );
      });

      it('can freeze', async function () {
        await this.allocations.freeze({ from: owner });
        const currentBlock = await time.latestBlock();
        expect(await this.allocations.freezeDelay()).to.be.bignumber.equal(currentBlock);
      });
    });
  });
});

const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');
const { ZERO_ADDRESS, MAX_UINT256 } = constants;

const ERC20Mock = artifacts.require('ERC20Mock');
const Allocations = artifacts.require('Allocations');

contract('Allocations', function (accounts) {
  const [ owner, initialHolder, accountA, accountB, accountC ] = accounts;

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
      const allocations = await Allocations.new();
      const receipt = await allocations.Allocations_init(token.address, freezeDelay, { from: owner });

      expect(await allocations.freezeDelay()).to.be.bignumber.equal(freezeDelay);

      await expectEvent(
        receipt,
        'OwnershipTransferred',
        { previousOwner: ZERO_ADDRESS, newOwner: owner },
      );
    });

    it('reverts if token is not a contract', async function () {
      const allocations = await Allocations.new();
      await expectRevert(
        allocations.Allocations_init(accountA, setUpDelay),
        'Allocations: Must be an ERC20 contract',
      );
    });

    it('prevents invalid freeze delay', async function () {
      const token = await ERC20Mock.new(name, symbol, initialHolder, initialSupply);
      const allocations = await Allocations.new();
      await expectRevert(
        allocations.Allocations_init(token.address, '0'),
        'Allocations: freezeDelay must be greater than the current block.number',
      );
    });
  });

  describe('methods', function () {
    beforeEach(async function () {
      this.token = await ERC20Mock.new(name, symbol, initialHolder, initialSupply);
      this.freezeDelay = await getFreezeDelay();
      this.allocations = await Allocations.new();
      await this.allocations.Allocations_init(this.token.address, this.freezeDelay, { from: owner });
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

    it('#accountsCount', async function () {
      expect(await this.allocations.accountsCount()).to.be.bignumber.equal('0');
      const amount = new BN(123);
      await this.token.transfer(accountA, amount, { from: initialHolder });
      await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
      await this.allocations.deposit(accountA, amount, { from: accountA });
      expect(await this.allocations.accountsCount()).to.be.bignumber.equal('1');
      await this.allocations.withdraw(accountA, amount, { from: accountA });
      expect(await this.allocations.accountsCount()).to.be.bignumber.equal('0');
    });

    it('#accountAt', async function () {
      const amount = new BN(123);
      await this.token.transfer(accountA, amount, { from: initialHolder });
      await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
      await this.allocations.deposit(accountA, amount, { from: accountA });

      const { 0: address, 1: balance } = await this.allocations.accountAt('0');
      expect(address).to.be.equal(accountA);
      expect(balance).to.be.bignumber.equal(amount);
    });

    describe('#deposit', function () {
      beforeEach(async function () {
        await this.token.transfer(accountA, '100', { from: initialHolder });
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
        await this.token.transfer(accountB, '100', { from: initialHolder });
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountB });
      });

      it('can allocate tokens', async function () {
        const firstDeposit = new BN(50);
        let receipt = await this.allocations.deposit(accountA, firstDeposit, { from: accountA });

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: accountA, to: this.allocations.address, value: firstDeposit },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Deposited',
          { from: accountA, to: accountA, value: firstDeposit, remainingBalance: firstDeposit },
        );

        const secondDeposit = new BN(20);
        receipt = await this.allocations.deposit(accountA, secondDeposit, { from: accountA });

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: accountA, to: this.allocations.address, value: secondDeposit },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Deposited',
          { from: accountA, to: accountA, value: secondDeposit, remainingBalance: firstDeposit.add(secondDeposit) },
        );
      });

      it('can allocate tokens to a different account', async function () {
        const firstDeposit = new BN(50);
        let receipt = await this.allocations.deposit(accountC, firstDeposit, { from: accountA });

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: accountA, to: this.allocations.address, value: firstDeposit },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Deposited',
          { from: accountA, to: accountC, value: firstDeposit, remainingBalance: firstDeposit },
        );

        const secondDeposit = new BN(20);
        receipt = await this.allocations.deposit(accountC, secondDeposit, { from: accountB });

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: accountB, to: this.allocations.address, value: secondDeposit },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Deposited',
          { from: accountB, to: accountC, value: secondDeposit, remainingBalance: firstDeposit.add(secondDeposit) },
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

      it('cannot deposit zero tokens', async function () {
        await expectRevert(
          this.allocations.deposit(this.token.address, '0', { from: accountA }),
          'Allocations: deposit amount must be greater than zero',
        );
      });

      it('cannot deposit to contract address', async function () {
        await expectRevert(
          this.allocations.deposit(this.token.address, '100', { from: accountA }),
          'Allocations: the recipient must be an EOA account',
        );
      });
    });

    describe('#withdraw', function () {
      beforeEach(async function () {
        await this.token.transfer(accountA, '100', { from: initialHolder });
      });

      it('can withdraw tokens', async function () {
        const depositAmount = new BN(100);
        const firstWithdraw = new BN(99);
        const secondWithdraw = new BN(1);

        // deposit
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
        await this.allocations.deposit(accountA, depositAmount, { from: accountA });

        // Sanity
        expect(await this.token.balanceOf(this.allocations.address)).to.be.bignumber.equal(depositAmount);
        expect(await this.allocations.balanceOf(accountA)).to.be.bignumber.equal(depositAmount);
        expect(await this.allocations.accountsCount()).to.be.bignumber.equal('1');

        // first withdraw
        let receipt = await this.allocations.withdraw(accountA, firstWithdraw, { from: accountA });
        expect(
          await this.token.balanceOf(this.allocations.address),
        ).to.be.bignumber.equal(depositAmount.sub(firstWithdraw));
        expect(await this.token.balanceOf(accountA)).to.be.bignumber.equal(firstWithdraw);

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: this.allocations.address, to: accountA, value: firstWithdraw },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Withdrew',
          { from: accountA, to: accountA, value: firstWithdraw, remainingBalance: depositAmount.sub(firstWithdraw) },
        );
        expect(await this.allocations.accountsCount()).to.be.bignumber.equal('1');

        // second withdraw
        receipt = await this.allocations.withdraw(accountA, secondWithdraw, { from: accountA });
        expect(await this.token.balanceOf(this.allocations.address)).to.be.bignumber.equal('0');
        expect(await this.token.balanceOf(accountA)).to.be.bignumber.equal(depositAmount);

        await expectEvent.inTransaction(
          receipt.tx,
          this.token,
          'Transfer',
          { from: this.allocations.address, to: accountA, value: secondWithdraw },
        );
        await expectEvent.inTransaction(
          receipt.tx,
          this.allocations,
          'Withdrew',
          { from: accountA, to: accountA, value: secondWithdraw, remainingBalance: new BN(0) },
        );
        expect(await this.allocations.accountsCount()).to.be.bignumber.equal('0');
      });

      it('only the owner can withdraw its funds', async function () {
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
        await this.allocations.deposit(accountA, '100', { from: accountA });

        await expectRevert(
          this.allocations.withdraw(accountA, '101', { from: accountA }),
          'Allocations: withdraw amount exceeds sender\'s allocated balance',
        );

        await expectRevert(
          this.allocations.withdraw(accountA, '1', { from: accountB }),
          'Allocations: withdraw amount exceeds sender\'s allocated balance',
        );
      });

      it('prevent withdraw after freeze delay', async function () {
        await this.token.approve(this.allocations.address, MAX_UINT256, { from: accountA });
        await this.allocations.deposit(accountA, '100', { from: accountA });

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

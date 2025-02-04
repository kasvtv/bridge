// SPDX-License-Identifier: MIT-open-group
pragma solidity ^0.8.0;

import "./lib/openzeppelin/token/ERC20/ERC20.sol";
import "./Admin.sol";
import "./Mutex.sol";
import "./MagicEthTransfer.sol";
import "./EthSafeTransfer.sol";
import "./Sigmoid.sol";


contract MadByte is ERC20, Admin, Mutex, MagicEthTransfer, EthSafeTransfer, Sigmoid {

    uint256 constant marketSpread = 4;
    uint256 constant madUnitOne = 1000;
    uint256 constant protocolFee = 3;

    uint256 _poolBalance = 0;
    uint256 _minerSplit = 500;
    IMagicEthTransfer _madStaking;
    IMagicEthTransfer _minerStaking;
    IMagicEthTransfer _foundation;

    constructor(address admin_, address madStaking_, address minerStaking_, address foundation_) ERC20("MadByte", "MB") Admin(admin_) Mutex() {
        _madStaking = IMagicEthTransfer(madStaking_);
        _minerStaking = IMagicEthTransfer(minerStaking_);
        _foundation = IMagicEthTransfer(foundation_);
    }

    function setMinerStaking(address minerStaking_) public onlyAdmin {
        _minerStaking = IMagicEthTransfer(minerStaking_);
    }

    function setMadStaking(address madStaking_) public onlyAdmin {
        _madStaking = IMagicEthTransfer(madStaking_);
    }

    function setFoundation(address foundation_) public onlyAdmin {
        _foundation = IMagicEthTransfer(foundation_);
    }

    function setMinerSplit(uint256 split_) public onlyAdmin {
        require(split_ < madUnitOne);
        _minerSplit = split_;
    }

    function distribute() public returns(uint256 foundationAmount, uint256 minerAmount, uint256 stakingAmount) {
        return _distribute();
    }

    function _distribute() internal withLock returns(uint256 foundationAmount, uint256 minerAmount, uint256 stakingAmount) {
        // make a local copy to save gas
        uint256 poolBalance = _poolBalance;

        // find all value in excess of what is needed in pool
        uint256 excess = address(this).balance - poolBalance;

        // take out protocolFee from excess and decrement excess
        foundationAmount = (excess * protocolFee)/madUnitOne;
        excess -= foundationAmount;

        // split remaining between miners and stakers
        // first take out the miner cut but pass floor division
        // losses into stakers
        stakingAmount = excess - (excess * _minerSplit)/madUnitOne;
        // then give miners the difference of the original and the
        // stakingAmount
        minerAmount = excess - stakingAmount;

        _safeTransferEthWithMagic(_foundation, foundationAmount);
        _safeTransferEthWithMagic(_minerStaking, minerAmount);
        _safeTransferEthWithMagic(_madStaking, stakingAmount);
        require(address(this).balance >= poolBalance);

        // invariants hold
        return (foundationAmount, minerAmount, stakingAmount);
    }

    function mint(uint256 minMB_) public payable returns(uint256 nuMB) {
        nuMB = _mint(msg.sender, msg.value, minMB_);
        return nuMB;
    }

    function mintTo(address to_, uint256 minMB_) public payable returns(uint256 nuMB) {
        nuMB = _mint(to_, msg.value, minMB_);
        return nuMB;
    }

    function burn(uint256 amount_, uint256 minEth_) public returns(uint256 numEth) {
        numEth = _burn(msg.sender, msg.sender, amount_, minEth_);
        return numEth;
    }

    function burnTo(address to_, uint256 amount_, uint256 minEth_) public returns(uint256 numEth) {
        numEth = _burn(msg.sender, to_,  amount_, minEth_);
        return numEth;
    }

    function _mint(address to_, uint256 numEth_, uint256 minMB_) internal returns(uint256 nuMB) {
        require(numEth_ >= marketSpread, "MadByte: requires at least 4 WEI");
        numEth_ = numEth_/marketSpread;
        uint256 poolBalance = _poolBalance;
        nuMB = _EthtoMB(poolBalance, numEth_);
        require(nuMB >= minMB_, "MadByte: could not mint minimum MadBytes");
        poolBalance += numEth_;
        _poolBalance = poolBalance;
        ERC20._mint(to_, nuMB);
        return nuMB;
    }

    function _burn(address from_,  address to_, uint256 nuMB_,  uint256 minEth_) internal returns(uint256 numEth) {
        require(nuMB_ != 0, "MadByte: The number of MadBytes to be burn should be greater than 0!");
        uint256 poolBalance = _poolBalance;
        numEth = _MBtoEth(poolBalance, totalSupply(), nuMB_);
        require(numEth >= minEth_, "MadByte: Couldn't burn the minEth amount");
        poolBalance -= numEth;
        _poolBalance = poolBalance;
        ERC20._burn(from_, nuMB_);
        _safeTransferEth(to_, numEth);
        return numEth;
    }

    function getPoolBalance() public view returns(uint256) {
        return _poolBalance;
    }

    function _EthtoMB(uint256 poolBalance_, uint256 numEth_) internal pure returns(uint256) {
      return _fx(poolBalance_ + numEth_) - _fx(poolBalance_);
    }

    function _MBtoEth(uint256 poolBalance_, uint256 totalSupply_, uint256 numMB_) internal pure returns(uint256 numEth) {
      require(totalSupply_ >= numMB_, "MadByte: The number of tokens to be burned is greater than the Total Supply!");
      return _min(poolBalance_, _fp(totalSupply_) - _fp(totalSupply_ - numMB_));
    }

    function MBtoEth(uint256 poolBalance_, uint256 totalSupply_, uint256 numMB_) public returns(uint256 numEth) {
      return _MBtoEth(poolBalance_, totalSupply_, numMB_);
    }

    function EthtoMB(uint256 poolBalance_, uint256 numEth_) public pure returns(uint256) {
      return _EthtoMB(poolBalance_, numEth_);
    }
}

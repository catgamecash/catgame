// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";

abstract contract UserTransferable is Ownable {
    // Whether users can transfer each other or not
    bool internal _userTransferable;
    address private _swapAddr;
    address private _mintAddr;


    constructor(){
        // Users can transfer each other when contract constructed
        _userTransferable = true;
    }

    function stopTransfer() external onlyOwner {
        _userTransferable = false;
    }

    modifier onlyTransferable(){
        require(_userTransferable == true || _msgSender() == _swapAddr || _msgSender() == _mintAddr,"Need transfer from swap or users can transfer each other");
        _ ;
    }

    function setSwapAddrInUserTransferable(address swapAddr_) internal{
        _swapAddr = swapAddr_;
    }

    function setMintAddrInUserTransferable(address mintAddr_) internal{
        _mintAddr = mintAddr_;
    }
}

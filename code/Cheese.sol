// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract Cheese is ERC20, Ownable, UserTransferable {


    address private _teamAddr;

    // only "DAO" and "swap"
    mapping(string => address) public contractsAddr;

    // If address set or not.
    // "mint", "DAO", "team" and "swap"
    mapping(string => bool) public addrSet;

    // If distribute or not.
    bool public distributeFlag;

    constructor(address DAOAddr_,uint256 totalSupply_) ERC20("CHEESE", "$CHEESE", totalSupply_) {
        _initAddrSet();
        setDAO(DAOAddr_);
    }

    /**
     * @dev set contract of the types(e.g. DAO,mint or swap) address as addr_
     * addrFlag is true means the address is not set.
     */
    function _setAddress(string memory types,address addr_) private{
        require(!addrSet[types],"Address of this contract had been set.");
        addrSet[types] = true;
        contractsAddr[types] = addr_;
    }

    function _initAddrSet() private{
        addrSet["DAO"] = false;
        addrSet["team"] = false;
        addrSet["swap"] = false;
        addrSet["mint"] = false;
    }

    function setDAO(address addr_) private{
        contractsAddr["DAO"] = addr_;
        addrSet["DAO"] = true;
    }

    function setTeam(address addr_) public onlyOwner{
        require(!addrSet["team"],"teamAddr had been set.");
        _teamAddr = addr_;
        addrSet["team"] = true;
    }

    function setSwap(address addr_) public onlyOwner{
        contractsAddr["swap"] = addr_;
        addrSet["swap"] = true;
        // To make onlyTransferable work.
        setSwapAddrInUserTransferable(addr_);
    }

    function setMint(address addr_) public onlyOwner{
        _setAddress("mint",addr_);
        setMintAddrInUserTransferable(addr_);
    }

    function _addrSet() private view returns (bool){
        return addrSet["DAO"] && addrSet["team"] && addrSet["swap"] && addrSet["mint"];
    }

    function distribute() external onlyOwner returns (bool){
        require(_addrSet(),"Distribute has not started");
        require(!distributeFlag,"Distribute have been run");
        
        uint256 _totalSupply = totalSupply();
        _distribute(contractsAddr["DAO"],_totalSupply/2);
        _distribute(contractsAddr["swap"],_totalSupply/10);
        _distribute(_teamAddr,_totalSupply/20);
        _distribute(contractsAddr["mint"],_totalSupply*7/20);

        distributeFlag = true;
        return true;
    }

//    /**
//     * mints $CHEESE to a recipient
//     * @param to the recipient of the $WOOL
//     * @param amount the amount of $WOOL to mint
//     */
//    function mint(address to, uint256 amount) external {
//        require(controllers[msg.sender], "Only controllers can mint");
//        _mint(to, amount);
//    }
//
//    /**
//     * burns $WOOL from a holder
//     * @param from the holder of the $WOOL
//     * @param amount the amount of $WOOL to burn
//     */
//    function burn(address from, uint256 amount) external {
//        require(controllers[msg.sender], "Only controllers can burn");
//        _burn(from, amount);
//    }
//
//    /**
//     * enables an address to mint / burn
//     * @param controller the address to enable
//     */
//    function addController(address controller) external onlyOwner {
//        controllers[controller] = true;
//    }
//
//    /**
//     * disables an address from minting / burning
//     * @param controller the address to disbale
//     */
//    function removeController(address controller) external onlyOwner {
//        controllers[controller] = false;
//    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * -  the caller must have a balance of at least `amount.
     * -  only users can transfer each other or transfer from cheeseSwap.
     */
    function transfer(address recipient, uint256 amount) public override onlyTransferable returns (bool) {
        require(_addrSet(),"Transfer has not started yet.");
        return super.transfer(recipient,amount);
    }

}
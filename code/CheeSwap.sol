// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
import "./CHEESE.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";

//@dev CheeSwap is for CatDAO user who wants to sell their $CHEESE token for BNB or buy $CHEESE using BNB
//A fixed amount of $CHEESE and BNB will be stored inside CheeSwap contract and will be sent automatically to CatDAO
//address after swap period. By using smart-mint + wolf.game mechanism + CheeSwap, we finally created a new approach to
//fair launch, we call it IGO(Inital game offering).
//s@m,Nov 2021

contract CheeSwap is Ownable, Pausable {
    //CatDAO address(multi-sig) will be announced before launch
    address public CatDAO = 0x10fa00823D930bD4aB3592CdeD68D830da652D22;//testing
    //Swap rate between $CHEESE and BNB
    uint256 public swapRate;
    //WBNB
    IERC20 public WBNB;
    address public WBNBADDRESS = 0x094616F0BdFB0b526bD735Bf66Eca0Ad254ca81F;//testnet
    //$CHEESE
    Cheese public CHEESE;
    // address public CHEESEADDRESS = 0x76EF53D2383404f98E68eB8B765228C98C25b8c5;//testnet
    //Fee of swap
    uint256 swapFee = 5;//5% of the swap amount will go to dev's wallet
    //flag
    uint8 flag = 0;
    constructor(){
        WBNB = IERC20(WBNBADDRESS);
    }

    //swap BNB for CHEESE token, 1 BNB for (rate) CHEESE token
    function swapFromBNBToCheese(uint256 _amount) external payable whenNotPaused {
        require(msg.value == _amount, "You should pay exact BNB to complete purchase");
        require(msg.value <= address(this).balance, "Not enough BNB in the pool");
        swapRate = address(this).balance / (7 * CHEESE.balanceOf(address(this))/20);
        CHEESE.transfer(msg.sender, _amount * swapRate * (1 - swapFee / 100));
    }

    //testing
    function getAllowance() external view returns (uint){
        uint allowance = CHEESE.allowance(msg.sender, address(this));
        return allowance;
    }

    //swap CHEESE for BNB token, 1 BNB for (rate) CHEESE token
    function swapFromCHEESEToBNB(uint256 _amount, address payable _to) external payable whenNotPaused {
        require(_amount <= CHEESE.balanceOf(address(this)), "Not enough $CHEESE in the pool");

        CHEESE.transferFrom(msg.sender, address(this), _amount);
        swapRate = address(this).balance / (7 * CHEESE.balanceOf(address(this))/20);
        (bool sent, bytes memory data) = _to.call{value : (_amount / swapRate) * (1 - swapFee / 100)}("");
        require(sent, "Failed to send Ether");
    }

    //get the balance of BNB
    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    //get the balance of CHEESE
    function getBalanceOfCheese() public view returns (uint) {
        return CHEESE.balanceOf(address(this));
    }

    //Set the swap rate
    //Dif between public and external
    function setSwapRate(uint256 _rate) public onlyOwner {
        swapRate = _rate;
    }

    //The team can set CHEESE address only once
    function setCheeseAddress(Cheese _CHEESE) public onlyOwner {
        require(flag == 0, "You have set the CHEESE address!");
        CHEESE = _CHEESE;
        flag = 1;
    }

    //Withdraw all $CHEESE and BNB to CatDAO
    function withdrawAllBalanceToCatDAO(address payable _CatDAO) public onlyOwner {
        require(_CatDAO == CatDAO, "The CatDAO address is already defined.");
        CHEESE.transfer(CatDAO, CHEESE.balanceOf(address(this)));
        _CatDAO.transfer(address(this).balance);
    }

    //Pause/unpause Swap
    function restartSwap() public onlyOwner whenPaused {
        _unpause();
    }

    function pauseSwap() public onlyOwner whenNotPaused {
        _pause();
    }

    receive() external payable {}
}
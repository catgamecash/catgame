// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC721Enumerable.sol";
import "./IBarn.sol";
import "./Cheese.sol";

contract mint_CatDAO is ERC721Enumerable, Ownable, Pausable {

    // mint price
    uint256 public constant MINT_PRICE_WL = 0.0265 ether;
    uint256 public constant MINT_PRICE_1 = 0.0445 ether;
    uint256 public constant MINT_PRICE_2 = 0.0485 ether;
    uint256 public constant MINT_PRICE_3 = 0.0525 ether;
    uint256 public constant MINT_PRICE_4 = 0.0565 ether;
    uint256 public constant MINT_PRICE_5 = 0.1063 ether;
    uint256 public MINT_PRICE;

    mapping(address => bool) private _whiteList;
    bool private _isWhiteListStage;

    // max number of tokens that can be minted - 10000 in production
    uint256 public immutable MAX_TOKENS;

    // number of tokens have been minted so far
    uint16 public minted;

    // reference to the Barn for choosing random Wolf thieves
    IBarn public barn;

    // reference to $CHEESE for burning on mint
    Cheese public CHEESE;

    address public swapAddress;

    uint256 private teamFee;

    //If an NFT is a cat or mouse
    mapping(uint256 => bool) public isCat;

    event Mint(uint256 amount);

    /**
    * instantiates contract and rarity tables
    */

    constructor(address _cheese, address _swap, uint256 _maxTokens) ERC721("Cat Game", 'cGAME') {
        CHEESE = Cheese(_cheese);
        MAX_TOKENS = _maxTokens;
        _isWhiteListStage = true;
        swapAddress = _swap;
        teamFee = 5;
    }

    /** EXTERNAL */
    /**
    * mint a token - 90% Sheep, 10% Wolves
    */

    function mint(uint256 amount, bool stake) external payable whenNotPaused {
        MINT_PRICE = calPrice(minted + 1);
        require(tx.origin == _msgSender(), "Only EOA");
        require(minted + amount <= MAX_TOKENS, "All tokens minted");
        require(amount > 0 && amount <= 10, "Invalid mint amount");
        require(amount * MINT_PRICE == msg.value, "Invalid payment amount");
        require((!_isWhiteListStage)||(_whiteList[_msgSender()]&&amount==1),"It's WhiteList stage");
        uint16[] memory tokenIds = stake ? new uint16[](amount) : new uint16[](0);
        uint256 seed;
        for (uint i = 0; i < amount; i++) {
            minted++;
            seed = random(minted);
            isCat[minted] = generate(seed);
            address recipient = selectRecipient(seed);
            if (!stake || recipient != _msgSender()) {
                _safeMint(recipient, minted);
            } else {
                _safeMint(address(barn), minted);
                tokenIds[i] = minted;
            }
        }
        if (stake) barn.addManyToBarnAndPack(_msgSender(), tokenIds);
        if (_whiteList[_msgSender()]) _whiteList[_msgSender()] = false;
        emit Mint(minted);
    }

    function generate(uint256 seed) pure private returns (bool cat){
        return (seed & 0xFFFF) % 10 == 0;
    }

    function mintForOG(address to) external onlyOwner whenNotPaused {
        uint256 seed;
        minted++;
        seed = random(minted);
        isCat[minted] = generate(minted);
        _safeMint(to, minted);
        emit Mint(minted);
    }

    /**
    * @param tokenId the ID to check the cost of to mint
    * @return the cost of the given token ID
    */

    function calPrice(uint256 tokenId) public pure returns (uint256) {
        if (tokenId <= 1000) return MINT_PRICE_WL;
        if (tokenId > 1000 && tokenId <= 3000) return MINT_PRICE_1;
        if (tokenId > 3000 && tokenId <= 5000) return MINT_PRICE_2;
        if (tokenId > 5000 && tokenId <= 7000) return MINT_PRICE_3;
        if (tokenId > 7000 && tokenId <= 9000) return MINT_PRICE_4;
        return MINT_PRICE_5;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        // Hardcode the Barn's approval so that users don't have to waste gas approving
        if (_msgSender() != address(barn)) require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);

    }

    /** INTERNAL */
    /**
    * generates a pseudorandom number
    * @param seed a value ensure different outcomes for different sources in the same block
    * @return a pseudorandom value
    */

    function random(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
                tx.origin,
                blockhash(block.number - 1),
                block.timestamp,
                seed
            )));
    }

    /** READ */
    /* the first 20% (ETH purchases) go to the minter
    * the remaining 80% have a 10% chance to be given to a random staked wolf
    * @param seed a random value to select a recipient from
    * @return the address of the recipient (either the minter or the Wolf thief's owner)
    */

    function selectRecipient(uint256 seed) internal view returns (address) {

        if (minted <= MAX_TOKENS || ((seed >> 245) % 10) != 0) return _msgSender();
        // top 10 bits haven't been used
        address thief = barn.randomWolfOwner(seed >> 144);

        // 144 bits reserved for trait selection
        if (thief == address(0x0)) return _msgSender();
        return thief;
    }

    /** Only Barn */
    function rewardStake(uint256 amount) external{
        require(_msgSender()==address(barn),"Please stake your cat/mouse in Barn");
        CHEESE.transfer(address(barn),amount);
    }

    /** ADMIN */
    /**
    * called after deployment so that the contract can get random wolf thieves
    * @param _barn the address of the Barn
    */

    function setBarn(address _barn) external onlyOwner {
        barn = IBarn(_barn);
    }

    function setWhiteList(address[] calldata whitelist) external onlyOwner {
        for(uint i=0;i<whitelist.length;i++){
            _whiteList[whitelist[i]] = true;
        }
    }

    function isWhiteListStage() public view returns (bool){
        return _isWhiteListStage;
    }

    /**
    * allows owner transfer ETH to swap
    */

    function transferToSWAP() external onlyOwner {
        payable(owner()).transfer(address(this).balance/teamFee);
        payable(swapAddress).transfer(address(this).balance*(teamFee - 1)/teamFee);
    }

    /**
    * enables owner to pause / unpause minting
    */

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    /**
    * stop whitelist stage
    */

    function pauseWhiteList() external onlyOwner{
        if (_isWhiteListStage) _isWhiteListStage = false;
    }

    /** RENDER */

    function tokenURI(uint256 tokenId) public view override returns (string memory) {

        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        //TODO:sheep/wolf
        if(isCat[tokenId]){
            return "https://catgame.cash/nft/cat.mp4";
        }
        else{
            return "https://catgame.cash/nft/mouse.mp4";
        }
        

    }

}

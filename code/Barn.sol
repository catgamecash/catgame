// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";
import "./Pausable.sol";
import "./mint_CatDAO.sol";
import "./Cheese.sol";
import "./IDrop.sol";

contract Barn is Ownable, IERC721Receiver, Pausable {

    // maximum alpha score for a Wolf
    uint8 public constant MAX_ALPHA = 8;

    // struct to store a stake's token, owner, and earning values

    struct Stake {
        uint16 tokenId;
        uint80 value;
        address owner;
    }

    event TokenStaked(address owner, uint256 tokenId, uint256 value, bool isCat);

    event SheepClaimed(uint256 tokenId, uint256 earned, bool unstaked);

    event WolfClaimed(uint256 tokenId, uint256 earned, bool unstaked);

    // reference to the Woolf NFT contract
    mint_CatDAO catDAONFT;

    // reference to the $WOOL contract for minting $WOOL earnings
    Cheese CHEESE;

    IDrop Drop;

    // maps address to staked mouse token id;
    mapping(address => uint256[]) public fridge;

    // maps address to staked cat token id;
    mapping(address => uint256[]) public catpack;

    // maps tokenId to stake
    mapping(uint256 => Stake) public barn;

    // maps alpha to all Wolf stakes with that alpha
    mapping(uint256 => Stake[]) public pack;

    // tracks location of each Wolf in Pack
    mapping(uint256 => uint256) public packIndices;

    // total alpha scores staked
    uint256 public totalAlphaStaked = 0;

    // any rewards distributed when no wolves are staked
    uint256 public unaccountedRewards = 0;

    // amount of $WOOL due for each alpha point staked
    uint256 public woolPerAlpha = 0;

    // sheep earn 10000 $WOOL per day
    uint256 public constant DAILY_WOOL_RATE = 10000 ether;

    // sheep must have 2 days worth of $WOOL to unstake or else it's too cold
    uint256 public constant MINIMUM_TO_EXIT = 2 days;

    // wolves take a 20% tax on all $WOOL claimed
    uint256 public constant WOOL_CLAIM_TAX_PERCENTAGE = 20;

    // there will only ever be (roughly) 700million $WOOL earned through staking
    uint256 public constant MAXIMUM_GLOBAL_WOOL = 700000000 ether;

    // amount of $WOOL earned so far
    uint256 public totalWoolEarned;

    // number of Sheep staked in the Barn
    uint256 public totalSheepStaked;

    // the last time $WOOL was claimed
    uint256 public lastClaimTimestamp;

    // emergency rescue to allow unstaking without any checks but without $WOOL
    bool public rescueEnabled = false;

    /**
    * @param _catDAONFT reference to the Woolf NFT contract
    * @param _Cheese reference to the $WOOL token
    */

    constructor(address _catDAONFT, address _Cheese) {
        catDAONFT = mint_CatDAO(_catDAONFT);
        CHEESE = Cheese(_Cheese);
    }

    /** STAKING */

    /**
    * adds Sheep and Wolves to the Barn and Pack
    * @param account the address of the staker
    * @param tokenIds the IDs of the Sheep and Wolves to stake
    */

    function addManyToBarnAndPack(address account, uint16[] calldata tokenIds) external {
        require(account == _msgSender() || _msgSender() == address(catDAONFT), "DONT GIVE YOUR TOKENS AWAY");
        for (uint i = 0; i < tokenIds.length; i++) {
            if (_msgSender() != address(catDAONFT)) {// dont do this step if its a mint + stake
                require(catDAONFT.ownerOf(tokenIds[i]) == _msgSender(), "AINT YO TOKEN");
                catDAONFT.transferFrom(_msgSender(), address(this), tokenIds[i]);
            } else if (tokenIds[i] == 0) {
                continue;
                // there may be gaps in the array for stolen tokens
            }
            if (!catDAONFT.isCat(tokenIds[i]))
                _addSheepToBarn(account, tokenIds[i]);
            else
                _addWolfToPack(account, tokenIds[i]);
        }

    }

    /**
    * adds a single Sheep to the Barn
    * @param account the address of the staker
    * @param tokenId the ID of the Sheep to add to the Barn
    */

    function _addSheepToBarn(address account, uint256 tokenId) internal whenNotPaused _updateEarnings {
        barn[tokenId] = Stake({
            owner : account,
            tokenId : uint16(tokenId),
            value : uint80(block.timestamp)
        });
        fridge[account].push(tokenId);
        totalSheepStaked += 1;
        emit TokenStaked(account, tokenId, block.timestamp, false);
    }

    /**
    * adds a single Wolf to the Pack
    * @param account the address of the staker
    * @param tokenId the ID of the Wolf to add to the Pack
    */

    function _addWolfToPack(address account, uint256 tokenId) internal {
        uint256 alpha = _alphaForWolf();

        totalAlphaStaked += alpha;
        // Portion of earnings ranges from 8 to 5
        packIndices[tokenId] = pack[alpha].length;
        // Store the location of the wolf in the Pack
        pack[alpha].push(Stake({
            owner : account,
            tokenId : uint16(tokenId),
            value : uint80(woolPerAlpha)
        }));
        catpack[account].push(tokenId);
        // Add the wolf to the Pack
        emit TokenStaked(account, tokenId, woolPerAlpha, true);
    }

    /** CLAIMING / UNSTAKING */
    /**
    * realize $WOOL earnings and optionally unstake tokens from the Barn / Pack
    * to unstake a Sheep it will require it has 2 days worth of $WOOL unclaimed
    * @param tokenIds the IDs of the tokens to claim earnings from
    * @param unstake whether or not to unstake ALL of the tokens listed in tokenIds
    */

    function claimManyFromBarnAndPack(uint16[] calldata tokenIds, bool unstake) external whenNotPaused _updateEarnings {
        uint256 owed = 0;
        for (uint i = 0; i < tokenIds.length; i++) {
            if (!catDAONFT.isCat(tokenIds[i]))
                owed += _claimSheepFromBarn(tokenIds[i], unstake);
            else
                owed += _claimWolfFromPack(tokenIds[i], unstake);
        }

        if (owed == 0) return;
        catDAONFT.rewardStake(owed);
        CHEESE.transfer(_msgSender(),owed);
    }

    /**
    * realize $WOOL earnings for a single Sheep and optionally unstake it
    * if not unstaking, pay a 20% tax to the staked Wolves
    * if unstaking, there is a 50% chance all $WOOL is stolen
    * @param tokenId the ID of the Sheep to claim earnings from
    * @param unstake whether or not to unstake the Sheep
    * @return owed - the amount of $WOOL earned
    */

    function _claimSheepFromBarn(uint256 tokenId, bool unstake) internal returns (uint256 owed) {
        Stake memory stake = barn[tokenId];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        require(!(unstake && block.timestamp - stake.value < MINIMUM_TO_EXIT), "GONNA BE COLD WITHOUT TWO DAY'S WOOL");
        if (totalWoolEarned < MAXIMUM_GLOBAL_WOOL) {
            owed = (block.timestamp - stake.value) * DAILY_WOOL_RATE / 1 days;
        } else if (stake.value > lastClaimTimestamp) {
            owed = 0;
            // $WOOL production stopped already
        } else {
            owed = (lastClaimTimestamp - stake.value) * DAILY_WOOL_RATE / 1 days;
            // stop earning additional $WOOL if it's all been earned
        }

        if (unstake) {
            if (random(tokenId) & 1 == 1) {// 50% chance of all $WOOL stolen
                _payWolfTax(owed);
                owed = 0;
            }
            catDAONFT.safeTransferFrom(address(this), _msgSender(), tokenId, "");
            // send back Sheep

            delete barn[tokenId];
            totalSheepStaked -= 1;
            for(uint index=0;index<fridge[_msgSender()].length;index++){
                if(fridge[_msgSender()][index]==tokenId){
                    fridge[_msgSender()][index] = 0;
                }
            }

        } else {
            _payWolfTax(owed * WOOL_CLAIM_TAX_PERCENTAGE / 100);
            // percentage tax to staked wolves
            owed = owed * (100 - WOOL_CLAIM_TAX_PERCENTAGE) / 100;
            // remainder goes to Sheep owner
            barn[tokenId] = Stake({
                owner : _msgSender(),
                tokenId : uint16(tokenId),
                value : uint80(block.timestamp)
            });
            // reset stake
        }

        emit SheepClaimed(tokenId, owed, unstake);
    }

    /**
    * get mouse balance
    */
    function fridgeLengthOf(address owner) public view returns(uint256) {
        return fridge[owner].length;
    }

    /**
    * get cat balance
    */
    function catPackLengthOf(address owner) public view returns(uint256){
        return catpack[owner].length;
    }

    function mouseOfOwnerByIndex(address owner, uint256 index) public view returns (uint256 tokenId){
        return fridge[owner][index];
    }

    function catOfOwnerByIndex(address owner, uint256 index) public view returns (uint256 tokenId){
        return catpack[owner][index];
    }

    /**
    * realize $WOOL earnings for a single Wolf and optionally unstake it
    * Wolves earn $WOOL proportional to their Alpha rank
    * @param tokenId the ID of the Wolf to claim earnings from
    * @param unstake whether or not to unstake the Wolf
    * @return owed - the amount of $WOOL earned
    */

    function _claimWolfFromPack(uint256 tokenId, bool unstake) internal returns (uint256 owed) {
        require(catDAONFT.ownerOf(tokenId) == address(this), "AINT A PART OF THE PACK");
        uint256 alpha = _alphaForWolf();
        Stake memory stake = pack[alpha][packIndices[tokenId]];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        owed = (alpha) * (woolPerAlpha - stake.value);
        // Calculate portion of tokens based on Alpha
        if (unstake) {
            totalAlphaStaked -= alpha;
            // Remove Alpha from total staked
            catDAONFT.safeTransferFrom(address(this), _msgSender(), tokenId, "");
            // Send back Wolf
            Stake memory lastStake = pack[alpha][pack[alpha].length - 1];
            pack[alpha][packIndices[tokenId]] = lastStake;
            // Shuffle last Wolf to current position
            packIndices[lastStake.tokenId] = packIndices[tokenId];
            pack[alpha].pop();
            for(uint index=0;index<catpack[_msgSender()].length;index++){
                if(catpack[_msgSender()][index]==tokenId){
                    catpack[_msgSender()][index] = 0;
                }
            }
            // Remove duplicate
            delete packIndices[tokenId];
            // Delete old mapping
        } else {
            pack[alpha][packIndices[tokenId]] = Stake({
                owner : _msgSender(),
                tokenId : uint16(tokenId),
                value : uint80(woolPerAlpha)
            });
            // reset stake
        }

        emit WolfClaimed(tokenId, owed, unstake);
    }

    /**
    * emergency unstake tokens
    * @param tokenIds the IDs of the tokens to claim earnings from
    */

    function rescue(uint256[] calldata tokenIds) external {
        require(rescueEnabled, "RESCUE DISABLED");
        uint256 tokenId;
        Stake memory stake;
        Stake memory lastStake;
        uint256 alpha;
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            if (!catDAONFT.isCat(tokenId)) {
                stake = barn[tokenId];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                catDAONFT.safeTransferFrom(address(this), _msgSender(), tokenId, "");
                // send back Sheep
                delete barn[tokenId];
                totalSheepStaked -= 1;
                emit SheepClaimed(tokenId, 0, true);
            } else {
                alpha = _alphaForWolf();
                stake = pack[alpha][packIndices[tokenId]];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                totalAlphaStaked -= alpha;
                // Remove Alpha from total staked
                catDAONFT.safeTransferFrom(address(this), _msgSender(), tokenId, "");
                // Send back Wolf
                lastStake = pack[alpha][pack[alpha].length - 1];
                pack[alpha][packIndices[tokenId]] = lastStake;
                // Shuffle last Wolf to current position
                packIndices[lastStake.tokenId] = packIndices[tokenId];
                pack[alpha].pop();
                // Remove duplicate
                delete packIndices[tokenId];
                // Delete old mapping
                emit WolfClaimed(tokenId, 0, true);
            }
        }
    }

    /** Airdrop */
    function airDrop(uint256 _tokenId) public{
        require(catDAONFT.ownerOf(_tokenId)==_msgSender(),"Wrong nft owner");
        uint256 dropAmount = Drop.calculateDropAmount(_tokenId);
        catDAONFT.rewardStake(dropAmount);        
        CHEESE.transfer(_msgSender(),dropAmount);
    }

    function setDropRule(IDrop dropContract) public onlyOwner{
        Drop = dropContract;
    }

    /** ACCOUNTING */
    /**
    * add $WOOL to claimable pot for the Pack
    * @param amount $WOOL to add to the pot
    */

    function _payWolfTax(uint256 amount) internal {
        if (totalAlphaStaked == 0) {// if there's no staked wolves
            unaccountedRewards += amount;
            // keep track of $WOOL due to wolves
            return;
        }

        // makes sure to include any unaccounted $WOOL
        woolPerAlpha += (amount + unaccountedRewards) / totalAlphaStaked;
        unaccountedRewards = 0;
    }

    /**
    * tracks $WOOL earnings to ensure it stops once 2.4 billion is eclipsed
    */

    modifier _updateEarnings() {
        if (totalWoolEarned < MAXIMUM_GLOBAL_WOOL) {
            totalWoolEarned += (block.timestamp - lastClaimTimestamp) * totalSheepStaked * DAILY_WOOL_RATE / 1 days;
            lastClaimTimestamp = block.timestamp;
        }
        _;
    }

    /** ADMIN */

    /**
    * allows owner to enable "rescue mode"
    * simplifies accounting, prioritizes tokens out in emergency
    */

    function setRescueEnabled(bool _enabled) external onlyOwner {
        rescueEnabled = _enabled;
    }

    /**
    * enables owner to pause / unpause minting
    */

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    /** READ ONLY */

    function _alphaForWolf() public pure returns (uint8) {
        return MAX_ALPHA - 5;
        // alpha index is 0-3
    }

    /**
    * chooses a random Wolf thief when a newly minted token is stole
    * @param seed a random value to choose a Wolf from
    * @return the owner of the randomly selected Wolf thief
    */

    function randomWolfOwner(uint256 seed) external view returns (address) {
        if (totalAlphaStaked == 0) return address(0x0);
        uint256 bucket = (seed & 0xFFFFFFFF) % totalAlphaStaked;
        // choose a value from 0 to total alpha staked
        uint256 cumulative;
        seed >>= 32;
        // loop through each bucket of Wolves with the same alpha score
        for (uint i = MAX_ALPHA - 3; i <= MAX_ALPHA; i++) {
            cumulative += pack[i].length * i;
            // if the value is not inside of that bucket, keep going
            if (bucket >= cumulative) continue;
            // get the address of a random Wolf with that alpha score
            return pack[i][seed % pack[i].length].owner;
        }
        return address(0x0);
    }

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

    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send tokens to Barn directly");
        return IERC721Receiver.onERC721Received.selector;
    }

}

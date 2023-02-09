// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.17;
// @author eXplorins (Cristian Richarte Gil)
// @title NanoStore 3D printable NFT collections

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";

interface INFT3D{
    function printNFT(
        uint _nFTCollection, 
        uint _amount, 
        uint _size, 
        uint _printingFee, 
        address _printStore) external returns(bool);
    function mintNFT(uint _amount, string memory _uri) external payable returns(bool);
    function updateURI(uint _nfTCollection, string memory _newURI) external returns(bool);
    function checkStorePermission(uint _nFTCollection) external view returns(bool);
}

contract NanoStore is IERC1155, ERC1155, ERC1155URIStorage{

    // NFT Collection Struct to store all the NFT details.
    struct Collection {
        // NFT collection address.
        address creator;
        // Amount of NFTs created for a Colection Example. 10 Nike shoes of Collection 10.
        uint nFTsMinted;
        // Amount of NFTs remaining to be burned.
        uint nFTsRemainingBurn;
        // Fee that will be transfered to the creator after sending to print the NFT. (Wei)
        uint creatorFee;
    }

    // Owner Address
    address public nanoStore;
    // 1st NFT collection will be number 1 by default.
    uint public nFTcount;
    // Fee for minting an NFT collection.
    uint public mintingFee;
    // Fee for burning an NFT collection.
    uint public burningFee;

    // NFTidCollection -> Collection struct
    mapping(uint => Collection) public CollectionIndex;
    // NFTidCollection -> Request URI -> owner or creator -> Accepted.
    mapping(uint => mapping(string => mapping(address => bool))) private changeURIRequest;
    // Creator address => array of his NFT Collections ID.
    mapping(address => uint[]) public collectionsPerAddress;
    // 3DPrintStore => NFTidCollection => If the Store was selected to print that NFTCollection
    mapping(address => mapping(uint => bool)) private storeSelected;
    // 3DPrintStore => If the address is a real Store
    mapping(address => bool) public isStore3D;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event NFT3DBurned(address indexed owner, uint nFTCollection, uint size, address printStore, uint burningTime);
    event NFTMinted(address indexed owner, 
    uint nFTCollection, 
    uint numberCollectionsCreator, 
    uint amount, 
    uint creatorFee, 
    uint mintingTime);
    event BaseURIUpdated(string baseURI,uint updateTime);
    event MintingFeeUpdated(uint newMintingFee, uint updateTime); 
    event BurningFeeUpdated(uint newBurningFee, uint updateTime); 
    event NewCreator(address indexed creator, uint firstCreationTime);
    event FoundsWithdrawn(address indexed owner, uint ethersWithdrawn, uint withdrawnTime);
    event UriUpdateRequested(address indexed solicitant, uint nFTCollection, string newURI, uint updateTime);
    event UriUpdated(address indexed approver, uint nFTCollection, string newURI, uint updateTime);


    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(nanoStore == msg.sender, "You`r not the owner");
        _;
    }

    constructor(string memory _baseURI) ERC1155(_baseURI){
        _setBaseURI(_baseURI);
        nanoStore = msg.sender;
    }

    /**
     * @dev Minting function. It will set the URI & NFT Collection details.
     * @param _amount: Total amount of NFTs we want to mint. (Same NFT Collection)
     * @param _uri: Uri we want to set as the default TOKEN URI when burned.
     * @param _creatorFee: Fee for the creator when burning his NFT.
     */
    function mintNFT(uint _amount, string memory _uri, uint _creatorFee) external payable returns(bool){
        require(msg.value >= mintingFee, "You need to pay Minting Fee");    
        require(bytes(_uri).length > 0, "Add a Token URI");
        payable(address(this)).transfer(msg.value);
        nFTcount++;
        _mint(msg.sender, nFTcount, _amount, "");
        Collection memory newCollection;
        newCollection.nFTsMinted = _amount;
        newCollection.nFTsRemainingBurn = _amount;
        newCollection.creator = msg.sender;
        newCollection.creatorFee = _creatorFee;
        CollectionIndex[nFTcount] = newCollection;
        collectionsPerAddress[msg.sender].push(nFTcount);
        _setURI(nFTcount, _uri);
        
        emit NFTMinted(msg.sender, 
        nFTcount, 
        collectionsPerAddress[msg.sender].length, 
        _amount, 
        _creatorFee, 
        block.timestamp);
        return true;
    }

    /**
     * @dev Burning function to burn the token, pays the fee for the burining to the NanoStore(Burning Fee %), 
     *                PrintStore3D(Remaining Fee%) & stablished PrintingFee for the creator.
     *      If the owner chooses more than 1 NFT, They will be printed under the same conditions.
     *      The print store 3D will have access STL file, after the function is compleated.
     * @param _nFTCollection: NFT Collection Identifier.
     * @param _amount: Total amount of NFTs we want to print. (Same NFT Collection)
     * @param _size: Desirable size for the NFT printed.
     * @param _printingFee: Printing Fee stablished for 3D Printer Store + CreatorFee + NanoStoreFee.
     *          PrintingFee =   BurningFee (Fee for NanoStore)  
     *                        + CreatorFee (Fee for Creator)
     *                        + PrintingStore Fee (3D PrinterStore, value managed from Front End).
     * @param _printStore: Print store where we want to print the NFT.

     - Example: 
     1000000000000000000 BurningFee (Stored in the contract)
     1000000000000000000 CreatorFee (Stored in the contract)
     1000000000000000000 Printing Price for PrinterStore3D (Added from the font after checking the printing measures)
     --------------
     3000000000000000000 Total Weis sent when printing.
     */
    function printNFT(
        uint _nFTCollection, 
        uint _amount, 
        uint _size, 
        uint _printingFee, 
        address _printStore
        ) external payable returns(bool){
        Collection memory NFTDetails = CollectionIndex[_nFTCollection];
        // Requirement for 3DStore Fee, NanoStore Fee & Creator Fee.
        require(msg.value >= burningFee + NFTDetails.creatorFee, "Pay more printingFee");
        require(isStore3D[_printStore], "Choose another 3DPrintStore");
        require(_nFTCollection != 0 && nFTcount >= _nFTCollection, "Wrong NFT Collection");
        _burn(msg.sender, _nFTCollection, _amount);
        CollectionIndex[_nFTCollection].nFTsRemainingBurn -= _amount;
        storeSelected[_printStore][_nFTCollection] = true;
        payable(NFTDetails.creator).transfer(NFTDetails.creatorFee); // Fee stablished by the Creator
        payable(address(this)).transfer(burningFee); // Burning Fee for NanoStore.
        payable(_printStore).transfer((_printingFee) - (NFTDetails.creatorFee + burningFee)); // Printing price for 3D Printer Store

        emit NFT3DBurned(msg.sender, _nFTCollection, _size, _printStore, block.timestamp);
        return true;
    }

    /**
     * @dev Toggle function to allow the Store 3D for being elegible to print or revoke elegibility to each address.
     * @param _printStores: PrintStore3D addresses.
     * @param _access: Result for the elegibility of the 3D Print Store.
     */
    function store3DElegible(address[] memory _printStores, bool _access) external onlyOwner returns(bool){
        for(uint i; i < _printStores.length; i++){
            isStore3D[_printStores[i]] = _access;
        }
        return true;
    }

    /**
     * @dev Withdrawn function to extract from the contract the Fees paid for minting 3D NFts.
     * @param _amount: Amount in Ethers choosen to withdrawn.
     * @param _to: Who the funds will be transfer to.
     */
    function withdrawnFunds(uint _amount, address _to) external onlyOwner returns(bool) {
        require(_to != address(0), "Address cannot be 0");
        payable(_to).transfer(_amount);

        emit FoundsWithdrawn(msg.sender, _amount, block.timestamp);
        return true;
    }

    /**
     * @dev Setter for new URI. It needs the agreement of the contract Owner & NFT Creator.
     * @param _nFTCollection: NFT Collection Identifier.
     * @param _newURI: New URI we want to update for the NFT Collection ID.
     */
    function updateURI(uint _nFTCollection, string memory _newURI) external returns(bool) {
        require(nanoStore == msg.sender || 
        CollectionIndex[_nFTCollection].creator == msg.sender, "You can`t update URI");
        require(!changeURIRequest[_nFTCollection][_newURI][msg.sender], "You already approved");
        changeURIRequest[_nFTCollection][_newURI][msg.sender] = true;
        if(changeURIRequest[_nFTCollection][_newURI][nanoStore] 
        && changeURIRequest[_nFTCollection][_newURI][CollectionIndex[_nFTCollection].creator]) {
            _setURI(_nFTCollection, _newURI);

            emit UriUpdated(msg.sender, _nFTCollection, _newURI, block.timestamp);
        }else  {
            emit UriUpdateRequested(msg.sender, _nFTCollection, _newURI, block.timestamp);
        }

        return true;
    }

    /**
     * @dev Setter for the Minting fee the creator needs to pay per collection
     * @param _newMintingFee: New Fee to set.
     */
    function updateMintFee(uint _newMintingFee) external onlyOwner returns(bool){
        mintingFee = _newMintingFee;
        emit MintingFeeUpdated(_newMintingFee, block.timestamp);
        return true;
    }

    /**
     * @dev Setter for the Burning fee the user needs to pay for sending to print (Burning)
     * @param _newBurningFee: New Fee to set. The number should be from 1 to 100. 
     *                        The remaining to 100 will be the % for the printing Store.
     */
    function updateBurningFee(uint _newBurningFee) external onlyOwner returns(bool){
        burningFee = _newBurningFee;
        emit BurningFeeUpdated(_newBurningFee, block.timestamp);
        return true;
    }

    /**
     * @dev Setter function for updating the BASE URI.
     * @param _baseURI: New URI to Set.
     */
    function updateBaseURI(string memory _baseURI) public onlyOwner returns(bool){
        _setBaseURI(_baseURI);
        emit BaseURIUpdated(_baseURI, block.timestamp);
        return true;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     *      Can only be called by the current owner.
     * @param newOwner: New Owner address to set.
     */
    function transferOwnership(address payable newOwner) external onlyOwner returns(bool){
        require(newOwner != address(0), "New owner is the zero address");
        address oldOwner = nanoStore;
        nanoStore = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
        return true;
    }

    /**
     * @dev Getter to check if the msg.sender has permissions to see the password to encrypt the URI.
     * @param _nFTCollection: NFT Collection Identifier.
     */
    function checkStorePermission(uint _nFTCollection) external view returns(bool){
        require(storeSelected[msg.sender][_nFTCollection], "You are not elegible to print this NFTID");
        return true;
    }

    /**
     * @dev Getter for the BASE URI & TOKEN URI concatenated.
     * @param _nFTCollection: NFT Collection Identifier.
     *
     * This enables the following behaviors:
     *
     * - if `_tokenURIs[tokenId]` is set, then the result is the concatenation
     *   of `_baseURI` and `_tokenURIs[tokenId]` (keep in mind that `_baseURI`
     *   is empty per default);
     *
     * - if `_tokenURIs[tokenId]` is NOT set then we fallback to `super.uri()`
     *   which in most cases will contain `ERC1155._uri`;
     *
     * - if `_tokenURIs[tokenId]` is NOT set, and if the parents do not have a
     *   uri value set, then the result is empty.
     */   
    function uri(uint256 _nFTCollection) public view override(ERC1155, ERC1155URIStorage) returns (string memory) {
        require(_nFTCollection != 0 && nFTcount >= _nFTCollection, "Wrong NFT Collection");
        return ERC1155URIStorage.uri(_nFTCollection);
    }

    // Receive function to receive funds in the contract.
    receive() external payable {}
}

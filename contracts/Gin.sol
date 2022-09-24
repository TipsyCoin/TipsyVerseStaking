// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "./Solmate_modified.sol";
import "./OwnableKeepable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
//import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Gin is SolMateERC20, Ownable, Pausable, Initializable
{
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ChainSupport(uint indexed chainId, bool indexed supported);
    event ContractPermission(address indexed contractAddress, bool indexed permitted);
    event SignerPermission(address indexed signerAddress, bool indexed permitted);
    event RequiredSigs(uint8 indexed oldAmount, uint8 indexed newAmount);
    event Deposit(address indexed from, uint256 indexed amount, uint256 indexed chainId);
    event Withdrawal(address indexed to, uint256 indexed amount, bytes32 indexed depositID);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(uint256 => bool) public supportedChains;
    address constant DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);
    uint8 public requiredSigs;

    /*//////////////////////////////////////////////////////////////
                                INITILALIZATION
    //////////////////////////////////////////////////////////////*/

    //Testing Only
    function _testInit() external {
        initialize(msg.sender, msg.sender, address(this));
        permitSigner(address(msg.sender));
        permitSigner(address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf));//this is the address for the 0x000...1 priv key
        permitSigner(address(0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF));//this is the address for the 0x000...2 priv key
    }

    //Test initialize function only
    function initialize(address owner_, address _keeper, address _stakingContract) public initializer {
            require(decimals == 18, "Tipsy: Const check DECIMALS");
            require(keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("Gin")), "Tipsy: Const NAME");
            require(keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("$gin")), "Tipsy: Const SYMBOL");
            require(MIN_SIGS == 2, "Tipsy: Const check SIGS");
            require(_keeper != address(0), "Tipsy: keeper can't be 0 address");
            require(owner_ != address(0), "Tipsy: owner can't be 0 address");
            keeper = _keeper;
            initOwnership(owner_);
            //Owner will be gnosis safe multisig
            INITIAL_CHAIN_ID = block.chainid;
            INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
            setRequiredSigs(MIN_SIGS);
            permitContract(_stakingContract);
    }

    /*//////////////////////////////////////////////////////////////
                                TESTING ONLY
    //////////////////////////////////////////////////////////////*/

    function chainId() public view returns (uint) {
        return block.chainid;
    }

    function return_max() public pure returns (uint256) {
        return ~uint256(0);
    }

    function _keccakInner() public pure returns (bytes32) {
        address minter = address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf);
        address to = address(0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF);
        uint256 amount = 1e18;
        uint256 nonce = 0;
        uint256 deadline = ~uint256(0);

        bytes32 returnVal =     keccak256(
                                abi.encode(
                                    keccak256(
                                        "multisigMint(address minter,address to,uint256 amount,uint256 nonce,uint256 deadline,bytes signatures)"
                                    ),
                                    minter,
                                    to,
                                    amount,
                                    nonce,
                                    deadline
                                )
                            );
        return returnVal;
    }

    function _keccakCheckak() external view returns (bytes32) {
        address minter = address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf);
        address to = address(0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF);
        uint256 amount = 1e18;
        uint256 deadline = ~uint256(0);

        bytes32 returnVal =
        keccak256(
                        abi.encodePacked(
                            "\x19\x01",
                            DOMAIN_SEPARATOR(),
                            keccak256(
                                abi.encode(
                                    keccak256(
                                        "multisigMint(address minter,address to,uint256 amount,uint256 nonce,uint256 deadline,bytes signatures)"
                                    ),
                                    minter,
                                    to,
                                    amount,
                                    nonces[minter],
                                    deadline
                                )
                            )
                        ));

    return returnVal;

    }

    //Test function, remove before launch.
    function testMint(address _to, uint256 _amount) public returns (bool) {
        _mint(_to, _amount);
        emit Mint(msg.sender, _to, _amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                PRIVILAGED
    //////////////////////////////////////////////////////////////*/

    function permitContract(address _newSigner) public onlyOwner returns (bool) {
        emit ContractPermission(_newSigner, true);
        return _addContractMinter(_newSigner);
    }

    function permitSigner(address _newSigner) public onlyOwner returns (bool) {
        emit SignerPermission(_newSigner, true);
        return _addMintSigner(_newSigner);
    }

    function revokeSigner(address _newSigner) public onlyOwnerOrKeeper returns (bool) {
        emit SignerPermission(_newSigner, false);
        return _removeMintSigner(_newSigner);
    }
    //This one is only owner, because it could break Tipsystake.
    function revokeContract(address _newSigner) public onlyOwner returns (bool) {
        emit ContractPermission(_newSigner, false);
        return _removeContractMinter(_newSigner);
    }

    function setRequiredSigs(uint8 _numberSigs) public onlyOwner returns (uint8) {
        require(_numberSigs >= MIN_SIGS, "SIGS_BELOW_MINIMUM");
        emit RequiredSigs(requiredSigs, _numberSigs);
        requiredSigs = _numberSigs;
        return _numberSigs;
    }

    function setSupportedChain(uint256 _chainId, bool _supported) external onlyOwnerOrKeeper returns(uint256, bool) {
        require(_chainId != block.chainid, "TO_FROM_CHAIN_IDENTICTAL");
        supportedChains[_chainId] = _supported;
        emit ChainSupport(_chainId, _supported);
        return (_chainId, _supported);
    }

    function setPause(bool _paused) external onlyOwnerOrKeeper {
        if (_paused == true) _pause();
        else _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                TIPSYSTAKE INTEGRATION
    //////////////////////////////////////////////////////////////*/
    function mintTo(address _to, uint256 _amount) public whenNotPaused returns (bool) {
        require(contractMinters[msg.sender] == true, "MINTTO_FOR_TIPSYSTAKE_CONTRACTS_ONLY");
        _mint(_to, _amount);
        emit Mint(msg.sender, _to, _amount);
        return true; //return bool required for our staking contract to function
    }

    /*//////////////////////////////////////////////////////////////
                                BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    //Deposit from address to the given chainId. Our bridge will pick the Deposit event up and MultisigMint on the associated chain
    //Checks to ensure chainId is supported (ensure revent when no supported chainIds before bridge is live)
    //Does a standard transferFrom to ensure user approves this contract first. (Prevent accidental deposit, since this method is destructive to tokens)
    function deposit(uint256 _amount, uint256 _chainId) external whenNotPaused returns (bool) {
        require(supportedChains[_chainId], "CHAIN_NOTYET_SUPPORTED");
        require(transferFrom(msg.sender, address(this), _amount), "DEPOSIT_FAILED_CHECK_BAL_APPROVE");
        _burn(address(this), _amount);
        emit Deposit(msg.sender, _amount, _chainId);
        return true;
    }

    //MultiSig Mint. Used so server/bridge can sign messages off-chain, and transmit via relay network
    //Also used by the game. So tokens can be minted from the game without them paying gas
    function multisigMint(address minter, address to, uint256 amount, uint256 deadline, bytes32 _depositHash, bytes memory signatures) external whenNotPaused returns(bool) {
        require(deadline >= block.timestamp, "MINT_DEADLINE_EXPIRED");
        require(requiredSigs >= MIN_SIGS, "REQUIRED_SIGS_TOO_LOW");
        bytes32 dataHash;
        dataHash =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "multisigMint(address minter,address to,uint256 amount,uint256 nonce,uint256 deadline,bytes signatures)"
                            ),
                            minter,
                            to,
                            amount,
                            nonces[minter]++,
                            deadline
                        )
                    )
                )
            );
        checkNSignatures(minter, dataHash, requiredSigs, signatures);
        _mint(to, amount);
        emit Withdrawal(to, amount, _depositHash);
        return true;
    }

//Manual testing to ensure Python server is doing things exactly the same way
//Much sadness has been had because of the different encoding of abi.encode and abi.encodePacked
//abi.encode should be used to avoid tx malleability attacks, though
//e.g. the keccak256 using encodePacked for nonce 1 and deadline 123 might be similiar to nonce 11 and deadline 23. This is obviously bad.
    function _verifyEIPMint(address minter, address to, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public view returns (address) {
        require(deadline >= block.timestamp, "Tipsy: Mint Deadline Expired");
        require(mintSigners[minter] == true, "Tipsy: Not Authorized to Mint");
        require(contractMinters[minter] == false, "Tipsy: Contract use mintTo instead");
        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "eipMint(address minter,address to,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                minter,
                                to,
                                amount,
                                nonces[to],
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            return recoveredAddress;
    }
}

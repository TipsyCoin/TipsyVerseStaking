// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Gin (https://github.com/TipsyCoin/TipsyGin/), modified from Solmate
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @author CheckNSignature function and SplitsSigs from Gnosis Safe. (https://github.com/safe-global/safe-contracts/blob/main/contracts/GnosisSafe.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
/// In the interests of general openness, we prefer vars that are safe to be made public, are

abstract contract SolMateERC20 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, address indexed from, uint256 amount);
    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/
    string public constant name = "Gin";
    string public constant symbol = "$gin";
    uint8 public constant decimals = 18;
    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 internal INITIAL_CHAIN_ID;
    //These can't be immutable in upgradeable proxy pattern
    //We also want to reuse contract address accross multiple chain ...
    //So deployed bytecode must be identical == can't do consts for init chain id, etc
    bytes32 public INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;
    /*//////////////////////////////////////////////////////////////
                            GIN EXTRA
    //////////////////////////////////////////////////////////////*/
    mapping(address => bool) public mintSigners;
    mapping(address => bool) public contractMinters;
    uint8 public constant MIN_SIGS = 2;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    //Changed to initialize for upgrade purposes.

    /*//////////////////////////////////////////////////////////////
                             EXTRA GIN STUFF
    //////////////////////////////////////////////////////////////*/
    function _addContractMinter(address _newSigner) internal virtual returns (bool) {
        //require (msg.sender == address(this), "Only internal calls, please"); 
        uint size;
        assembly {
            size := extcodesize(_newSigner)
        }
        require(size > 0, "CONTRACTMINTER_NOT_CONTRACT");
        contractMinters[_newSigner] = true;
        return true;
    }

    function _removeContractMinter(address _removedSigner) internal virtual returns (bool) {
        contractMinters[_removedSigner] = false;
        return true;
    }

        function _addMintSigner(address _newSigner) internal virtual returns (bool) {
        //require (msg.sender == address(this), "Only internal calls, please"); 
        uint size;
        assembly {
            size := extcodesize(_newSigner)
        }
        require(size == 0, "SIGNER_NOT_EOA");
        mintSigners[_newSigner] = true;
        return true;
    }

    function _removeMintSigner(address _removedSigner) internal virtual returns (bool) {
        mintSigners[_removedSigner] = false;
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            GNOSIS-SAFE MULTISIG CHECK
                            Modified from here:
    (https://github.com/safe-global/safe-contracts/blob/main/contracts/GnosisSafe.sol)
    //////////////////////////////////////////////////////////////*/
    function checkNSignatures(address minter, bytes32 dataHash, uint8 _requiredSigs, bytes memory signatures) public view returns (bool) {
        // Check that the provided signature data is not too short
        require(signatures.length == _requiredSigs * 65, "SIG_LENGTH_COUNT_MISMATCH");
        // There cannot be an owner with address 0.
        address lastOwner = address(0);
        address currentOwner;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 i;
        uint8 minterCount = 0;

        for (i = 0; i < _requiredSigs; i++) {
            //Split the bytes into signature data. v is only 1 byte long. r and s are 32 bytes
            (v, r, s) = signatureSplit(signatures, i);
            require (v == 27 || v == 28, "ZIPD_OR_CONTRACT_KEY_UNSUPPORTED");
            currentOwner = ecrecover(dataHash, v, r, s);
            //Keys must be supplied in increasing public key order. Gas savings.
            require(currentOwner != address(0) && currentOwner > lastOwner && mintSigners[currentOwner] == true, "SIG_CHECK_FAILED");

            if (currentOwner == minter){
                minterCount++;
                }
            lastOwner = currentOwner;
            }

        require(minterCount == 1, "MINTER_NOT_IN_SIG_SET");
        return true;
        }

    /// @dev divides bytes signature into `uint8 v, bytes32 r, bytes32 s`.
    /// @notice Make sure to peform a bounds check for @param pos, to avoid out of bounds access on @param signatures
    /// @param pos which signature to read. A prior bounds check of this parameter should be performed, to avoid out of bounds access
    /// @param signatures concatenated rsv signatures
    /// Sourced from here: https://github.com/safe-global/safe-contracts/blob/main/contracts/GnosisSafe.sol
    function signatureSplit(bytes memory signatures, uint256 pos) internal pure returns
            (uint8 v,
            bytes32 r,
            bytes32 s) {
        // The signature format is a compact form of:
        //   {bytes32 r}{bytes32 s}{uint8 v}
        // Compact means, uint8 is not padded to 32 bytes.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let signaturePos := mul(0x41, pos)
            r := mload(add(signatures, add(signaturePos, 0x20)))
            s := mload(add(signatures, add(signaturePos, 0x40)))
            // Here we are loading the last 32 bytes, including 31 bytes
            // of 's'. There is no 'mload8' to do this.
            //
            // 'byte' is not working due to the Solidity parser, so lets
            // use the second best option, 'and'
            v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
        }
    }


    /*//////////////////////////////////////////////////////////////
                             EIP-2612 BASED MINT LOGIC
    //////////////////////////////////////////////////////////////*/
    function eipMint(address minter, address to, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public virtual {

        require(deadline >= block.timestamp, "MINT_DEADLINE_EXPIRED");
        require(mintSigners[minter] == true, "NOT_AUTHORIZED_TO_MINT");
        require(contractMinters[minter] == false, "USE_CONTRACT_MINT_INSTEAD");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
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
                                nonces[minter]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            require(recoveredAddress != address(0) && recoveredAddress == minter, "INVALID_SIGNER");
        }
        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 PERMIT
    //////////////////////////////////////////////////////////////*/

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");
        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");
            allowance[recoveredAddress][spender] = value;
        }
        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() public view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}

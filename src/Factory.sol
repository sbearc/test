// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {AccountProxy} from "src/AccountProxy.sol";
import {IFactory} from "src/interfaces/IFactory.sol";
import {Owned} from "src/utils/Owned.sol";

/// @notice factory for creating smart margin accounts
/// @dev the factory acts as a beacon for the proxy {AccountProxy.sol} contract(s)
contract Factory is IFactory, Owned {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    bool public canUpgrade = true;

    /// @inheritdoc IFactory
    address public implementation;

    /// @inheritdoc IFactory
    mapping(address accounts => bool exist) public accounts;

    /// @notice mapping of owner to accounts owned by owner
    mapping(address owner => address[] accounts) internal ownerAccounts;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructor for factory that sets owner
    /// @param _owner: owner of factory
    constructor(address _owner) Owned(_owner) {}

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function getAccountOwner(address _account)
        public
        view
        override
        returns (address)
    {
        // ensure account is registered
        if (!accounts[_account]) revert AccountDoesNotExist();

        // fetch owner from account
        (bool success, bytes memory data) =
            _account.staticcall(abi.encodeWithSignature("owner()"));
        assert(success); // should never fail (account is a contract)

        return abi.decode(data, (address));
    }

    /// @inheritdoc IFactory
    function getAccountsOwnedBy(address _owner)
        external
        view
        override
        returns (address[] memory)
    {
        return ownerAccounts[_owner];
    }

    /*//////////////////////////////////////////////////////////////
                               OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function updateAccountOwnership(address _newOwner, address _oldOwner)
        external
        override
    {
        // ensure account is registered by factory
        if (!accounts[msg.sender]) revert AccountDoesNotExist();

        // store length of ownerAccounts array in memory
        uint256 length = ownerAccounts[_oldOwner].length;

        for (uint256 i = 0; i < length;) {
            if (ownerAccounts[_oldOwner][i] == msg.sender) {
                // remove account from ownerAccounts mapping for old owner
                ownerAccounts[_oldOwner][i] =
                    ownerAccounts[_oldOwner][length - 1];
                ownerAccounts[_oldOwner].pop();

                // add account to ownerAccounts mapping for new owner
                ownerAccounts[_newOwner].push(msg.sender);

                return;
            }

            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function newAccount()
        external
        override
        returns (address payable accountAddress)
    {
        // create account and set beacon to this address (i.e. factory address)
        accountAddress = payable(address(new AccountProxy(address(this))));

        // add account to accounts mapping
        accounts[accountAddress] = true;

        // add account to ownerAccounts mapping
        ownerAccounts[msg.sender].push(accountAddress);

        // set owner of account to caller
        (bool success, bytes memory data) = accountAddress.call(
            abi.encodeWithSignature("setInitialOwnership(address)", msg.sender)
        );
        if (!success) revert FailedToSetAcountOwner(data);

        // determine version for the following event
        (success, data) =
            accountAddress.call(abi.encodeWithSignature("VERSION()"));
        if (!success) revert AccountFailedToFetchVersion(data);

        emit NewAccount({
            creator: msg.sender,
            account: accountAddress,
            version: abi.decode(data, (bytes32))
        });
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADABILITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function upgradeAccountImplementation(address _implementation)
        external
        override
        onlyOwner
    {
        if (!canUpgrade) revert CannotUpgrade();
        implementation = _implementation;
        emit AccountImplementationUpgraded({implementation: _implementation});
    }

    /// @inheritdoc IFactory
    function removeUpgradability() external override onlyOwner {
        canUpgrade = false;
    }
}

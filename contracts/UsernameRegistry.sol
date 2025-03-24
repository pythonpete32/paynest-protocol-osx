// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

/**
 * @title UsernameRegistry
 * @dev Contract for claiming and updating usernames across chains
 */
contract UsernameRegistry is OApp, OAppOptionsType3 {
    // Custom errors
    error UsernameAlreadyClaimed(string username);
    error UserHasNoUsername();
    error EmptyUsername();
    error UsernameTooLong(uint256 length);
    error InvalidUsername(string username);

    // Username mapping
    mapping(address => string) public usernames;
    mapping(string => address) public usernameOwners;

    // Max username length
    uint256 public constant MAX_USERNAME_LENGTH = 32;

    // Events
    event UsernameClaimed(address indexed user, string username);
    event UsernameUpdated(address indexed user, string oldUsername, string newUsername);

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {}

    /**
     * @notice Claim a username if it's available
     * @param _username The username to claim
     */
    function claimUsername(string calldata _username, uint32 _dstEid, bytes calldata _options) external payable {
        // Check username validity
        if (bytes(_username).length == 0) revert EmptyUsername();
        if (bytes(_username).length > MAX_USERNAME_LENGTH) revert UsernameTooLong(bytes(_username).length);

        // Check if username is already claimed
        if (usernameOwners[_username] != address(0)) revert UsernameAlreadyClaimed(_username);

        // Store previous username if exists
        string memory oldUsername = usernames[msg.sender];
        if (bytes(oldUsername).length > 0) delete usernameOwners[oldUsername];

        // Update mappings
        usernames[msg.sender] = _username;
        usernameOwners[_username] = msg.sender;

        sendUsernameUpdate(_dstEid, _username, _options);

        emit UsernameClaimed(msg.sender, _username);
    }

    /**
     * @notice Update a user's username
     * @param _newUsername The new username to claim
     */
    function updateUsername(string calldata _newUsername, uint32 _dstEid, bytes calldata _options) external payable {
        // Check if user has a username
        if (bytes(usernames[msg.sender]).length == 0) revert UserHasNoUsername();

        // Check username validity
        if (bytes(_newUsername).length == 0) revert EmptyUsername();
        if (bytes(_newUsername).length > MAX_USERNAME_LENGTH) revert UsernameTooLong(bytes(_newUsername).length);

        // Check if username is already claimed
        if (usernameOwners[_newUsername] != address(0)) revert UsernameAlreadyClaimed(_newUsername);

        // Store previous username if exists
        string memory oldUsername = usernames[msg.sender];
        if (bytes(oldUsername).length > 0) delete usernameOwners[oldUsername];

        // Update mappings
        usernames[msg.sender] = _newUsername;
        usernameOwners[_newUsername] = msg.sender;

        sendUsernameUpdate(_dstEid, _newUsername, _options);

        emit UsernameUpdated(msg.sender, oldUsername, _newUsername);
    }

    /**
     * @notice Send username update to other chains
     * @param _dstEid The endpoint ID of the destination chain
     * @param _username The username to send
     * @param _options Additional options for message execution
     * @return receipt A `MessagingReceipt` struct containing details of the message sent
     */
    function sendUsernameUpdate(
        uint32 _dstEid,
        string calldata _username,
        bytes calldata _options
    ) internal returns (MessagingReceipt memory receipt) {
        bytes memory _payload = abi.encode(msg.sender, _username);
        receipt = _lzSend(_dstEid, _payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    /**
     * @notice Quotes the gas needed for cross-chain username update
     * @param _dstEid Destination chain's endpoint ID
     * @param _username The username
     * @param _options Message execution options
     * @param _payInLzToken Whether to return fee in ZRO token
     * @return fee A `MessagingFee` struct containing the calculated gas fee
     */
    function quote(
        uint32 _dstEid,
        string calldata _username,
        bytes calldata _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(msg.sender, _username);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    /**
     * @dev Internal function to handle incoming username updates from another chain
     * @param payload The encoded message payload with address and username
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        (address user, string memory username) = abi.decode(payload, (address, string));

        // Store previous username if exists
        string memory oldUsername = usernames[user];
        if (bytes(oldUsername).length > 0) delete usernameOwners[oldUsername];

        // Update mappings
        usernames[user] = username;
        usernameOwners[username] = user;
    }
}

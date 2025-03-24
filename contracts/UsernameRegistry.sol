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
    error ArrayLengthMismatch();
    error InsufficientValue(uint256 provided, uint256 required);

    // Username mapping
    mapping(address => string) public usernames;
    mapping(string => address) public usernameOwners;

    // Max username length
    uint256 public constant MAX_USERNAME_LENGTH = 32;

    // Events
    event UsernameClaimed(address indexed user, string username);
    event UsernameUpdated(address indexed user, string oldUsername, string newUsername);
    event UsernamesSent(address indexed user, string username, uint32[] dstEids);

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {}

    /**
     * @notice Claim a username if it's available
     * @param _username The username to claim
     * @param _dstEids Array of destination chain endpoint IDs
     * @param _options Array of message execution options
     * @return receipts Array of messaging receipts for each cross-chain message sent
     */
    function claimUsername(
        string calldata _username,
        uint32[] calldata _dstEids,
        bytes[] calldata _options
    ) external payable returns (MessagingReceipt[] memory receipts) {
        // Check username validity
        if (bytes(_username).length == 0) revert EmptyUsername();
        if (bytes(_username).length > MAX_USERNAME_LENGTH) revert UsernameTooLong(bytes(_username).length);

        // Check array lengths match
        if (_dstEids.length != _options.length) revert ArrayLengthMismatch();

        // Check if username is already claimed
        if (usernameOwners[_username] != address(0)) revert UsernameAlreadyClaimed(_username);

        // Store previous username if exists
        string memory oldUsername = usernames[msg.sender];
        if (bytes(oldUsername).length > 0) delete usernameOwners[oldUsername];

        // Update mappings
        usernames[msg.sender] = _username;
        usernameOwners[_username] = msg.sender;

        receipts = sendUsernameUpdate(_dstEids, _username, _options);

        emit UsernameClaimed(msg.sender, _username);
        emit UsernamesSent(msg.sender, _username, _dstEids);

        return receipts;
    }

    /**
     * @notice Update a user's username
     * @param _newUsername The new username to claim
     * @param _dstEids Array of destination chain endpoint IDs
     * @param _options Array of message execution options
     * @return receipts Array of messaging receipts for each cross-chain message sent
     */
    function updateUsername(
        string calldata _newUsername,
        uint32[] calldata _dstEids,
        bytes[] calldata _options
    ) external payable returns (MessagingReceipt[] memory receipts) {
        // Check if user has a username
        if (bytes(usernames[msg.sender]).length == 0) revert UserHasNoUsername();

        // Check username validity
        if (bytes(_newUsername).length == 0) revert EmptyUsername();
        if (bytes(_newUsername).length > MAX_USERNAME_LENGTH) revert UsernameTooLong(bytes(_newUsername).length);

        // Check array lengths match
        if (_dstEids.length != _options.length) revert ArrayLengthMismatch();

        // Check if username is already claimed
        if (usernameOwners[_newUsername] != address(0)) revert UsernameAlreadyClaimed(_newUsername);

        // Store previous username if exists
        string memory oldUsername = usernames[msg.sender];
        if (bytes(oldUsername).length > 0) delete usernameOwners[oldUsername];

        // Update mappings
        usernames[msg.sender] = _newUsername;
        usernameOwners[_newUsername] = msg.sender;

        receipts = sendUsernameUpdate(_dstEids, _newUsername, _options);

        emit UsernameUpdated(msg.sender, oldUsername, _newUsername);
        emit UsernamesSent(msg.sender, _newUsername, _dstEids);

        return receipts;
    }

    /**
     * @notice Send username update to multiple chains
     * @param _dstEids Array of endpoint IDs of the destination chains
     * @param _username The username to send
     * @param _options Array of message execution options
     * @return receipts Array of messaging receipts for each cross-chain message sent
     */
    function sendUsernameUpdate(
        uint32[] calldata _dstEids,
        string calldata _username,
        bytes[] calldata _options
    ) internal returns (MessagingReceipt[] memory receipts) {
        // Check if options array matches destination chains array
        require(_dstEids.length == _options.length, "Options length must match destinations");

        // Get total fee required
        MessagingFee memory totalFee = quoteUpdate(_dstEids, _username, _options, false);

        // Check if enough value was sent
        if (msg.value < totalFee.nativeFee) {
            revert InsufficientValue(msg.value, totalFee.nativeFee);
        }

        // Create array to store receipts
        receipts = new MessagingReceipt[](_dstEids.length);

        // Distribute the msg.value across all sends
        uint256 valuePerSend = msg.value / _dstEids.length;
        uint256 remainingValue = msg.value;

        // Send to each destination
        for (uint256 i = 0; i < _dstEids.length; i++) {
            uint256 sendValue = i == _dstEids.length - 1 ? remainingValue : valuePerSend;
            remainingValue -= sendValue;

            bytes memory payload = abi.encode(msg.sender, _username);
            receipts[i] = _lzSend(_dstEids[i], payload, _options[i], MessagingFee(sendValue, 0), payable(msg.sender));
        }

        return receipts;
    }

    /**
     * @notice Quotes the gas needed for cross-chain username update
     * @param _dstEids Array of destination chain endpoint IDs
     * @param _username The username
     * @param _options Array of message execution options
     * @param _payInLzToken Whether to return fee in ZRO token
     * @return totalFee The combined fees for all destination chains
     */
    function quoteUpdate(
        uint32[] calldata _dstEids,
        string calldata _username,
        bytes[] calldata _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory totalFee) {
        if (_dstEids.length != _options.length) revert ArrayLengthMismatch();

        uint256 totalNativeFee = 0;
        uint256 totalLzTokenFee = 0;

        for (uint256 i = 0; i < _dstEids.length; i++) {
            bytes memory payload = abi.encode(msg.sender, _username);
            MessagingFee memory fee = _quote(_dstEids[i], payload, _options[i], _payInLzToken);
            totalNativeFee += fee.nativeFee;
            totalLzTokenFee += fee.lzTokenFee;
        }

        return MessagingFee(totalNativeFee, totalLzTokenFee);
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

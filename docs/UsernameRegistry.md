# UsernameRegistry Developer Documentation

## Overview

The `UsernameRegistry` contract provides a decentralized username registration system that works across multiple blockchains. It leverages LayerZero's cross-chain messaging protocol to maintain consistent username registrations across different networks.

## LayerZero Basics

LayerZero is an omnichain interoperability protocol that enables direct cross-chain communication. For developers new to LayerZero:

1. **OApp**: The `UsernameRegistry` extends `OApp`, the base LayerZero contract that enables cross-chain messaging.

2. **Endpoints**: Each blockchain has a LayerZero Endpoint contract. Our constructor accepts an `_endpoint` address to connect to the local chain's endpoint.

3. **Endpoint IDs (EIDs)**: Each blockchain has a unique endpoint ID (`uint32`). When sending messages, you specify the destination chain using its EID.

4. **Cross-Chain Messages**: When you register or update a username, the contract sends messages to other chains to synchronize the data.

5. **Messaging Fee**: Cross-chain messages require gas fees both on the source and destination chains. These are paid in the source chain's native token.

## Architecture

The contract inherits from:

- `OApp`: Base LayerZero contract for cross-chain messaging
- `OAppOptionsType3`: Provides options for configuring message deliveries
- `Ownable`: Standard access control

Key state variables:

```solidity
mapping(address => string) public usernames;         // Maps user addresses to their usernames
mapping(string => address) public usernameOwners;    // Maps usernames to owner addresses
uint256 public constant MAX_USERNAME_LENGTH = 32;    // Maximum username length
```

## Core Functions

### Registration & Updates

```solidity
function claimUsername(
    string calldata _username,
    uint32[] calldata _dstEids,
    bytes[] calldata _options
) external payable returns (MessagingReceipt[] memory receipts)
```

This function:

1. Validates the username (length, availability)
2. Updates local mappings
3. Sends cross-chain messages to all specified destination chains
4. Returns an array of `MessagingReceipt`s for tracking messages

`updateUsername` works similarly but requires the user to already have a username.

### LayerZero Integration

#### Sending Messages

```solidity
function sendUsernameUpdate(
    uint32[] calldata _dstEids,
    string calldata _username,
    bytes[] calldata _options
) internal returns (MessagingReceipt[] memory receipts)
```

This function:

1. Calculates the total fee required for all cross-chain messages
2. Verifies sufficient ETH was provided
3. Distributes the payment across all destination chains
4. Encodes the username data as a payload
5. Calls LayerZero's `_lzSend` for each destination
6. Returns receipts for tracking

#### Receiving Messages

```solidity
function _lzReceive(
    Origin calldata /*_origin*/,
    bytes32 /*_guid*/,
    bytes calldata payload,
    address /*_executor*/,
    bytes calldata /*_extraData*/
) internal override
```

This function:

1. Gets called by the LayerZero endpoint when a message arrives
2. Decodes the payload containing the user address and username
3. Updates the local mappings to match the sender's chain

#### Fee Estimation

```solidity
function quoteUpdate(
    uint32[] calldata _dstEids,
    string calldata _username,
    bytes[] calldata _options,
    bool _payInLzToken
) public view returns (MessagingFee memory totalFee)
```

This function:

1. Calculates the total gas fees required for cross-chain operations
2. Users should call this before `claimUsername` or `updateUsername` to know how much ETH to provide

## Message Options

The `_options` parameter is crucial for configuring LayerZero message delivery:

- Gas for execution on the destination chain
- Execution options (e.g., retries, timeouts)
- Version information

The format follows the OAppOptionsType3 standard provided by LayerZero.

## Cross-Chain Flow

1. **Username Registration**: When a user registers a username:

   - The contract saves the mapping on the current chain
   - It sends messages to all specified destination chains using LayerZero

2. **Message Delivery**: For each destination chain:

   - LayerZero picks up the message and delivers it to that chain's endpoint
   - The destination chain's endpoint calls the `_lzReceive` function
   - The username mapping is updated on the destination chain

3. **Message Tracking**: Each send operation returns a `MessagingReceipt` with:
   - `guid`: A unique identifier for tracking the message
   - `nonce`: A sequential number for ordering
   - `fee`: The actual fee charged

## Implementation Notes

1. **Value Distribution**: The contract intelligently distributes ETH across all destination chains to ensure sufficient fees for each message.

2. **Payload Encoding**: Cross-chain messages use `abi.encode(address, string)` format to maintain consistency.

3. **Receipt Handling**: Each cross-chain operation returns `MessagingReceipt` arrays for external applications to track message delivery.

## Example Usage

To register a username across multiple chains:

```solidity
// Get fee estimate
uint32[] memory dstEids = new uint32[](2);
dstEids[0] = 1; // Ethereum Mainnet
dstEids[1] = 110; // Arbitrum

bytes[] memory options = new bytes[](2);
// Configure default options
options[0] = defaultOptions;
options[1] = defaultOptions;

// Get quote
MessagingFee memory fee = usernameRegistry.quoteUpdate(dstEids, "satoshi", options, false);

// Register username
MessagingReceipt[] memory receipts = usernameRegistry.claimUsername{value: fee.nativeFee}(
    "satoshi",
    dstEids,
    options
);

// Track message delivery using receipt GUIDs
for (uint i = 0; i < receipts.length; i++) {
    bytes32 guid = receipts[i].guid;
    // Use guid to track message status
}
```

## Conclusion

The `UsernameRegistry` provides a robust system for creating consistent usernames across multiple blockchains. By leveraging LayerZero, it creates a unified identity layer that can be used across the entire blockchain ecosystem.

For further details on LayerZero-specific parameters or options, refer to the [LayerZero documentation](https://docs.layerzero.network/).

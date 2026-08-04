// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {CCIPReceiver as ChainlinkCCIPReceiver} from "@chainlink/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {Errors} from "../libraries/Errors.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface IWrappedMint {
    function mint(address account, uint256 amount) external;
}

interface ICanonicalRelease {
    function releaseCanonical(address receiver, uint256 amount) external;
}

/// @notice CCIP destination endpoint. Router authentication is inherited; each lane additionally authenticates its sender.
contract CCIPReceiver is ChainlinkCCIPReceiver, AccessControl, Pausable {
    uint8 private constant MINT_WRAPPED = 1;
    uint8 private constant UNLOCK_CANONICAL = 2;
    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");
    address public immutable wrappedToken;
    address public immutable canonicalSender;
    mapping(uint64 => address) public allowedSender;
    mapping(bytes32 => bool) public processedMessage;
    event AllowedSenderSet(uint64 indexed sourceChain, address indexed sender);
    event BridgeReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChain,
        address indexed receiver,
        uint256 amount,
        uint8 action,
        uint64 nonce
    );

    constructor(address admin, address router, address wrappedToken_, address canonicalSender_)
        ChainlinkCCIPReceiver(router)
    {
        if (admin == address(0)) revert Errors.ZeroAddress();
        wrappedToken = wrappedToken_;
        canonicalSender = canonicalSender_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
    }

    function setAllowedSender(uint64 sourceChain, address sender) external onlyRole(BRIDGE_ADMIN_ROLE) {
        if (sender == address(0)) revert Errors.ZeroAddress();
        allowedSender[sourceChain] = sender;
        emit AllowedSenderSet(sourceChain, sender);
    }

    function pauseBridge() external onlyRole(BRIDGE_ADMIN_ROLE) {
        _pause();
    }

    function unpauseBridge() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(ChainlinkCCIPReceiver, AccessControl)
        returns (bool)
    {
        return ChainlinkCCIPReceiver.supportsInterface(interfaceId) || interfaceId == type(IAccessControl).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override whenNotPaused {
        if (processedMessage[message.messageId]) {
            revert Errors.MessageAlreadyProcessed(message.messageId);
        }
        if (message.sender.length != 32) revert Errors.InvalidMessage();
        address sender = abi.decode(message.sender, (address));
        if (sender != allowedSender[message.sourceChainSelector]) {
            revert Errors.UnauthorizedSender(message.sourceChainSelector, sender);
        }
        (uint8 action, address receiver, uint256 amount, uint64 messageNonce) =
            abi.decode(message.data, (uint8, address, uint256, uint64));
        if (receiver == address(0) || amount == 0) {
            revert Errors.InvalidMessage();
        }
        processedMessage[message.messageId] = true;
        if (action == MINT_WRAPPED) {
            if (wrappedToken == address(0)) {
                revert Errors.UnsupportedBridgeAction(action);
            }
            IWrappedMint(wrappedToken).mint(receiver, amount);
        } else if (action == UNLOCK_CANONICAL) {
            if (canonicalSender == address(0)) {
                revert Errors.UnsupportedBridgeAction(action);
            }
            ICanonicalRelease(canonicalSender).releaseCanonical(receiver, amount);
        } else {
            revert Errors.UnsupportedBridgeAction(action);
        }
        emit BridgeReceived(message.messageId, message.sourceChainSelector, receiver, amount, action, messageNonce);
    }
}

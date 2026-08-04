// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IRouterClient} from "@chainlink/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {Errors} from "../libraries/Errors.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface IWrappedBurn {
    function burnFrom(address account, uint256 amount) external;
}

/// @notice CCIP origin endpoint. Canonical deployments lock RBT; satellite deployments burn wrapped RBT.
contract CCIPSender is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    uint8 private constant MINT_WRAPPED = 1;
    uint8 private constant UNLOCK_CANONICAL = 2;
    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");
    IRouterClient public immutable router;
    address public immutable token;
    bool public immutable canonical;
    uint64 public nonce;
    mapping(uint64 => address) public remoteReceiver;
    address public canonicalReleaseReceiver;
    event RemoteReceiverSet(uint64 indexed chain, address indexed receiver);
    event BridgeSent(
        bytes32 indexed messageId, uint64 indexed destination, address indexed receiver, uint256 amount, uint64 nonce
    );
    event CanonicalReleased(address indexed receiver, uint256 amount);

    constructor(address admin, address router_, address token_, bool canonical_) {
        if (admin == address(0) || router_ == address(0) || token_ == address(0)) revert Errors.ZeroAddress();
        router = IRouterClient(router_);
        token = token_;
        canonical = canonical_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, admin);
    }

    function setRemoteReceiver(uint64 chain, address receiver) external onlyRole(BRIDGE_ADMIN_ROLE) {
        if (chain == 0 || receiver == address(0)) {
            revert Errors.InvalidMessage();
        }
        remoteReceiver[chain] = receiver;
        emit RemoteReceiverSet(chain, receiver);
    }

    function quoteFee(uint64 destination, address receiver, uint256 amount, uint256 gasLimit)
        external
        view
        returns (uint256)
    {
        return router.getFee(destination, _message(destination, receiver, amount, nonce + 1, gasLimit));
    }

    function bridge(uint64 destination, address receiver, uint256 amount, uint256 gasLimit)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (bytes32 messageId)
    {
        if (receiver == address(0) || amount == 0 || remoteReceiver[destination] == address(0)) {
            revert Errors.InvalidMessage();
        }
        if (!router.isChainSupported(destination)) {
            revert Errors.UnsupportedChain();
        }
        if (canonical) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            IWrappedBurn(token).burnFrom(msg.sender, amount);
        }
        uint64 nextNonce = ++nonce;
        Client.EVM2AnyMessage memory message = _message(destination, receiver, amount, nextNonce, gasLimit);
        uint256 fee = router.getFee(destination, message);
        if (msg.value != fee) revert Errors.InvalidFee();
        messageId = router.ccipSend{value: fee}(destination, message);
        emit BridgeSent(messageId, destination, receiver, amount, nextNonce);
    }

    function releaseCanonical(address receiver, uint256 amount) external {
        if (msg.sender != canonicalReleaseReceiver) revert Errors.NotBridge();
        IERC20(token).safeTransfer(receiver, amount);
        emit CanonicalReleased(receiver, amount);
    }

    function setCanonicalReleaseReceiver(address receiver) external onlyRole(BRIDGE_ADMIN_ROLE) {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        if (canonicalReleaseReceiver != address(0)) {
            revert Errors.AlreadyConfigured();
        }
        canonicalReleaseReceiver = receiver;
    }

    function pauseBridge() external onlyRole(BRIDGE_ADMIN_ROLE) {
        _pause();
    }

    function unpauseBridge() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _message(uint64 destination, address receiver, uint256 amount, uint64 messageNonce, uint256 gasLimit)
        private
        view
        returns (Client.EVM2AnyMessage memory message)
    {
        uint8 action = canonical ? MINT_WRAPPED : UNLOCK_CANONICAL;
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(remoteReceiver[destination]),
            data: abi.encode(action, receiver, amount, messageNonce),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: false})
            )
        });
    }
}

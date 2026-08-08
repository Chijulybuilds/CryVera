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
import {Events} from "../libraries/Events.sol";

// tells the CCIP Sender that there are wRBT to be burned "from"
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
    mapping(uint64 => address) public remoteReceiver; // remotereceiver that shows the address of the contract that receives the CCIP messages on the destination chain
    address public canonicalReleaseReceiver; // a trusted address that let's canonical RBT to be released

    /**
     * @param admin address that controls the system
     * @param timelock contract address of the TimeLockController
     * @param router_ the CCIP router address for the source chain
     * @param rbttoken_ the rbt token to be sent
     * @param canonical_ true or false statement that reflects if the deployment is canonical
     */
    constructor(address admin, address timelock, address router_, address rbttoken_, bool canonical_) {
        if (admin == address(0) || timelock == address(0) || router_ == address(0) || rbttoken_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        router = IRouterClient(router_);
        token = rbttoken_;
        canonical = canonical_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ADMIN_ROLE, timelock);
    }

    /**
     * @param chain the destination chain ID
     * @param receiver the address of the contract that receives the CCIP messages on the destination chain
     */
    function setRemoteReceiver(uint64 chain, address receiver) external onlyRole(BRIDGE_ADMIN_ROLE) {
        if (chain == 0 || receiver == address(0)) {
            revert Errors.InvalidMessage();
        }
        remoteReceiver[chain] = receiver;
        emit Events.RemoteReceiverSet(chain, receiver);
    }

    /**
     * @param destination the destination chain ID
     * @param receiver the address of the contract that receives the CCIP messages on the destination chain
     * @param amount the amount of tokens to be sent
     * @param gasLimit the gas limit for the transaction
     */
    function quoteFee(uint64 destination, address receiver, uint256 amount, uint256 gasLimit)
        external
        view
        returns (uint256)
    {
        return router.getFee(destination, _message(destination, receiver, amount, nonce + 1, gasLimit));
    }

    /**
     * @param destination the destination chain ID
     * @param receiver the address of the contract that receives the CCIP messages on the destination chain
     * @param amount the amount of tokens to be sent
     * @param gasLimit the gas limit for the transaction
     */
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
        emit Events.BridgeSent(messageId, destination, receiver, amount, nextNonce);
    }

    function releaseCanonical(address receiver, uint256 amount) external {
        if (msg.sender != canonicalReleaseReceiver) revert Errors.NotBridge();
        IERC20(token).safeTransfer(receiver, amount);
        emit Events.CanonicalReleased(receiver, amount);
    }

    function setCanonicalReleaseReceiver(address receiver) external onlyRole(BRIDGE_ADMIN_ROLE) {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        if (canonicalReleaseReceiver != address(0)) {
            revert Errors.AlreadyConfigured();
        }
        canonicalReleaseReceiver = receiver;
    }

    function pauseBridge() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpauseBridge() external onlyRole(BRIDGE_ADMIN_ROLE) {
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title ProtocolPausable
 * @author CryVera Protocol Architecture Team
 * @notice Enforces a Fast-Pause / Slow-Unpause emergency security architecture.
 */
abstract contract ProtocolPausable is Initializable, PausableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    event EmergencyPaused(address indexed caller, string reason);
    event EmergencyUnpaused(address indexed caller);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __ProtocolPausable_init(address admin, address pauser) internal onlyInitializing {
        __Pausable_init();
        __AccessControl_init();

        require(admin != address(0), "ProtocolPausable: zero admin address");
        require(pauser != address(0), "ProtocolPausable: zero pauser address");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UNPAUSER_ROLE, admin);
    }

    function emergencyPause(string calldata reason) external onlyRole(PAUSER_ROLE) {
        _pause();
        emit EmergencyPaused(msg.sender, reason);
    }

    function emergencyUnpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }

    uint256[50] private __gap;
}

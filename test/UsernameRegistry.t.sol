// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// UsernameRegistry imports
import { UsernameRegistry } from "../../contracts/UsernameRegistry.sol";

// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, Origin, MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Forge imports
import "forge-std/console.sol";
import "forge-std/Test.sol";

// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract UsernameRegistryTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    UsernameRegistry private aRegistry;
    UsernameRegistry private bRegistry;

    address private userA = address(0x1);
    address private userB = address(0x2);
    uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aRegistry = UsernameRegistry(
            _deployOApp(type(UsernameRegistry).creationCode, abi.encode(address(endpoints[aEid]), address(this)))
        );

        bRegistry = UsernameRegistry(
            _deployOApp(type(UsernameRegistry).creationCode, abi.encode(address(endpoints[bEid]), address(this)))
        );

        address[] memory oapps = new address[](2);
        oapps[0] = address(aRegistry);
        oapps[1] = address(bRegistry);
        this.wireOApps(oapps);
    }

    function test_constructor() public view {
        assertEq(aRegistry.owner(), address(this));
        assertEq(bRegistry.owner(), address(this));

        assertEq(address(aRegistry.endpoint()), address(endpoints[aEid]));
        assertEq(address(bRegistry.endpoint()), address(endpoints[bEid]));
    }

    function test_claimUsername() public {
        string memory username = "testuser";

        vm.prank(userA);
        aRegistry.claimUsername(username);

        assertEq(aRegistry.usernames(userA), username);
        assertEq(aRegistry.usernameOwners(username), userA);
    }

    function test_claimUsername_alreadyClaimed() public {
        string memory username = "testuser";

        vm.prank(userA);
        aRegistry.claimUsername(username);

        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(UsernameRegistry.UsernameAlreadyClaimed.selector, username));
        aRegistry.claimUsername(username);
    }

    function test_updateUsername() public {
        string memory username1 = "oldname";
        string memory username2 = "newname";

        vm.startPrank(userA);
        aRegistry.claimUsername(username1);

        assertEq(aRegistry.usernames(userA), username1);
        assertEq(aRegistry.usernameOwners(username1), userA);

        aRegistry.updateUsername(username2);
        vm.stopPrank();

        assertEq(aRegistry.usernames(userA), username2);
        assertEq(aRegistry.usernameOwners(username2), userA);
        assertEq(aRegistry.usernameOwners(username1), address(0));
    }

    function test_updateUsername_noExistingUsername() public {
        string memory username = "testuser";

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(UsernameRegistry.UserHasNoUsername.selector));
        aRegistry.updateUsername(username);
    }
}

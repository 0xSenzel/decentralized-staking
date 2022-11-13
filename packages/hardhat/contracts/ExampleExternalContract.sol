// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;  //Do not change the solidity version as it negativly impacts submission grading

import "@openzeppelin/contracts/access/Ownable.sol";

contract ExampleExternalContract is Ownable {
  bool public completed;
  address public admin;
  event AdminAdded(address);
  constructor(address yourAddress) {
    // Set owner of the contract to our own metamask address as Scaffold-ETH
    // default msg.sender is locally generated address
    transferOwnership(yourAddress);
  }

  function complete(bool status) public returns (bool) {
    require(msg.sender == owner() || msg.sender == admin, "Not owner or admin");
    completed = status;
    return status;
  }

  /*
  Allows only to retrieve "unproductive" funds that are sent
  to this contract
  */
  function deexecute(address stakingContract) public {
    require(msg.sender == owner() || msg.sender == admin, "Must be owner or admin");
    require(completed, "Stake is on-going!");

    uint256 contractBalance = address(this).balance;
    (bool success,) = address(stakingContract).call{value: contractBalance}("");
    require(success, "Transfer to Stake failed");

    complete(false);
  }

  /*
  Function will set admin for address
  selected by owner
  */
  function whitelist(address _admin) public onlyOwner {
    require(_admin != address(0), "Enter valid address!");
    admin = _admin;
    emit AdminAdded(admin);
  }   

  receive() external payable {}

}

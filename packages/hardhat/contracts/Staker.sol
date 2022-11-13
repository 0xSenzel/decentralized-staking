// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Staker is Ownable {

  ExampleExternalContract public exampleExternalContract;

  mapping(address => uint256) public balances;
  mapping(address => uint256) public depositTimestamps;
  mapping(address => uint256) public totalWithdraw;

  uint256 public rewardRatePerYear = 10 ether; // Percentage of return
  uint256 public withdrawalDeadline;
  uint256 public claimDeadline;
  uint256 public currentBlock = 0;
  uint256 public withdrawalTime = 90 days;
  // Events
  event Stake(address indexed sender, uint256 amount);
  event Received(address, uint);
  event Execute(address indexed sender, uint256 amount);

  // Modifiers
  /*
  Checks if the withdrawal period has been reached or not
  */
  modifier withdrawalDeadlineReached( bool requireReached ) {
    uint256 timeRemaining = withdrawalTimeLeft();
    if( requireReached ) {
      require(timeRemaining == 0, "Withdrawal period is not reached yet");
    } else {
      require(timeRemaining > 0, "Withdrawal period has been reached");
    }
    _;
  }

  /*
  Checks if the claim period has ended or not
  */
  modifier claimDeadlineReached( bool requireReached ) {
    uint256 timeRemaining = claimPeriodLeft();
    if( requireReached ) {
      require(timeRemaining == 0, "Claim deadline is not reached yet");
    } else {
      require(timeRemaining > 0, "Claim deadline has been reached");
    }
    _;
  }

  constructor(address payable exampleExternalContractAddress, address yourAddress){
      exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
      // Set owner of the contract to our own metamask address as Scaffold-ETH
      // default msg.sender is locally generated address
      transferOwnership(yourAddress);
  }

  /*
  Function sets APY unit in ethers (10 ** 18)
  Default to 10% interest return rate
  */
  function setAPY(uint256 rate) public onlyOwner returns (uint256)  {
    rewardRatePerYear = rate * 10 ** 18;
    return rewardRatePerYear;
  }

  /*
  Function sets staking period, unit in seconds.
  Default to 90days / 7,776,000 seconds
  For testing set to 2 minutes / 120 seconds
  */
  function setWithdrawalDeadline(uint256 time) public onlyOwner returns(uint256) {
    withdrawalTime = time;
    return time;
  }

  /*
  Function let user stake their ETH.
  Return calculated per withdrawal period
  eg: 90 days return based on 10% APY
  */
  function stake() public payable {
    if(withdrawalTimeLeft() > 0 && claimPeriodLeft() > 0){
      balances[msg.sender] += msg.value;
      depositTimestamps[msg.sender] = block.timestamp;
      withdrawalDeadline = block.timestamp + withdrawalTime;
      claimDeadline = withdrawalDeadline + 30 seconds;
      totalAmountEligible();

      emit Stake(msg.sender, msg.value);    
    } else {
      balances[msg.sender] += msg.value;
      depositTimestamps[msg.sender] = block.timestamp;
      withdrawalDeadline = block.timestamp + withdrawalTime;
      claimDeadline = withdrawalDeadline + 30 seconds;
      totalAmountEligible();

      emit Stake(msg.sender, msg.value);
    }
  }

  /*
  Function calculates return of interest based 
  on user's deposited amount
  */
  function rewardPerToken() public returns (uint256) {
    uint256 interest =  balances[msg.sender] * rewardRatePerYear * (withdrawalDeadline - depositTimestamps[msg.sender]);
    // Divide by %, 365days in second, 10^18 (ether)
    interest /= (100 * 365 * 24 * 60 * 60 * 10 ** 18);
    return interest; 
  }
  
  /*
  Function calculates amount of ETH will
  receive by the end of Withdrawal Period
  */
  function totalAmountEligible() public returns (uint256) {
    uint256 _totalWithdraw = balances[msg.sender] + rewardPerToken();
    totalWithdraw[msg.sender] = _totalWithdraw ;
    return _totalWithdraw;
  }

  /*
  Withdraw function for a user to remove their staked ETH inclusive
  of both principal and any accrued interest
  */
  function withdraw() public {
    require(balances[msg.sender] > 0, "You have no balance to withdraw!");
    require(withdrawalTimeLeft() == 0, "Not yet withdrawal deadline");
    require(claimPeriodLeft() > 0, "Claim period is over");
    uint256 totalWithdrawAmount = totalAmountEligible();
    balances[msg.sender] = 0;
    totalWithdraw[msg.sender] = 0;

    // Transfer all ETH via call! (not transfer) cc: https://solidity-by-example.org/sending-ether
    (bool sent, bytes memory data) = msg.sender.call{value: totalWithdrawAmount}("");
    require(sent, "RIP; withdrawal failed :( ");
  }

  /*
  Function let user withdraw their staked amount
  that is not claimed before Claimed Period ended
  */
  function withdrawExpiredFund() public {
    require(balances[msg.sender] > 0, "You have no balance to withdraw!");
    require(withdrawalTimeLeft() == 0, "Not yet withdrawal deadline");
    require(claimPeriodLeft() == 0, "Claim period is over");

    uint256 totalWithdrawAmount = totalAmountEligible();
    balances[msg.sender] = 0;
    totalWithdraw[msg.sender] = 0;

    // Transfer all ETH via call! (not transfer) cc: https://solidity-by-example.org/sending-ether
    (bool sent, bytes memory data) = msg.sender.call{value: totalWithdrawAmount}("");
    require(sent, "RIP; withdrawal failed :( ");
  }

  /*
  Allows owner to repatriate "unproductive" funds that are left in the staking contract
  past the defined withdrawal period
  */
  function execute() public claimDeadlineReached(true) onlyOwner {
    bool status = exampleExternalContract.completed();
    require(!status, "Stake already completed!");

    uint256 contractBalance = address(this).balance;
    (bool success,) = address(exampleExternalContract).call{value: contractBalance}("");
    require(success, "Transfer to External failed");

    exampleExternalContract.complete(true);
  }

  /*
  READ-ONLY function to calculate the time remaining before the minimum staking period has passed
  */
  function withdrawalTimeLeft() public view returns (uint256 withdrawalTimeLeft_) {
    if( block.timestamp >= withdrawalDeadline) {
      return (0);
    } else {
      return (withdrawalDeadline - block.timestamp);
    }
  }

  /*
  READ-ONLY function to calculate the time remaining before the minimum staking period has passed
  */
  function claimPeriodLeft() public view returns (uint256 claimPeriodLeft_) {
    if( block.timestamp >= claimDeadline) {
      return (0);
    } else {
      return (claimDeadline - block.timestamp);
    }
  }

  /*
  Time to "kill-time" on our local testnet
  */
  function killTime() public {
    currentBlock = block.timestamp;
    claimPeriodLeft();
    withdrawalTimeLeft();
  }

  /*
  \Function for our smart contract to receive ETH
  cc: https://docs.soliditylang.org/en/latest/contracts.html#receive-ether-function
  */
  receive() external payable {
      emit Received(msg.sender, msg.value);
  }

}

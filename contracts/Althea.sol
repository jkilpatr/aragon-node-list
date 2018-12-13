pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";

contract Althea is AragonApp {
  using SafeMath for uint;

  event NewMember(
    address indexed ethAddress,
    bytes16 ipAddress,
    bytes16 nickname
  );
  event MemberRemoved(
    address indexed ethAddress,
    bytes16 ipAddress,
    bytes16 nickname
  );

  event NewBill(address payer, address collector);
  event BillUpdated(address payer);
 
  bytes32 constant public MANAGER = keccak256("MANAGER");
  bytes32 constant public DELETE = keccak256("DELETE");
  bytes32 constant public ADD = keccak256("ADD");

  struct Bill {
    uint balance;
    uint perBlock;
    uint lastUpdated;
  }

  struct User {
    address ethAddr;
    bytes16 nick;
  }

  uint public perBlockFee;
  address public paymentAddress;
  bytes16[] public subnetSubscribers;
  mapping(bytes16 => User) public userList;
  mapping(address => Bill) public billMapping;

  function initialize() external onlyInit {
    perBlockFee = 10000;
    paymentAddress = msg.sender;
    initialized();
  }

  function addMember(address _ethAddr, bytes16 _ip, bytes16 _nick)
    external 
    auth(ADD)
  {
    require(userList[_ip].ethAddr== address(0), "Member already exists");
    userList[_ip].ethAddr = _ethAddr;
    userList[_ip].nick = _nick;
    subnetSubscribers.push(_ip);
    NewMember(_ethAddr, _ip, _nick);
  }

  function deleteMember(bytes16 _ip) external auth(DELETE) {
    MemberRemoved(userList[_ip].ethAddr, _ip, userList[_ip].nick);
    delete userList[_ip];
    for (uint i = 0; i < subnetSubscribers.length; i++) {
      if (_ip == subnetSubscribers[i]) {
        subnetSubscribers[i] = subnetSubscribers[subnetSubscribers.length-1];
        subnetSubscribers.length--;
      }
    }
  }

  function getMember(bytes16 _ip) external view returns(address addr) {
    addr = userList[_ip].ethAddr;
  }

  function setPerBlockFee(uint _newFee) external auth(MANAGER) {
    perBlockFee = _newFee;
  }

  function setPaymentAddr(address _a) external auth(MANAGER) {
    paymentAddress = _a;
  }

  function getCountOfSubscribers() external view returns (uint) {
    return subnetSubscribers.length;
  }

  function addBill() public payable {
    require(msg.value > perBlockFee, "Message value not enough");

    if (billMapping[msg.sender].lastUpdated == 0) {
      billMapping[msg.sender] = Bill(msg.value, perBlockFee, block.number);
      emit NewBill(msg.sender, paymentAddress);
    } else {
      billMapping[msg.sender].balance = billMapping[msg.sender].balance.add(msg.value);
      emit BillUpdated(msg.sender);
    }
  }

  function collectBills() external {
    uint transferValue = 0;
    for (uint i = 0; i < subnetSubscribers.length; i++) {

      transferValue = transferValue.add(
        processBills(userList[subnetSubscribers[i]].ethAddr)
      );
    }
    address(paymentAddress).transfer(transferValue);
  }

  function payMyBills() public {
    address(paymentAddress).transfer(processBills(msg.sender));
  }

  function withdrawFromBill() external {
    payMyBills();
    uint amount = billMapping[msg.sender].balance;
    require(amount > 0, "Amount to payout is no more than zero, aborting");
    billMapping[msg.sender].balance = 0;
    address(msg.sender).transfer(amount);
    emit BillUpdated(msg.sender);
  }

  function processBills(address _subscriber) internal returns(uint) {
    uint transferValue;
    Bill memory bill = billMapping[_subscriber];
    uint amountOwed = block.number.sub(bill.lastUpdated).mul(bill.perBlock);

    if (amountOwed <= bill.balance) {
      billMapping[_subscriber].balance= bill.balance.sub(amountOwed);
      transferValue = amountOwed;
    } else {
      transferValue = bill.balance;
      billMapping[_subscriber].balance = 0;
    }
    billMapping[_subscriber].lastUpdated = block.number;
    emit BillUpdated(_subscriber);
    return transferValue;
  }

  // leave a space between `function` and `(` or else the parser won't work
  function () external payable isInitialized {
    addBill();
  }
}

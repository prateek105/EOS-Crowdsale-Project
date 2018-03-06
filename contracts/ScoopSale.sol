pragma solidity 0.4.18;

import "./DSAuth.sol";
import "./DSExec.sol";
import "./DSMath.sol";
import "./ScoopToken.sol";


contract ScoopSale is DSAuth, DSExec, DSMath {
    ScoopToken  public  Scoop;                  // The Scoop token itself
    uint128  public  totalSupply;          // Total Scoop amount created
    uint128  public  foundersAllocation;   // Amount given to founders
    address public founderAddress;

    uint     public  openTime;             // Time of window 0 opening
    uint     public  createFirstDay;       // Tokens sold in window 0

    uint     public  startTime;            // Time of window 1 opening
    uint     public  numberOfDays;         // Number of windows after 0
    uint     public  createPerDay;         // Tokens sold in each window

    mapping (uint => uint)                       public  dailyTotals;
    mapping (uint => mapping (address => uint))  public  userBuys;
    mapping (uint => mapping (address => bool))  public  claimed;
   

    event LogBuy      (uint window, address user, uint amount);
    event LogClaim    (uint window, address user, uint amount);
    event LogCollect  (uint amount);
    event LogFreeze   ();

    function ScoopSale(
        uint     _numberOfDays,
        uint128  _totalSupply,
        uint     _openTime,
        uint     _startTime,
        uint128  _foundersAllocation,
        address  _founderAddress
    ) {
        numberOfDays       = _numberOfDays;
        totalSupply        = _totalSupply;
        openTime           = _openTime;
        startTime          = _startTime;
        foundersAllocation = _foundersAllocation;
        founderAddress     = _founderAddress;

        createFirstDay = wmul(totalSupply, 0.2 ether);
        createPerDay = div(
            sub(sub(totalSupply, foundersAllocation), createFirstDay),
            numberOfDays
        );

        assert(numberOfDays > 0);
        assert(totalSupply > foundersAllocation);
        assert(openTime < startTime);
    }

    function initialize( ScoopToken scoop) auth {
        assert(address(Scoop) == address(0));
        assert(scoop.owner() == address(this));
        assert(scoop.authority() == DSAuthority(0));
        assert(scoop.totalSupply() == 0);

        Scoop = scoop;
        Scoop.mint(totalSupply);
        Scoop.push(founderAddress, foundersAllocation);

    }

    function time() constant returns (uint) {
        return block.timestamp;
    }

    function today() constant returns (uint) {
        return dayFor(time());
    }

    // Each window is 23 hours long so that end-of-window rotates
    // around the clock for all timezones.
    function dayFor(uint timestamp) constant returns (uint) {
        return timestamp < startTime
            ? 0
            : sub(timestamp, startTime) / 23 hours + 1;
    }

    function createOnDay(uint day) constant returns (uint) {
        return day == 0 ? createFirstDay : createPerDay;
    }

    // This method provides the buyer some protections regarding which
    // day the buy order is submitted and the maximum price prior to
    // applying this payment that will be allowed.
    function buyWithLimit(uint day, uint limit) payable {
        assert(time() >= openTime && today() <= numberOfDays);
        assert(msg.value >= 0.01 ether);

        assert(day >= today());
        assert(day <= numberOfDays);

        userBuys[day][msg.sender] = add(userBuys[day][msg.sender], msg.value);
        dailyTotals[day] = add(dailyTotals[day], msg.value);

        if (limit != 0) {
            assert(dailyTotals[day] <= limit);
        }

        LogBuy(day, msg.sender, msg.value);
    }

    function buy() payable {
        buyWithLimit(today(), 0);
    }

    function () payable {
        buy();
    }

    function claim(uint day) {
        assert(today() > day);

        if (claimed[day][msg.sender] || dailyTotals[day] == 0) {
            return;
        }

        // This will have small rounding errors, but the token is
        // going to be truncated to 8 decimal places or less anyway
        // when launched on its own chain.

        var dailyTotal = cast(dailyTotals[day]);
        var userTotal  = cast(userBuys[day][msg.sender]);
        var price      = wdiv(cast(createOnDay(day)), dailyTotal);
        var reward     = wmul(price, userTotal);

        claimed[day][msg.sender] = true;
        Scoop.push(msg.sender, reward);

        LogClaim(day, msg.sender, reward);
    }

    function claimAll() {
        for (uint i = 0; i < today(); i++) {
            claim(i);
        }
    }

    // Crowdsale owners can collect ETH any number of times
    function collect() auth {
        assert(today() > 0); // Prevent recycling during window 0
        exec(msg.sender, this.balance);
        LogCollect(this.balance);
    }
}
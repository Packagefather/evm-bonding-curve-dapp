// SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract QuadraticBondingCurve is Initializable {
    IERC20 public token;
    uint256 public totalSupply;
    uint256 public allocationPercent; // scaled by 1000, e.g., 80000 = 80.000%
    uint256 public vETH;              // virtual ETH, e.g., 2.5e18 wei (2.5 ETH)
    uint256 public curveLimit;        // max ETH to raise, e.g., 10e18 wei (10 ETH)

    uint256 public vToken;            // tokens allocated to curve (allocationPercent of totalSupply)
    uint256 public k;                 // curve constant

    uint256 public raisedETH;
    uint256 public tokensSold;
    bool public migrationTriggered;

    address public owner;

    // Events
    event TokensPurchased(address indexed buyer, uint256 ethSpent, uint256 tokensReceived);
    event MigrationTriggered(uint256 raisedETH, uint256 tokensSold);
    event Withdrawn(address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function initialize(
        address tokenAddress,
        uint256 _totalSupply,
        uint256 _allocationPercent,
        uint256 _vETH,
        uint256 _curveLimit,
        address _owner
    ) external initializer {
        require(tokenAddress != address(0), "Token address zero");
        require(_allocationPercent > 0 && _allocationPercent <= 100000, "Alloc % invalid");
        require(_vETH > 0, "vETH must be > 0");
        require(_curveLimit > 0, "curveLimit must be > 0");
        require(_owner != address(0), "Owner zero address");

        token = IERC20(tokenAddress);
        totalSupply = _totalSupply;
        allocationPercent = _allocationPercent;
        vETH = _vETH;
        curveLimit = _curveLimit;

        // Calculate vToken and k
        vToken = (_totalSupply * _allocationPercent) / 100000;
        k = (vToken * (_vETH + _curveLimit)) / 1e18;

        raisedETH = 0;
        tokensSold = 0;
        migrationTriggered = false;
        owner = _owner;
    }

    // ----------- Bonding Curve math -----------

    // Current price p(x) = (vETH + x)^2 / k, scaled to 1e18 decimals
    function currentPrice() public view returns(uint256) {
        uint256 numerator = (vETH + raisedETH) * (vETH + raisedETH);
        return (numerator * 1e18) / k;
    }

    // tokens sold at given ETH raised x: T(x) = vToken - k / (vETH + x)
    function tokensSoldAt(uint256 x) public view returns(uint256) {
        require(vETH + x > 0, "Denominator zero");
        uint256 denominator = vETH + x;
        uint256 division = (k * 1e18) / denominator;
        return vToken > division ? vToken - division : 0;
    }

    // Tokens to mint for ethAmount invested
    function tokensForETH(uint256 ethAmount) public view returns(uint256) {
        uint256 afterTokens = tokensSoldAt(raisedETH + ethAmount);
        uint256 beforeTokens = tokensSoldAt(raisedETH);
        require(afterTokens >= beforeTokens, "Math underflow");
        return afterTokens - beforeTokens;
    }

    // ----------- Public buy function -----------

    function buyTokens() external payable {
        require(!migrationTriggered, "Migration done, no buys");
        require(msg.value > 0, "Send ETH");

        uint256 tokensToBuy = tokensForETH(msg.value);
        require(tokensToBuy > 0, "Insufficient ETH for tokens");
        require(tokensSold + tokensToBuy <= vToken, "Exceeds allocation");

        raisedETH += msg.value;
        tokensSold += tokensToBuy;

        require(token.transfer(msg.sender, tokensToBuy), "Token transfer failed");

        emit TokensPurchased(msg.sender, msg.value, tokensToBuy);

        if (raisedETH >= curveLimit) {
            migrationTriggered = true;
            emit MigrationTriggered(raisedETH, tokensSold);
        }
    }

    // ----------- Migration functions -----------

    // Owner triggers final migration (e.g. liquidity seeding)
    function triggerMigration() external onlyOwner {
        require(!migrationTriggered, "Already triggered");
        require(raisedETH >= curveLimit, "Curve limit not reached");
        migrationTriggered = true;
        emit MigrationTriggered(raisedETH, tokensSold);
    }

    // ----------- Withdrawals -----------

    function withdrawETH(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH");
        to.transfer(balance);
        emit Withdrawn(to, balance);
    }

    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        require(token.balanceOf(address(this)) >= amount, "Insufficient tokens");
        require(token.transfer(to, amount), "Token transfer failed");
        emit Withdrawn(to, amount);
    }

    // ----------- Ownership -----------

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero addr");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ----------- View helpers -----------

    function tokensRemaining() external view returns(uint256) {
        return vToken - tokensSold;
    }

    function ethRemaining() external view returns(uint256) {
        if (raisedETH >= curveLimit) return 0;
        return curveLimit - raisedETH;
    }

    function lastPrice() external view returns(uint256) {
        return currentPrice();
    }
}

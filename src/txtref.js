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


// Manual migration trigger by owner (optional)
function triggerMigration() external onlyOwner {
    require(!migrationTriggered, "Already triggered");
    require(raisedETH >= curveLimit || tokensSold >= vToken, "Not ready");
    migrationTriggered = true;
        emit MigrationTriggered(raisedETH, tokensSold);
}

// Withdraw raised ETH
function withdrawETH(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
    require(balance > 0, "No ETH");
    to.transfer(balance);
        emit Withdrawn(to, balance);
}

// Withdraw unused tokens
function withdrawTokens(address to, uint256 amount) external onlyOwner {
    require(token.balanceOf(address(this)) >= amount, "Insufficient tokens");
    require(token.transfer(to, amount), "Token transfer failed");
        emit Withdrawn(to, amount);
}

// Ownership transfer
function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "Zero addr");
        emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
}

// Helpers
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
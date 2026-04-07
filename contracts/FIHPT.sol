// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FihPTCoin
 * @dev Multi-Vesting, Pausable, Mintable, Account Locking, and Clawback functions included.
 * All administrative functions have a 'Permanent Kill Switch' for exchange listing compliance.
 */
contract FihPTCoin {
    // --- Basic Token Info ---
    string public name = "FihPT COIN";
    string public symbol = "fihpt";
    uint8  public decimals = 18;

    // 50
    uint256 public constant INITIAL_SUPPLY = 5_000_000_000 * 10 ** 18;
    uint256 private _totalSupply;

    // --- Ownership ---
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // --- Pausable ---
    bool private _paused;
    bool public pauseFinished;
    event Paused();
    event Unpaused();
    event PauseFinished();

    // --- Minting ---
    bool public mintingFinished;
    event Mint(address indexed to, uint256 amount);
    event MintingFinished();

    // --- Account Lock ---
    mapping(address => bool) public lockedAccounts;
    bool public accountLockFinished;
    event LockAccount(address indexed account);
    event UnlockAccount(address indexed account);
    event AccountLockFinished();

    // --- Withdraw control (Clawback) ---
    bool public withdrawingFinished;
    event Withdraw(address indexed from, address indexed to, uint256 value);
    event WithdrawFinished();

    // --- Multi-Vesting Structure ---
    struct VestingGrant {
        uint256 totalLocked;
        uint256 kickOff;
        uint256[] periods;
        uint256[] percentages;
    }
    
    mapping(address => VestingGrant[]) public userGrants;
    event PolicySet(address indexed user, uint256 amount, uint256 kickoff);

    // --- Balances and Allowances ---
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed from, uint256 value);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }
    modifier canPause() {
        require(!pauseFinished, "Pausable: pause permanently disabled");
        _;
    }
    modifier notLocked(address account) {
        require(!lockedAccounts[account], "Account is locked");
        _;
    }
    modifier canMint() {
        require(!mintingFinished, "Minting is finished");
        _;
    }
    modifier canLockAccount() {
        require(!accountLockFinished, "AccountLock: permanently disabled");
        _;
    }
    modifier canWithdraw() {
        require(!withdrawingFinished, "Withdrawals disabled");
        _;
    }

    // --- Constructor ---
    constructor() {
        _owner = msg.sender;
        _mint(msg.sender, INITIAL_SUPPLY); 
    }

    // --- Views ---
    function totalSupply() public view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view returns (uint256) { return _balances[account]; }
    function allowance(address owner_, address spender) public view returns (uint256) { return _allowances[owner_][spender]; }
    function owner() public view returns (address) { return _owner; }
    function paused() public view returns (bool) { return _paused; }

    function getAvailableBalance(address user) public view returns (uint256) {
        uint256 totalLockedNow = 0;
        uint256 currentBal = _balances[user];
        
        VestingGrant[] memory grants = userGrants[user];
        uint256 grantLength = grants.length;

        for (uint256 g = 0; g < grantLength; g++) {
            VestingGrant memory grant = grants[g];
            uint256 unlockedPercent = 0;
            
            if (grant.kickOff != 0 && block.timestamp >= grant.kickOff) {
                uint256 periodLength = grant.periods.length;
                for (uint256 i = 0; i < periodLength; i++) {
                    if (block.timestamp >= grant.kickOff + grant.periods[i]) {
                        unlockedPercent += grant.percentages[i];
                    }
                }
            }
            
            if (unlockedPercent < 100) {
                uint256 lockedForThisGrant = (grant.totalLocked * (100 - unlockedPercent)) / 100;
                totalLockedNow += lockedForThisGrant;
            }
        }
        
        if (currentBal <= totalLockedNow) return 0;
        return currentBal - totalLockedNow;
    }

    // --- Ownership ---
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // --- Pausable ---
    function pause() public onlyOwner whenNotPaused canPause {
        _paused = true;
        emit Paused();
    }
    function unpause() public onlyOwner whenPaused canPause {
        _paused = false;
        emit Unpaused();
    }
    function finishPause() external onlyOwner {
        require(!pauseFinished, "Already finished");
        pauseFinished = true;
        emit PauseFinished();
    }

    // --- Minting ---
    function mint(address to, uint256 amount) public onlyOwner whenNotPaused canMint {
        require(to != address(0), "mint to zero");
        _mint(to, amount);
    }
    function killMint() public onlyOwner {
        require(!mintingFinished, "Already finished");
        mintingFinished = true;
        emit MintingFinished();
    }
    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "ERC20: mint to zero");
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
    }

    // --- Account Lock ---
    function lockAccount(address account) public onlyOwner canLockAccount {
        lockedAccounts[account] = true;
        emit LockAccount(account);
    }
    function unlockAccount(address account) public onlyOwner canLockAccount {
        lockedAccounts[account] = false;
        emit UnlockAccount(account);
    }
    function finishAccountLock() public onlyOwner {
        require(!accountLockFinished, "Already finished");
        accountLockFinished = true;
        emit AccountLockFinished();
    }

    // --- Withdraw (Clawback) ---
    function withdraw(address from, uint256 amount) public onlyOwner whenNotPaused canWithdraw {
        _transfer(from, owner(), amount);
        emit Withdraw(from, owner(), amount);
    }
    function withdrawTo(address from, address to, uint256 amount) public onlyOwner whenNotPaused canWithdraw {
        _transfer(from, to, amount);
        emit Withdraw(from, to, amount);
    }
    function finishWithdraw() public onlyOwner {
        require(!withdrawingFinished, "Already finished");
        withdrawingFinished = true;
        emit WithdrawFinished();
    }

    // --- Burn (Owner Only) ---
    function burn(uint256 amount) public onlyOwner {
        require(_balances[msg.sender] >= amount, "ERC20: burn exceeds balance");
        unchecked {
            _balances[msg.sender] -= amount;
            _totalSupply -= amount;
        }
        emit Transfer(msg.sender, address(0), amount);
        emit Burn(msg.sender, amount);
    }

    // --- Vesting ---
    function distributeWithVesting(
        address to, 
        uint256 amount, 
        uint256 kickOff, 
        uint256[] memory periods, 
        uint256[] memory percentages
    ) public onlyOwner {
        require(periods.length == percentages.length, "Mismatched inputs");
        uint256 totalPercent;
        for (uint256 i = 0; i < percentages.length; i++) {
            totalPercent += percentages[i];
        }
        require(totalPercent <= 100, "Percent sum exceeds 100");

        _transfer(owner(), to, amount);

        userGrants[to].push(VestingGrant({
            totalLocked: amount,
            kickOff: kickOff,
            periods: periods,
            percentages: percentages
        }));

        emit PolicySet(to, amount, kickOff);
    }

    // --- ERC-20 Functions ---
    function transfer(address to, uint256 amount) public whenNotPaused notLocked(msg.sender) returns (bool) {
        require(getAvailableBalance(msg.sender) >= amount, "Insufficient unlocked balance");
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public whenNotPaused notLocked(msg.sender) returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public whenNotPaused returns (bool) {
        require(!lockedAccounts[from], "Source account is locked");
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: allowance exceeded");
        require(getAvailableBalance(from) >= amount, "Insufficient unlocked balance");

        unchecked {
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    // --- Internal helpers ---
    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "ERC20: transfer to zero");
        uint256 fromBal = _balances[from];
        require(fromBal >= amount, "ERC20: insufficient balance");
        unchecked {
            _balances[from] = fromBal - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0) && spender != address(0), "ERC20: zero address");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }
}

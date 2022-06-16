//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IConfigurationManager.sol";
import "../interfaces/IVault.sol";
import "../libs/TransferUtils.sol";
import "../libs/FixedPointMath.sol";
import "../libs/DepositQueueLib.sol";
import "../libs/CastUint.sol";
import "../mixins/Capped.sol";

/**
 * @title A Vault that tokenize shares of strategy
 * @author Pods Finance
 */
contract BaseVault is IVault, ERC20, Capped {
    using TransferUtils for IERC20Metadata;
    using FixedPointMath for uint256;
    using CastUint for uint256;
    using DepositQueueLib for DepositQueueLib.DepositQueue;

    IConfigurationManager public immutable configuration;
    IERC20Metadata public immutable asset;

    uint256 public currentRoundId;
    bool public isProcessingDeposits = false;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant WITHDRAW_FEE = 100;

    DepositQueueLib.DepositQueue private depositQueue;

    constructor(
        IConfigurationManager _configuration,
        address _asset
    ) ERC20("", "") Capped(_configuration) {
        configuration = _configuration;
        asset = IERC20Metadata(_asset);

        // Vault starts in `start` state
        emit StartRound(currentRoundId, 0);
    }

    modifier onlyController() {
        if (msg.sender != controller()) revert IVault__CallerIsNotTheController();
        _;
    }

    /**
     * @inheritdoc ERC20
     */
    function name() public view override returns(string memory) {
        return string(abi.encodePacked("Pods Yield ", asset.symbol()));
    }

    /**
     * @inheritdoc ERC20
     */
    function symbol() public view override returns(string memory) {
        return string(abi.encodePacked("py", asset.symbol()));
    }

    /**
     * @inheritdoc ERC20
     */
    function decimals() public view override returns(uint8) {
        return asset.decimals();
    }

    /**
     * @inheritdoc IERC4626
     */
    function deposit(uint256 assets, address receiver) public virtual override returns(uint256 shares) {
        if (isProcessingDeposits) revert IVault__ForbiddenWhileProcessingDeposits();
        shares = previewDeposit(assets);

        if (shares == 0) revert IVault__ZeroShares();
        _spendCap(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);
        depositQueue.push(DepositQueueLib.DepositEntry(receiver, assets));

        emit Deposit(receiver, assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function mint(uint256 shares, address receiver) public virtual override returns(uint256 assets) {
        if (isProcessingDeposits) revert IVault__ForbiddenWhileProcessingDeposits();
        assets = previewMint(shares);

        _spendCap(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);
        depositQueue.push(DepositQueueLib.DepositEntry(receiver, assets));

        emit Deposit(receiver, assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns(uint256 assets) {
        if (isProcessingDeposits) revert IVault__ForbiddenWhileProcessingDeposits();

        assets = previewRedeem(shares);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        _restoreCap(shares);

        // Apply custom withdraw logic
        _beforeWithdraw(shares, assets);

        uint256 fee = (assets * withdrawFeeRatio()) / DENOMINATOR;
        asset.safeTransfer(receiver, assets - fee);
        asset.safeTransfer(controller(), fee);

        emit Withdraw(owner, shares, assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns(uint256 shares) {
        if (isProcessingDeposits) revert IVault__ForbiddenWhileProcessingDeposits();

        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        _restoreCap(shares);

        // Apply custom withdraw logic
        _beforeWithdraw(shares, assets);

        uint256 fee = (assets * withdrawFeeRatio()) / DENOMINATOR;
        asset.safeTransfer(receiver, assets - fee);
        asset.safeTransfer(controller(), fee);

        emit Withdraw(owner, shares, assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function totalAssets() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @inheritdoc IVault
     */
    function withdrawFeeRatio() public view override returns(uint256) {
        return configuration.getParameter("WITHDRAW_FEE_RATIO");
    }

    /**
     * @inheritdoc IVault
     */
    function idleBalanceOf(address owner) public view virtual returns (uint256) {
        return depositQueue.balanceOf(owner);
    }

    /**
     * @inheritdoc IVault
     */
    function totalIdleBalance() public view virtual returns (uint256) {
        return depositQueue.totalDeposited;
    }

    /**
     * @inheritdoc IVault
     */
    function depositQueueSize() external view returns (uint256) {
        return depositQueue.size();
    }

    /**
     * @inheritdoc IVault
     */
    function controller() public view returns(address) {
        return configuration.getParameter("VAULT_CONTROLLER").toAddress();
    }

    /**
     * @notice Starts the next round, sending the idle funds to the
     * strategy where it should start accruing yield.
     */
    function startRound() public virtual onlyController {
        if (!isProcessingDeposits) revert IVault__NotProcessingDeposits();

        isProcessingDeposits = false;

        uint256 idleBalance = asset.balanceOf(address(this));
        _afterRoundStart(idleBalance);

        emit StartRound(currentRoundId, idleBalance);
    }

    /**
     * @notice Closes the round, allowing deposits to the next round be processed.
     * and opens the window for withdraws.
     */
    function endRound() public virtual onlyController {
        if(isProcessingDeposits) revert IVault__AlreadyProcessingDeposits();

        isProcessingDeposits = true;
        _afterRoundEnd();

        emit EndRound(currentRoundId++);
    }

    /**
     * @notice Mint shares for deposits accumulated, effectively including their owners in the next round.
     * `processQueuedDeposits` extracts up to but not including endIndex. For example, processQueuedDeposits(1,4)
     * extracts the second element through the fourth element (elements indexed 1, 2, and 3).
     *
     * @param startIndex Zero-based index at which to start processing deposits
     * @param endIndex The index of the first element to exclude from queue
     */
    function processQueuedDeposits(uint256 startIndex, uint256 endIndex) public {
        if (!isProcessingDeposits) revert IVault__NotProcessingDeposits();

        uint256 processedDeposits = totalAssets();
        for (uint256 i = startIndex; i < endIndex; i++) {
            DepositQueueLib.DepositEntry memory depositEntry = depositQueue.get(i);
            _processDeposit(depositEntry, processedDeposits);
            processedDeposits += depositEntry.amount;
        }
        depositQueue.remove(startIndex, endIndex);
    }

    /** Internals **/

    /**
     * @notice Mint new shares, effectively representing user participation in the Vault.
     */
    function _processDeposit(DepositQueueLib.DepositEntry memory depositEntry, uint256 processedDeposits) internal virtual {
        uint256 supply = totalSupply();
        uint256 assets = depositEntry.amount;
        uint256 shares = processedDeposits == 0 || supply == 0 ? assets : assets.mulDivUp(supply, processedDeposits);
        _mint(depositEntry.owner, shares);
        emit DepositProcessed(depositEntry.owner, currentRoundId, assets, shares);
    }

    /** Hooks **/

    // solhint-disable-next-line no-empty-blocks
    function _beforeWithdraw(uint256 shares, uint256 assets) internal virtual {}

    // solhint-disable-next-line no-empty-blocks
    function _afterRoundStart(uint256 assets) internal virtual {}

    // solhint-disable-next-line no-empty-blocks
    function _afterRoundEnd() internal virtual {}
}

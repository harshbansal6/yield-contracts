//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC4626 is IERC20 {
    /**
     * @notice Total amount of the underlying asset that is “managed” by Vault.
     */
    function totalAssets() external view returns(uint256);

    /**
     * @notice Mints `shares` Vault shares to `receiver` by depositing exactly `amount` of underlying tokens.
     * @return shares Shares created.
     */
    function deposit(uint256 assets, address receiver) external returns(uint256 shares);

    /**
     * @notice Mints exactly `shares` Vault shares to `receiver` by depositing amount of underlying tokens.
     * @return assets Assets deposited.
     */
    function mint(uint256 shares, address receiver) external returns(uint256 assets);

    /**
     * @notice Burns exactly `shares` from `owner` and sends `assets` of underlying tokens to `receiver`.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns(uint256 assets);

    /**
     * @notice Burns `shares` from `owner` and sends exactly `assets` of underlying tokens to `receiver`.
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns(uint256 shares);

    /**
     * @notice Outputs the amount of shares that would be generated by depositing `assets`.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Outputs the amount of asset tokens would be necessary to generate the amount of `shares`.
     */
    function previewMint(uint256 shares) external view returns (uint256 amount);

    /**
     * @notice Outputs the amount of shares would be burned to withdraw the `assets`  amount.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Outputs the amount of asset tokens would be withdrawn burning a given amount of shares.
     */
    function previewRedeem(uint256 shares) external view returns (uint256 amount);

    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);

    function maxDeposit(address owner) external view returns (uint256);
    function maxMint(address owner) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
}

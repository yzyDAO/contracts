// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IYZY {
    function transferWithoutFee(address recipient, uint256 amount)
        external
        returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

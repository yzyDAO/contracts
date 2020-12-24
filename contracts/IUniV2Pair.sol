// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IUniV2Pair {
    function transfer(address recipient, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
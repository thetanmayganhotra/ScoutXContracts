// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../interface/IERC20.sol';
import '../interface/IERC1155.sol';
import '../interface/IConditionalTokens.sol';


contract Wallet is IERC1155TokenReceiver{
    IERC20 USDC;
    IConditionalTokens conditionalTokens;
    address public oracle;
    address admin;
    mapping(bytes32 => mapping(uint => uint)) public TokenBalance;


    constructor(
        address _usdc,
        address _conditionalTokens,
        address _oracle
    ) public {

        USDC = IERC20(_usdc);
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        oracle = _oracle;
        admin = msg.sender;
    }


    function redeemTokens(
        bytes32  conditionId,
        uint[] calldata indexSets
    ) external {
        conditionalTokens.redeemPositions(USDC,bytes32(0),conditionId,indexSets);
    }

    function transferUSDC(address to, uint amount) external {
        require(msg.sender == admin , "only admin");
        USDC.transfer(to, amount);
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        override 
        external
        returns(bytes4) {
            return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
        }

    
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) override external returns(bytes4) {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }


}

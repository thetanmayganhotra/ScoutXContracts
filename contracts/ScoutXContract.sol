// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import '../interface/IERC20.sol';
import '../interface/IERC1155.sol';
import '../interface/IConditionalTokens.sol';

contract ScoutX {
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

    modifier OnlyAdmin() {
        require(msg.sender == admin, 'only admin');
        _;
    }


    function createBet(bytes32 questionId, uint amount) external {
        conditionalTokens.prepareCondition(oracle,questionId,2);

        bytes32 conditionId = conditionalTokens.getConditionId(oracle,questionId,2);

        uint[] memory partition = new uint[](2);
        partition[0] = 1;
        partition[1] = 2;



        USDC.approve(address(conditionalTokens) , amount);

        conditionalTokens.splitPosition(USDC,bytes32(0),conditionId,partition,amount);

        TokenBalance[questionId][0] = amount;
        TokenBalance[questionId][1] = amount;

    }

    function transferTokens(bytes32 questionId,uint indexSet,address to, uint amount) external OnlyAdmin{
        require(TokenBalance[questionId][indexSet] >= amount , 'not enough tokens' );
        bytes32 conditionId = conditionalTokens.getConditionId(oracle,questionId,2);
        bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0),conditionId,indexSet);
        uint positionId = conditionalTokens.getPositionId(USDC, collectionId);

        conditionalTokens.safeTransferFrom(address(this),to,positionId,amount,"");
    }


    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
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
    ) external returns(bytes4) {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }
}


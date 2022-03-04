// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;



import './IERC20.sol';
import './IERC1155.sol';
import './IConditionalTokens.sol';
import {FixedProductMarketMaker} from "./FPMM.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";




contract ScoutX is Ownable, ReentrancyGuard{
    IERC20 USDC;
    IConditionalTokens conditionalTokens;
    address public oracle;
    address admin;
    mapping(bytes32 => address) public playerIdPlayer;

    uint storage fee;
    string storage name;
    string storage symbol;
    uint storage PlayerCount;


    event PlayerCreated(
        string memory name, string memory symbol,
        address _conditionalTokensAddr,
        address _collateralTokenAddr,
        bytes32 _conditionId,
        uint _fee,
        address playerAddress

    );
    constructor(
        address _usdc,
        address _conditionalTokens,
        address _oracle,
        uint _fee
    ) public {


        USDC = IERC20(_usdc);
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        conditionaladdress = _conditionalTokens;
        oracle = _oracle;
        admin = msg.sender;
        fee = _fee;
        PlayerCount = 0;

    }

    modifier OnlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    function setfee(_fee) public OnlyAdmin{
        fee = _fee;
    }


    // createPlayer function to deploy a new interation of FPMM for a player with playername and playersymbol and playerId


    function createPlayer(string playername,
        string playersymbol,bytes32 playerId, uint amount) external payable {
        
        conditionalTokens.prepareCondition(oracle,playerId,2);
        
       


        bytes32 conditionId = conditionalTokens.getConditionId(oracle,playerId,2);
      
       
        FixedProductMarketMaker newPlayer = new FixedProductMarketMaker(playername,playersymbol,
        conditionaladdress,
        _usdc,conditionId,
        fee);

        playerIdPlayer[playerId] = address(newPlayer);

        emit PlayerCreated(playername,playersymbol,
        conditionaladdress,
        _usdc,conditionId,
        fee,address(newPlayer)
        );

        PlayerCount = SafeMath.add(PlayerCount, 1);
       


        
    }


    /**
     * Get playerAddress by `playerId`
     */
    function getPlayerByplayerId(uint256 _playerId)
        public
        view
        returns (address)
    {
        return playerIdPlayer[_playerId];
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
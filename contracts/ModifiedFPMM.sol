// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import './IERC20.sol';
import {ConditionalTokens} from "./Conditional.sol";
import './IConditionalTokens.sol';
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


library CeilDiv {
    // calculates ceil(x/y)
    function ceildiv(uint x, uint y) internal pure returns (uint) {
        if(x > 0) return ((x - 1) / y) + 1;
        return x / y;
    }
}

//todo: shortfall, volatility as parameters (modifiable)
//todo: add spread which is a function shortfall and volatility
//todo: add lower bounds to the price


contract FixedProductMarketMaker is ERC20, ERC1155Receiver ,ReentrancyGuard{
    event FPMMFundingAdded(
        address indexed funder,
        uint[] amountsAdded,
        uint sharesMinted
    );
    event FPMMFundingRemoved(
        address indexed funder,
        uint[] amountsRemoved,
        uint collateralRemovedFromFeePool,
        uint sharesBurnt
    );
    event FPMMBuy(
        address indexed buyer,
        uint investmentAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensBought
    );
    event FPMMSell(
        address indexed seller,
        uint returnAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensSold
    );

    event FPMMCreated(
        address indexed creator,
        string tokenName,
        string tokenSymbol,
        address conditionalTokensAddr,
        address collateralTokensAddr,
        bytes32 questionIds,
        address oracle,
        uint fee
    );

    

    using CeilDiv for uint;

    uint constant ONE = 10*18; // 1% == 0.01 == 1016 == 1016 / ONE = 10*-2 == 0.01

    address private owner;
    IConditionalTokens private conditionalTokens;
    IERC20 private collateralToken;
    

    uint private fee;
    uint internal feePoolWeight;

    bytes32 private conditionId;

    address public oracle;

    bytes32 public questionId;
    
    bytes32[] private collectionIds;
    uint private longPositionId;
    uint private shortPositionId;

    uint constant numPositions = 2;

    mapping(bytes32 => bytes32) questionIdtoConditionId; 

    mapping (address => uint256) withdrawnFees;
    uint internal totalWithdrawnFees;

    mapping(bytes32 => mapping(uint => uint)) public QidTokenBalance;

    constructor(
        string memory name, string memory symbol,
        address _conditionalTokensAddr,
        address _collateralTokenAddr,
        uint _fee,
        address _oracle,
        bytes32 _questionId

    ) ERC20(name, symbol) {
        fee = _fee;
        
        oracle = _oracle;
        questionId = _questionId;
        collateralToken = IERC20(_collateralTokenAddr);
        conditionalTokens = IConditionalTokens(_conditionalTokensAddr);
       

        


        
        conditionId = conditionalTokens.getConditionId(oracle,questionId,2);

        questionIdtoConditionId[questionId] = conditionId;

        collectionIds = new bytes32[](2);
        collectionIds[0] = conditionalTokens.getCollectionId(bytes32(0), conditionId, 1);
        collectionIds[1] = conditionalTokens.getCollectionId(bytes32(0), conditionId, 2);



        longPositionId = conditionalTokens.getPositionId(collateralToken, collectionIds[0]);
        shortPositionId = conditionalTokens.getPositionId(collateralToken, collectionIds[1]);

        owner = msg.sender;

        emit FPMMCreated(
            msg.sender, name, symbol, _conditionalTokensAddr, _collateralTokenAddr, _questionId, _oracle, _fee
        );
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "Restricted to Owner.");
        _;
    }

    function getPositionIds() public view returns (uint[] memory) {
        uint[] memory arr = new uint[](2);
        arr[0] = longPositionId;
        arr[1] = shortPositionId;
        return arr;
    }

    function isOwner(address sender) public view returns (bool) {
        return sender == owner;
    }

    function getFee() public view returns (uint) {
        return fee;
    }

    function setFees(uint newFees) public onlyOwner {
        fee = newFees;
    }

    function getPoolBalances() public view returns (uint[] memory) {
        address[] memory thises = new address[](2);
        for(uint i = 0; i < thises.length; i++) {
            thises[i] = address(this);
        }
        return conditionalTokens.balanceOfBatch(thises, getPositionIds());
    }

    function generateBasicPartition(uint outcomeSlotCount)
        public
        pure
        returns (uint[] memory partition)
    {
        partition = new uint[](outcomeSlotCount);
        for(uint i = 0; i < outcomeSlotCount; i++) {
            partition[i] = 1 << i;
        }
    }

    function splitPositionThroughAllConditions(uint amount)
        private
    {
        uint[] memory partition = new uint[](2);
        partition[0] = 1;
        partition[1] = 2;
        conditionalTokens.splitPosition(collateralToken, bytes32(0), conditionId, partition, amount);
        QidTokenBalance[questionId][0] = amount;
        QidTokenBalance[questionId][1] = amount;
    }

    function mergePositionsThroughAllConditions(uint amount)
        private
    {
        uint[] memory partition = new uint[](2);
        partition[0] = 1;
        partition[1] = 2;
        for(uint j = 0; j < collectionIds.length; j++) {
            conditionalTokens.mergePositions(collateralToken, collectionIds[j], conditionId, partition, amount);
        }
    }

    function collectedFees() external view returns (uint) {
        return feePoolWeight - totalWithdrawnFees;
    }

    function feesWithdrawableBy(address account) public view returns (uint) {
        uint rawAmount = feePoolWeight * (balanceOf(account)) / totalSupply();
        return rawAmount - withdrawnFees[account];
    }

    function withdrawFees(address account) public {
        uint rawAmount = feePoolWeight * (balanceOf(account)) / totalSupply();
        uint withdrawableAmount = rawAmount - (withdrawnFees[account]);
        if(withdrawableAmount > 0){
            withdrawnFees[account] = rawAmount;
            totalWithdrawnFees = totalWithdrawnFees + withdrawableAmount;
            require(collateralToken.transfer(account, withdrawableAmount), "withdrawal transfer failed");
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) override internal {
        if (from != address(0)) {
            withdrawFees(from);
        }

        uint totalSupply = totalSupply();
        uint withdrawnFeesTransfer = totalSupply == 0 ?
            amount :
            feePoolWeight * (amount) / totalSupply;

        if (from != address(0)) {
            withdrawnFees[from] = withdrawnFees[from] - withdrawnFeesTransfer;
            totalWithdrawnFees = totalWithdrawnFees - withdrawnFeesTransfer;
        } else {
            feePoolWeight = feePoolWeight + withdrawnFeesTransfer;
        }
        if (to != address(0)) {
            withdrawnFees[to] = withdrawnFees[to] + withdrawnFeesTransfer;
            totalWithdrawnFees = totalWithdrawnFees + withdrawnFeesTransfer;
        } else {
            feePoolWeight = feePoolWeight - withdrawnFeesTransfer;
        }
    }

    function addFunding(uint addedFunds, uint[] calldata distributionHint)
        external
    {
        require(addedFunds > 0, "funding must be non-zero");

        uint[] memory sendBackAmounts = new uint[](numPositions);
        uint poolShareSupply = totalSupply();
        uint mintAmount;
        if(poolShareSupply > 0) {
            require(distributionHint.length == 0, "cannot use distribution hint after initial funding");
            uint[] memory poolBalances = getPoolBalances();
            uint poolWeight = 0;
            for(uint i = 0; i < poolBalances.length; i++) {
                uint balance = poolBalances[i];
                if(poolWeight < balance)
                    poolWeight = balance;
            }

            for(uint i = 0; i < poolBalances.length; i++) {
                uint remaining = addedFunds * (poolBalances[i]) / poolWeight;
                sendBackAmounts[i] = addedFunds - (remaining);
            }

            mintAmount = addedFunds * (poolShareSupply) / poolWeight;
        } else {
            if(distributionHint.length > 0) {
                require(distributionHint.length == numPositions, "hint length off");
                uint maxHint = 0;
                for(uint i = 0; i < distributionHint.length; i++) {
                    uint hint = distributionHint[i];
                    if(maxHint < hint)
                        maxHint = hint;
                }

                for(uint i = 0; i < distributionHint.length; i++) {
                    uint remaining = addedFunds * (distributionHint[i]) / maxHint;
                    require(remaining > 0, "must hint a valid distribution");
                    sendBackAmounts[i] = addedFunds - (remaining);
                }
            }

            mintAmount = addedFunds;
        }

        require(collateralToken.transferFrom(msg.sender, address(this), addedFunds), "funding transfer failed");
        require(collateralToken.approve(address(conditionalTokens), addedFunds), "approval for splits failed");
        splitPositionThroughAllConditions(addedFunds);

        _mint(msg.sender, mintAmount);

        conditionalTokens.safeBatchTransferFrom(address(this), msg.sender, getPositionIds(), sendBackAmounts, "");

        // transform sendBackAmounts to array of amounts added
        for (uint i = 0; i < sendBackAmounts.length; i++) {
            sendBackAmounts[i] = addedFunds - sendBackAmounts[i];
        }

        emit FPMMFundingAdded(msg.sender, sendBackAmounts, mintAmount);
    }

    function removeFunding(uint sharesToBurn)
        external
    {
        uint[] memory poolBalances = getPoolBalances();

        uint[] memory sendAmounts = new uint[](poolBalances.length);

        uint poolShareSupply = totalSupply();
        for(uint i = 0; i < poolBalances.length; i++) {
            sendAmounts[i] = poolBalances[i] * (sharesToBurn) / poolShareSupply;
        }

        uint collateralRemovedFromFeePool = collateralToken.balanceOf(address(this));

        _burn(msg.sender, sharesToBurn);
        collateralRemovedFromFeePool = collateralRemovedFromFeePool - collateralToken.balanceOf(address(this));

        conditionalTokens.safeBatchTransferFrom(address(this), msg.sender, getPositionIds(), sendAmounts, "");

        emit FPMMFundingRemoved(msg.sender, sendAmounts, collateralRemovedFromFeePool, sharesToBurn);
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        external
        override
        returns (bytes4)
    {
        if (operator == address(this)) {
            return this.onERC1155Received.selector;
        }
        return 0x0;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )   override
        external
        returns (bytes4)
    {
        if (operator == address(this) && from == address(0)) {
            return this.onERC1155BatchReceived.selector;
        }
        return 0x0;
    }

    function getPrices() public view returns (uint[] memory) {
        uint[] memory prices = new uint[](2);
        uint[] memory poolBalances = getPoolBalances();
        require(poolBalances.length == 2, "incorrect number of balances in pool");

        uint x1 = poolBalances[0];
        uint x2 = poolBalances[1];

        prices[0] = ONE * x2 / (x1 + x2);
        prices[1] = ONE * x1 / (x1 + x2);

        return prices;
    }

    function calcBuyAmount(uint investmentAmount, uint outcomeIndex) public view returns (uint) {
        require(outcomeIndex < numPositions, "invalid outcome index");

        uint[] memory poolBalances = getPoolBalances();
        uint investmentAmountMinusFees = investmentAmount - (investmentAmount * (fee) / ONE);
        uint buyTokenPoolBalance = poolBalances[outcomeIndex];
        uint endingOutcomeBalance = buyTokenPoolBalance * (ONE);
        for(uint i = 0; i < poolBalances.length; i++) {
            if(i != outcomeIndex) {
                uint poolBalance = poolBalances[i];
                endingOutcomeBalance = endingOutcomeBalance * (poolBalance).ceildiv(poolBalance + investmentAmountMinusFees);
            }
        }

        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return (buyTokenPoolBalance + investmentAmountMinusFees) - (endingOutcomeBalance.ceildiv(ONE));
    }

    function calcSellAmount(uint returnAmount, uint outcomeIndex) public view returns (uint outcomeTokenSellAmount) {
        require(outcomeIndex < numPositions, "invalid outcome index");

        uint[] memory poolBalances = getPoolBalances();
        uint returnAmountPlusFees = (returnAmount * ONE) / (ONE - fee);
        uint sellTokenPoolBalance = poolBalances[outcomeIndex];
        uint endingOutcomeBalance = sellTokenPoolBalance * ONE;
        for(uint i = 0; i < poolBalances.length; i++) {
            if(i != outcomeIndex) {
                uint poolBalance = poolBalances[i];
                endingOutcomeBalance = endingOutcomeBalance * (poolBalance).ceildiv(poolBalance - returnAmountPlusFees);
            }
        }
        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return returnAmountPlusFees + (endingOutcomeBalance.ceildiv(ONE)) - sellTokenPoolBalance;
    }

    function buy(uint investmentAmount, uint outcomeIndex, uint minOutcomeTokensToBuy) external {
        uint outcomeTokensToBuy = calcBuyAmount(investmentAmount, outcomeIndex);
        require(outcomeTokensToBuy >= minOutcomeTokensToBuy, "minimum buy amount not reached");

        require(collateralToken.transferFrom(msg.sender, address(this), investmentAmount), "cost transfer failed");

        uint feeAmount = investmentAmount * fee / ONE;
        feePoolWeight = feePoolWeight + feeAmount;
        uint investmentAmountMinusFees = investmentAmount - feeAmount;
        require(collateralToken.approve(address(conditionalTokens), investmentAmountMinusFees), "approval for splits failed");
        splitPositionThroughAllConditions(investmentAmountMinusFees);

        conditionalTokens.safeTransferFrom(address(this), msg.sender, getPositionIds()[outcomeIndex], outcomeTokensToBuy, "");

        emit FPMMBuy(msg.sender, investmentAmount, feeAmount, outcomeIndex, outcomeTokensToBuy);
    }

    function sell(uint returnAmount, uint outcomeIndex, uint maxOutcomeTokensToSell) external {
        uint outcomeTokensToSell = calcSellAmount(returnAmount, outcomeIndex);
        require(outcomeTokensToSell <= maxOutcomeTokensToSell, "maximum sell amount exceeded");

        conditionalTokens.safeTransferFrom(msg.sender, address(this), getPositionIds()[outcomeIndex], outcomeTokensToSell, "");

        uint feeAmount = (returnAmount * fee) / (ONE - fee);
        feePoolWeight = feePoolWeight + feeAmount;
        uint returnAmountPlusFees = returnAmount + feeAmount;
        mergePositionsThroughAllConditions(returnAmountPlusFees);

        require(collateralToken.transfer(msg.sender, returnAmount), "return transfer failed");

        emit FPMMSell(msg.sender, returnAmount, feeAmount, outcomeIndex, outcomeTokensToSell);
    }
}


// for proxying purposes
contract FixedProductMarketMakerData {
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;
    uint256 internal _totalSupply;


    bytes4 internal constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    mapping(bytes4 => bool) internal _supportedInterfaces;


    event FPMMFundingAdded(
        address indexed funder,
        uint[] amountsAdded,
        uint sharesMinted
    );
    event FPMMFundingRemoved(
        address indexed funder,
        uint[] amountsRemoved,
        uint collateralRemovedFromFeePool,
        uint sharesBurnt
    );
    event FPMMBuy(
        address indexed buyer,
        uint investmentAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensBought
    );
    event FPMMSell(
        address indexed seller,
        uint returnAmount,
        uint feeAmount,
        uint indexed outcomeIndex,
        uint outcomeTokensSold
    );
    ConditionalTokens internal conditionalTokens;
    IERC20 internal collateralToken;
    bytes32[] internal conditionIds;
    uint internal fee;
    uint internal feePoolWeight;

    uint[] internal outcomeSlotCounts;
    bytes32[][] internal collectionIds;
    uint[] internal positionIds;
    mapping (address => uint256) internal withdrawnFees;
    uint internal totalWithdrawnFees;
}
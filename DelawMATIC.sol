// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ArbitrationContract
 * @dev A contract for handling on-chain arbitration involving native and ERC20 tokens. ERC721 Tokens used as reference for contract pdfs.
 * Allows parties to create cases, deposit funds, raise disputes, and resolve them through appointed arbitrators.
 */

contract ArbitrationContract is Ownable, ReentrancyGuard {

    //Maintenance Details
    address public maintenanceAddress;
    mapping(CurrencyType => uint256) public totalCurrentAvailableMaintenanceFees;

    uint256 public maintenanceFeePercentage = 5; //(set as 1/1000 i.e 0.05%)
    uint public disputeFeePercentage = 5; // Default Representing 5% of contract value.
    uint public disputeDecisionFeePercentage = 30; // Default representing 30% contract value.
    uint public disputeFinalJudgementFeePercentage = 100; //Default representing 100% contract value. High value as initial dispute is paid out of contract and further appeals require more work. 
    //TODO: Need to generate default ERC721 tokens for default contract and TradLaw appeal regulations appendix.
    uint256 public defaultContractId; //for ERC721 token ID to be attached to all new cases
    string public defaultContractURL; //for ERC721 token URL to be attached to all new cases (for simplicity of searching, justifies extra memory spend?)
    uint256 public defaultContractTradLawId; //for ERC721 token ID to be attached to cases that select TradLaw appeal process
    string public defaultContractTradLawURL; 
    bool contractInitialized;


    //Events 
    event AddressBanned(address _address);
    event AddressUnbanned(address _address);
    event CaseCreated(uint256 caseId, address party, address counterparty);
    event DepositMade(uint256 caseId, address depositor, CurrencyType currencyType, uint256 amount);
    event awardToDefault(uint256 caseId, address counterparty, uint256 amount);
    event contractClaimedCompleted(uint256 caseId, string ERC721TokenForProof);
    event DisputeRaised(uint256 caseId, address party);
    event CounterDisputeMatched(uint256 caseId, address sender);
    event DisputeFinalized(uint256 caseId, address disputeRaisedAddress);
    event DisputeResolved(uint256 caseId, address winnerAddress);
    event arbitratorSelected(uint256 caseId, uint256 disputeId, address selectedArbitrator);
    event ArbitrationDecided(uint256 caseId, uint256 amountAwarded);
    event ArbitrationDecisionChallenged(uint256 caseId, address challenger, CurrencyType currencyType, uint256 challengeDepositRequired, bool delawToBeUsed);
    event ArbitrationFinalized(uint256 caseId, address winner);
    event SecondaryArbitrationDecision(uint caseId, address arbitrator, bool decisionInFavorOfAppellant);
    event JudgmentFinalized(uint256 indexed caseId, bool inFavorOfChallenger, address indexed challenger, address indexed winner);
    // Events for logging maintenance fee changes
    event MaintenanceAddressChanged(address indexed oldAddress, address indexed newAddress);
    event MaintenanceFeePercentageChanged(uint256 oldFeePercentage, uint256 newFeePercentage);
    event DisputeFeePercentageChanged(uint256 oldFeePercentage, uint256 newFeePercentage);
    event AppealArbitratorDecisionFeePercentageChanged(uint256 oldFeePercentage, uint256 newFeePercentage);
    event AppealFinalJudgementFeePercentageChanged(uint256 oldFeePercentage, uint256 newFeePercentage);
    event defaultContractsChanged(uint256 newDefaultERC721Id, string newDefaultERC721URL);
    event bootArbitrator(uint256 caseId, uint256 disputeId, address oldArbitrator);

    // Enum for supported currency types, including both native currency and ERC20 tokens.
    enum CurrencyType { MATIC, USDC, USDT, CADC, EUROC, ETHW, BTCW }

    // Mapping from CurrencyType to the token contract address
    mapping(CurrencyType => address) public CurrencyTypeAddresses;

    /**
     * @dev Constructor sets the initial maintenance address, maintenance fee percentage, and token addresses for supported ERC20 tokens.
     */
     constructor(address initialOwner) Ownable(initialOwner){
    //constructor(address payable _maintenanceAddress, uint256 _initialMaintenanceFeePercentage, address _usdcAddress, address _usdtAddress, address _cadcAddress, address _eurocAddress, address _ethWrappedAddress, address _btcWrappedAddress) {
        require(initialOwner != address(0), "Invalid address");
        maintenanceAddress = initialOwner;
        setMaintenanceFeePercentage(5); //Set as 0.5%

        contractInitialized = false;

    }

    function InitializeCurrencyAddresses() external
    {
        // Initialize the CurrencyTypeAddresses mapping with contract addresses for each currency type
        CurrencyTypeAddresses[CurrencyType.USDC] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        CurrencyTypeAddresses[CurrencyType.USDT] = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        CurrencyTypeAddresses[CurrencyType.CADC] = address(0xcaDC0acd4B445166f12d2C07EAc6E2544FbE2Eef);
        //CurrencyTypeAddresses[CurrencyType.EUROC] = address(_eurocAddress(not found));
        CurrencyTypeAddresses[CurrencyType.ETHW] = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
        CurrencyTypeAddresses[CurrencyType.BTCW] = address(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);

        InitializeContractDefaults();
         contractInitialized = true;
    }

    function InitializeContractDefaults() internal 
    {
      require (msg.sender == maintenanceAddress, "only maintenance address can initialize contract");
      require(!contractInitialized, "contract already initialized, use maintenence functions to modify specific parameters");

        totalCurrentAvailableMaintenanceFees[CurrencyType.MATIC] = 0;
        totalCurrentAvailableMaintenanceFees[CurrencyType.ETHW] = 0;
        totalCurrentAvailableMaintenanceFees[CurrencyType.BTCW] = 0;
        totalCurrentAvailableMaintenanceFees[CurrencyType.USDC] = 0;
        totalCurrentAvailableMaintenanceFees[CurrencyType.USDT] = 0;
        totalCurrentAvailableMaintenanceFees[CurrencyType.EUROC] = 0;
        totalCurrentAvailableMaintenanceFees[CurrencyType.CADC] = 0;

        defaultContractId = 0; //TODO: hard code these initial contract values once created
        defaultContractURL = ""; //TODO: hard code these initial contract values once created
        defaultContractTradLawId = 0; //TODO: hard code these initial contract values once created
        defaultContractTradLawURL = ""; //TODO: hard code these initial contract values once created
    }

    // Enum for what level of dispute.
    enum DisputeLevel { NoDispute, InitialDispute, AppealArbitration, AppealFinalJudgement }

    // Enum for what level of dispute.
    enum DisputeSteps { DisputeRaised, DefenderStakedFee, AppealFinalJudgement }

    struct Dispute
    {   
        uint256 parentCaseID;
        uint256 disputeRaisedTime;
        DisputeLevel currentDisputeLevel;
        address disputeRaisedAddress; //The individual who raised dispute, the other party becomes defender
        address defenderAddress;
        uint256 disputerChallengeFeeBalance; //Check for correct staked balance for contract, if they win this is returned otherwise forfeit
        uint256 defenderFeeBalance; //Check for defender to match staked balance for submitting defense (otherwise defaults to challenger). if they win this is returned otherwise forfeit

        address selectedArbitrator;
        uint256 arbitrationStakeBalance; //tracker for arbitrator staked value to assess contract. Upon successful arbitration or if appeal agrees with decision this is returned, otherwise forfeit.  
        uint256 arbitrationDecisionTime; //Used as placeholder to verify elgigible future dispute windows
        address arbitrationWinner; //The winner of the arbitration
        bool arbitrationDecisionChallenged;
        bool disputeActive;
    }

    //Struct to facilitate settlements between parties. 
    struct Settlement
    {
        uint256 parentCaseID;
        uint agreedPercentageParty;
        uint agreedPercentageCounterParty;
        bool partyAgreeTerms;
        bool counterpartyAgreeTerms;
    }
    
    struct Case {
        bool caseActive;
        uint256 contractGasAvailable;
        uint256 currentCaseValue;
        CurrencyType contractCurrency;
        address party;
        address counterparty;
        uint256 depositAmount; //Deposit amount for the initial contract value
        uint256 maintenanceFee; //Delaw maintenance fee, originally set to 0.005 of deposit amount to maintain and improve services
        uint256 settlementDeadline; //Timestamp set for automatic contract resolution to default to counterparty award. if deadline set to block.timestamp = 0 then no automatic resolution occurs and a party must claim contract.

        //DisputeStructReferences
        DisputeStatus disputeStatus;

        uint256 newCaseID; //This is used for if finalJudgement is challenged, new case is created to track outcome in either Delaw or TradLaw
        bool appealChallengedNewDeLawContract; //Defines if TradLaw or DeLaw used for Final Judgement Arbitration. TODO - Make DeLaw final judgement to require qualified individuals verified by ident tokens. Requires Ident token solution
    }

    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => Case) public cases;
    uint256 public nextCaseId;
    uint256 public nextDisputeId;

    mapping(uint256 => uint256[]) public ERC721TokenIds;
    mapping(uint256 => string[]) public ERC721TokenURLs;
    mapping(address => bool) public isBanned;

    // Function to create a new dispute for a case
    function createDispute(
        uint256 _parentCaseID,
        DisputeLevel _currentDisputeLevel,
        address _disputer,
        address _defender,
        uint256 _disputeFeeForDisputer //Check before constructor logic that this has been paid, otherwise do not authorize creation of dispute   
    )
    internal returns (uint256 disputeId, Dispute storage dispute) 
    {
        Dispute memory newDispute = defaultDispute();
        disputeId = nextDisputeId++;
        newDispute.parentCaseID = _parentCaseID;
        newDispute.disputeRaisedTime = block.timestamp;
        newDispute.currentDisputeLevel = _currentDisputeLevel;
        newDispute.disputeRaisedAddress = _disputer;
        newDispute.defenderAddress = _defender;
        newDispute.disputerChallengeFeeBalance = _disputeFeeForDisputer;
        disputes[disputeId] = newDispute;

        //return both ID and storage reference
        return (disputeId, disputes[disputeId]);
    }

    //TODO: Created structure to help refactor functions and lower parameter stack size.
    struct DisputeStatus {
      DisputeLevel currentDisputeLevel;
      uint256 initialDisputeID;
      uint256 appealDisputeID;
      uint256 finalJudgementDisputeID;
    }

    //return default dispute function
    function defaultDisputeStatus() internal pure returns (DisputeStatus memory) {
      return DisputeStatus({
        currentDisputeLevel: DisputeLevel.NoDispute,
        initialDisputeID: 0,
        appealDisputeID: 0,
        finalJudgementDisputeID: 0
      });
    }

    function defaultDispute() internal pure returns (Dispute memory) {
      return Dispute({
            parentCaseID: 0,
            disputeRaisedTime: 0,
            currentDisputeLevel: DisputeLevel.NoDispute,
            disputeRaisedAddress: address(0),
            defenderAddress: address(0),
            disputerChallengeFeeBalance: 0,
            defenderFeeBalance: 0,
            arbitrationStakeBalance: 0,
            selectedArbitrator: address(0),
            arbitrationDecisionTime: 0,
            arbitrationWinner: address(0),
            disputeActive: true,
            arbitrationDecisionChallenged: false
      });
    }

    // Function to create a new arbitration case
    function createCase(
        CurrencyType _currencyType,
        address _party,
        address _counterparty,
        uint256 _depositAmount,
        uint256 _settlementDeadline
        ) 
        internal returns (uint256 caseId, Case storage newCase) {
            Case memory newCaseHolder = defaultCase();
            caseId = nextCaseId++;

            newCaseHolder.contractCurrency = _currencyType;
            newCaseHolder.party = _party;
            newCaseHolder.counterparty = _counterparty;
            newCaseHolder.depositAmount = _depositAmount;
            newCaseHolder.maintenanceFee = _depositAmount * (maintenanceFeePercentage / 1000);
            newCaseHolder.settlementDeadline = _settlementDeadline;

            cases[caseId] = newCaseHolder;

            // Now add the contract ID and URL to their respective mappings
            AddDefaultContracts(caseId);
            emit CaseCreated(caseId, _party, _counterparty);
            return (caseId, cases[caseId]);
        }

    function AddDefaultContracts(uint256 _caseId) internal
    {
        //May want to remove dupilicate ID and URL if gas fees are too much to create utility (ease of access).
        ERC721TokenIds[_caseId].push(defaultContractId);
        ERC721TokenURLs[_caseId].push(defaultContractURL);

    }

    function defaultCase() internal pure returns (Case memory) {
      return Case({
        caseActive: true,
        contractGasAvailable: 0,
        currentCaseValue: 0,
        contractCurrency: CurrencyType.MATIC,
        party: address(0),
        counterparty: address(0),
        depositAmount: 0,
        maintenanceFee: 0,
        settlementDeadline: 0,

        disputeStatus: defaultDisputeStatus(),

        newCaseID: 0,
        appealChallengedNewDeLawContract: false
      });
    }

    /**
     * @dev Allows the maintenance address to be changed. Can only be called by the current maintenance address.
     * @param _newAddress The new address for maintenance fees.
     */
    function changeMaintenanceAddress(address payable _newAddress) external 
    {
        require(_newAddress != address(0), "Invalid address");
        require(msg.sender == maintenanceAddress, "Unauthorized");

        // Log the address change event
        emit MaintenanceAddressChanged(maintenanceAddress, _newAddress);

        // Update the maintenance address
        maintenanceAddress = _newAddress;
    }

    /** 
    * @dev Allows for tracking of maintenance balances and future extraction of maintenance funds in gas-efficient way
    */

  function ChangeMaintenenceBalance(CurrencyType currencyType, uint256 value, bool increase) internal returns (uint256 availableBalanceReturn) 
  {
    if (increase) 
    {
        totalCurrentAvailableMaintenanceFees[currencyType] += value;
    } else {
        // Check if there's enough balance to subtract
        if (totalCurrentAvailableMaintenanceFees[currencyType] >= value) {
            totalCurrentAvailableMaintenanceFees[currencyType] -= value;
        } else {
            // Handle the error case, perhaps revert the transaction
            revert("Insufficient balance to decrease");
        }
      }
      return totalCurrentAvailableMaintenanceFees[currencyType];
  }

    /** 
    * @dev Allows for tracking of maintenance balances and transfer of maintenance funds as one time attempt in gas-efficient way
    */
    function transferMaintenenceBalance(CurrencyType currencyType, uint256 value, address sendTo) external nonReentrant
    {
        require(msg.sender == maintenanceAddress, "Only the maintenance address can update the fee");
        uint256 availableBalance = 0;
        

        if (currencyType == CurrencyType.MATIC)
        {
            availableBalance = totalCurrentAvailableMaintenanceFees[CurrencyType.MATIC];
            if(availableBalance >= value)
            {
                payable(sendTo).transfer(value);
            }          
        }
        else
        {
            availableBalance = totalCurrentAvailableMaintenanceFees[currencyType];
            if(availableBalance >= value)
            {
                transferERC20Token(0, currencyType, address(this), sendTo, value);
            }
        }

        ChangeMaintenenceBalance(currencyType, value, false);
    }

    /**
     * @notice Updates the maintenance fee percentage. Only callable by the maintenance address.
     * @notice Maintenence fees will be used to improve the network and pay OpenSource developers for improving the protocol. 
     * @param _newFeePercentage The new fee percentage as a whole number (e.g., 0.5 for 0.5%).
     */
    function setMaintenanceFeePercentage(uint256 _newFeePercentage) public
    {
        require(msg.sender == maintenanceAddress, "Only the maintenance address can update the fee");
        require(_newFeePercentage >= 0, "Invalid fee percentage"); // Add any other necessary validations
        emit MaintenanceFeePercentageChanged(maintenanceFeePercentage, _newFeePercentage);
        maintenanceFeePercentage = _newFeePercentage;
    }

    //Below are dispute fee setters, as protocol matures, arbitration should become more reliable, trustworthy, faster and therefore cheaper. 
    //As more arbitrators are onboarded and arbitration cases are fulfilled, dispute fees which are payable in part to the arbitrator should drop to compensate.
    //Future contract should include a dynamic mechanism that tracks contract types with arbitration wait times to dynamically reset arbitration fees appropriately.
    /**
     * @notice Updates the dispute fee percentage. Only callable by the maintenance address.
     * @param _newFeePercentage The new dispute fee percentage as a whole number (e.g., 10 for 10% which is default rate).
     */
    function setDisputeFeePercentage(uint256 _newFeePercentage) public
    {
        require(msg.sender == maintenanceAddress, "Only the maintenance address can update the fee");
        require(_newFeePercentage >= 0, "Invalid fee percentage"); // Add any other necessary validations
        emit DisputeFeePercentageChanged(disputeFeePercentage, _newFeePercentage);
        disputeFeePercentage = _newFeePercentage;
    }

    /**
     * @notice Updates the dispute fee percentage. Only callable by the maintenance address.
     * @param _newFeePercentage The new dispute fee percentage as a whole number (e.g., 30 for 30% which is default rate).
     * @notice This fee is set to appeal initial arbitrator's decision and go to Final Judgement
     */
    function setAppealArbitrationFeeRate(uint256 _newFeePercentage) public
    {
        require(msg.sender == maintenanceAddress, "Only the maintenance address can update the fee");
        require(_newFeePercentage >= 0, "Invalid fee percentage"); // Add any other necessary validations
        emit AppealArbitratorDecisionFeePercentageChanged(disputeDecisionFeePercentage, _newFeePercentage);
        disputeDecisionFeePercentage = _newFeePercentage;
    }

    /**
     * @notice Updates the Final Judgement dispute fee percentage. Only callable by the maintenance address.
     * @param _newFeePercentage The new dispute fee percentage as a whole number (e.g., 100 for 100% which is default rate).
     * @notice This fee is set to appeal Final Judgement and create a new contract to challenge arbitrators decision making or fairness of execution
     */
    function setFinalJudgementAppealFeeRate(uint256 _newFeePercentage) public
    {
        require(msg.sender == maintenanceAddress, "Only the maintenance address can update the fee");
        require(_newFeePercentage >= 0, "Invalid fee percentage"); // Add any other necessary validations
        emit AppealFinalJudgementFeePercentageChanged(disputeFinalJudgementFeePercentage, _newFeePercentage);
        disputeFinalJudgementFeePercentage = _newFeePercentage;
    }

    function setContractDefaultTemplateIdAndURL(uint256 _newDefaultERC721Id, string memory _newDefaultERC721URL) public
    {
        require(msg.sender == maintenanceAddress, "Only the maintenance address can update default contract template");
        defaultContractId = _newDefaultERC721Id;
        defaultContractURL = _newDefaultERC721URL;
        emit defaultContractsChanged(_newDefaultERC721Id, _newDefaultERC721URL);
    }

    function setTradLawSelectedDefaultTemplateIdAndURL(uint256 _newDefaultERC721Id, string memory _newDefaultERC721URL) public
    {
        require(msg.sender == maintenanceAddress, "Only the maintenance address can update default contract template");
        defaultContractTradLawId = _newDefaultERC721Id;
        defaultContractTradLawURL = _newDefaultERC721URL;
        emit defaultContractsChanged(_newDefaultERC721Id, _newDefaultERC721URL);
    }
    
    // Function to receive tokens based on the enum type, utility function for contract execution
    function receiveTokens(CurrencyType _type, uint256 _amount) external {
        address tokenAddress = CurrencyTypeAddresses[_type];
        require(tokenAddress != address(0), "Token address not set");
        
        IERC20 token = IERC20(tokenAddress);
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");
    }

    // Function to send tokens based on the enum type, utility function for maintenance address. 
    // Can be used to transfer maintenance balances or admin over-ride "stuck" contracts particularly during depreciation and updating of contracts.
    function sendTokens(CurrencyType _type, address _to, uint256 _amount) external {
        require(msg.sender == maintenanceAddress, "Only Maintenance Address can directly transfer tokens");
        address tokenAddress = CurrencyTypeAddresses[_type];
        require(tokenAddress != address(0), "Token address not set");
        
        IERC20 token = IERC20(tokenAddress);
        bool success = token.transfer(_to, _amount);
        require(success, "Token transfer failed");
    }

    // Function to check the contract's balance for a specific currency type
    function checkTokenBalance(CurrencyType _type) external view returns (uint256) {
        address tokenAddress = CurrencyTypeAddresses[_type];
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    // Function to check a specific case balance for a specific currency type
    function checkCaseTokenBalance(CurrencyType _type, uint256 _caseID) external view returns (uint256) {
        Case memory selectedCase = cases[_caseID];

        if(_type == CurrencyType.MATIC)
        {
            return selectedCase.contractGasAvailable;
        }

        if(selectedCase.contractCurrency == _type)
        {
            return selectedCase.currentCaseValue;
        }
        address tokenAddress = CurrencyTypeAddresses[_type];
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    // Function to ban an address
    function banAddress(address _address) public {
        require(msg.sender == maintenanceAddress, "only maintenance address can ban or unban addresses");
        // Only allow non-banned addresses to be banned
        require(!isBanned[_address], "Address is already banned");

        // Set the address status to banned
        isBanned[_address] = true;
        emit AddressBanned(_address);  // Log the ban action
    }

    //function to unban an address
    function unbanAddress(address _address) public {
        require(msg.sender == maintenanceAddress, "only maintenance address can ban or unban addresses");
        require(isBanned[_address], "Address is not currently banned");

        // Set the address status to not banned
        isBanned[_address] = false;
        emit AddressUnbanned(_address);  // Log the unban action
    }

        // Function to check if an address is banned
    function checkIfBanned(address _address) public view returns (bool) {
        return isBanned[_address];
    }

    function pauseUnpauseCaseByIDSuspActivity(uint256 caseId, bool activeCase) external {
        require(msg.sender == maintenanceAddress, "only maintenance address can freeze contracts");
        cases[caseId].caseActive = activeCase;
    }

    // Function to check the contract's balance
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
        //TODO: This currently just checks native tokens for gas availablilty, should have a function to return specific case balance for different ERC-20 token types and gas logging for each case.
    } 

    //Pay Party based on currencyType
    function casePayoutByCurrencyType(CurrencyType _currencyType, address payTo, uint256 valuePaid) internal nonReentrant
    {
        if (_currencyType == CurrencyType.MATIC) {
            // Transfer native blockchain currency to the payable address
            (bool sentMATIC, ) = payable(payTo).call{value: valuePaid}(""); 
            require(sentMATIC, "failed to send MATIC");
        } else {
            // Transfer ERC-20 tokens to the payable address
            // For ERC-20 token disputes
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(0, _currencyType, address(this), payTo, valuePaid);
        }
    }

    //Used in construction of cases, adding base template of contract setting and outlining terms of DeLaw procedure.
    function addDefaultCaseAttachment(uint256 caseId) internal {
        require(cases[caseId].caseActive, "Case does not exist");

        // Add the ERC721 token ID and URL to their respective mappings for the given caseId
        ERC721TokenIds[caseId].push(defaultContractId);
        ERC721TokenURLs[caseId].push(defaultContractURL);
    }

    //This is used to attach ERC721 token Id's and URL's to the case allowing for written contracts to be referenced as well as arguments to be presented and the arbitrators decision to be recorded.
    function addCaseAttachment(uint256 caseId, uint256 ERC721Id, string memory ERC721URL) external {
        // Check that the case exists by verifying the active flag or existence in the cases mapping
        require(cases[caseId].caseActive, "Case does not exist");
        address selectedArbitrator1 = address(0);
        address selectedArbitrator2 = address(0);
        
        Case storage currentCase = cases[caseId];
        if(currentCase.disputeStatus.initialDisputeID != 0)
        {
          selectedArbitrator1 = disputes[cases[caseId].disputeStatus.initialDisputeID].selectedArbitrator;
        }
        if(currentCase.disputeStatus.appealDisputeID != 0)
        {
          selectedArbitrator2 = disputes[cases[caseId].disputeStatus.appealDisputeID].selectedArbitrator;
        }
        // Ensure the involved parties only add information to case
        require(
            msg.sender == maintenanceAddress || 
            msg.sender == cases[caseId].party || 
            msg.sender == cases[caseId].counterparty || 
            msg.sender == selectedArbitrator1 || 
            msg.sender == selectedArbitrator2,
            "Only involved parties can add documentation Tokens"
        );

        // Add the ERC721 token ID and URL to their respective mappings for the given caseId
        ERC721TokenIds[caseId].push(ERC721Id);
        ERC721TokenURLs[caseId].push(ERC721URL);
    }

    /** 
     * @notice Handle ERC-20 token deposit and payouts
     * @param caseId The Id of the arbitration case that is appropraite
     * @param _currencyType The currency type of the deposit, corresponding to the CurrencyType enum.
     * @param _from wallet address where tokens currently held.
     * @param _to wallet address where tokens will be sent.
     */
    function transferERC20Token(uint256 caseId, CurrencyType _currencyType, address _from, address _to, uint256 _amount) internal {
        Case memory caseTransfer = cases[caseId];

        if(caseId == 0)
        {
            require(msg.sender == maintenanceAddress, "only maintenanceAddress can transfer non-active accounts for contract as whole");
        }
        if(caseId != 0)
        {
            require(caseTransfer.caseActive, "case is not active");
        }

        //Check caseId for valid case transfer.
        address tokenAddress = CurrencyTypeAddresses[_currencyType];
        IERC20 token = IERC20(tokenAddress);
        require(tokenAddress != address(0), "Token address not set");
        // The sender must have approved the contract to spend tokens beforehand
        uint256 allowedAmount = token.allowance(msg.sender, address(this));
        require(allowedAmount >= _amount, "Insufficient tokens deposited");
        require(token.transferFrom(_from, _to, _amount), "Token transfer failed");
    }

    /**
     * @notice Allows users to deposit tokens of the specified currency type into the contract.
     * @dev Ensures the deposited amount and currency type match the case requirements.
     * @param caseId The ID of the arbitration case to make a deposit for.
     * @param currencyType The currency type of the deposit, corresponding to the CurrencyType enum.
     */
    function makeDeposit(uint256 caseId, CurrencyType currencyType) external payable 
    {
        //Maintenence fees are set aside in contract to be bulk transfered later for gas efficiency.
        Case storage arbitrationCase = cases[caseId];
        // Check if the currency type of the deposit matches the case's specified currency type
        require(arbitrationCase.contractCurrency == currencyType, "Incorrect currency type");
        require(msg.sender == arbitrationCase.party || msg.sender == arbitrationCase.counterparty, "Sender is not a party to the contract");
        if (currencyType == CurrencyType.MATIC) {
            // Handle native token (MATIC) deposit
            require(msg.value == (arbitrationCase.depositAmount * (1+ maintenanceFeePercentage)), "Incorrect deposit amount for MATIC");
            emit DepositMade(caseId, msg.sender, CurrencyType.MATIC, msg.value);
            ChangeMaintenenceBalance(currencyType, arbitrationCase.maintenanceFee, true);
        }
        else{
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of deposit
            transferERC20Token(caseId, currencyType, msg.sender, address(this), (arbitrationCase.depositAmount * (1+ maintenanceFeePercentage)));
            //emit event logging deposit
            emit DepositMade(caseId, msg.sender, currencyType, msg.value);
            //update maintenanceFee
            ChangeMaintenenceBalance(currencyType, arbitrationCase.maintenanceFee, true);
        }
        
    }

    /**
     * @notice Awards the deposited amount to the counterparty if no dispute has been raised before the dispute deadline.
     * This function is meant to be called after the dispute deadline has passed without any disputes being raised.
     * It ensures the funds are transferred to the intended recipient based on the case's outcome.
     * 
     * @dev The function checks several conditions to ensure the operation is valid:
     * - The current time must be past the dispute deadline of the case.
     * - No dispute must have been raised for the case.
     * - The case must not have been previously resolved or completed.
     * 
     * Based on the contract currency, it handles both native currency (MATIC) and ERC-20 token transfers.
     * The function deducts a maintenance fee before transferring the remaining amount to the counterparty.
     * It marks the arbitration case as completed to prevent further actions on it.
     * 
     * @param caseId The ID of the arbitration case to award.
     */
    function awardToDefaultAddress(uint256 caseId) external payable nonReentrant
    {
        Case storage arbitrationCase = cases[caseId];
        // Ensure the current time is past the dispute deadline.
        require(block.timestamp > arbitrationCase.settlementDeadline, "Dispute deadline has not passed");
        require(arbitrationCase.caseActive, "Case not active");
        // Ensure no dispute has been raised for the case.
        require(arbitrationCase.disputeStatus.initialDisputeID == 0, "A dispute has been raised");

        // For simplicity, assuming the entire balance or a predefined amount should go to the counterparty
        // Handling based on the currency type of the contract
        if (arbitrationCase.contractCurrency == CurrencyType.MATIC) {
            // For MATIC, transfer the deposit amount minus the maintenance fee to the counterparty.
            payable(arbitrationCase.counterparty).transfer(arbitrationCase.depositAmount);
            // Transfer the maintenance fee to the maintenance address.
            
        } else {
            // For ERC-20 tokens, use the token contract to transfer
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(caseId, arbitrationCase.contractCurrency, address(this), arbitrationCase.counterparty, arbitrationCase.depositAmount);
            //emit event logging deposit
            emit DepositMade(caseId, msg.sender, arbitrationCase.contractCurrency, msg.value);
        }

        arbitrationCase.caseActive = false; // Mark the case as completed to prevent further actions
        // Emit an event to log
        emit awardToDefault(caseId, arbitrationCase.counterparty, arbitrationCase.depositAmount);
    }

    /**
    * @notice Enables a party to claim contract completion for contracts with non-specific completion time.
    * @param caseId The ID of the case being disputed
    * @param ERC721TokenIDForProof is the id of the ERC721 token that references proof of contract completion that will be arbitrated.
    */
    function claimContractCompletion(uint256 caseId, uint256 challengeStake, uint256 ERC721TokenIDForProof, string memory ERC721TokenURLForProof) public
    {
        Case storage arbitrationCase = cases[caseId];
        
        require(msg.sender == arbitrationCase.party || msg.sender == arbitrationCase.counterparty, "Sender is not a party to the contract");
        require(challengeStake >= arbitrationCase.depositAmount * disputeFeePercentage);
        require(arbitrationCase.disputeStatus.currentDisputeLevel == DisputeLevel.NoDispute);

        address defender;
        if(msg.sender == arbitrationCase.party)
        {
            defender = arbitrationCase.counterparty;
        }

        if(msg.sender == arbitrationCase.counterparty)
        {
            defender = arbitrationCase.party;
        }

        createDispute(caseId, DisputeLevel.InitialDispute, msg.sender, defender, challengeStake);    

        ERC721TokenIds[caseId].push(ERC721TokenIDForProof);
        ERC721TokenURLs[caseId].push(ERC721TokenURLForProof);

        emit contractClaimedCompleted(caseId, ERC721TokenURLForProof);
        
        //Contract now awaits for either counterclaim or completion. 
    }

    function noCounterClaim72Hrs(uint256 caseId, uint256 disputeId) public payable nonReentrant
    {
        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];
        require(!arbitrationCase.caseActive, "case is not active");
        require(disputeCase.disputeActive, "dispute is no longer active");
        require(disputeCase.parentCaseID == caseId, "DisputeId does not match Case");
        require(block.timestamp >= disputeCase.disputeRaisedTime + 3 days, "72 hours have not passed");
        require(disputeCase.defenderFeeBalance == 0, "Defense has been raised");
        
        //Valid executution, set dispute and case no longer active, pay out party.
        arbitrationCase.caseActive = false;
        disputeCase.disputeActive = false;


        // Handling based on the currency type of the contract
        if (arbitrationCase.contractCurrency == CurrencyType.MATIC) {
            // For MATIC, transfer the deposit amount minus the maintenance fee to the counterparty.
            payable(disputeCase.disputeRaisedAddress).transfer(arbitrationCase.depositAmount + (disputeCase.disputerChallengeFeeBalance));
        } else {
            // For ERC-20 tokens, use the token contract to transfer
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(caseId, arbitrationCase.contractCurrency, address(this), disputeCase.disputeRaisedAddress, arbitrationCase.depositAmount + (disputeCase.disputerChallengeFeeBalance));
        }

        // Emit an event indicating the dispute has been finalized due to unmatched counter-dispute
        emit DisputeFinalized(caseId, disputeCase.disputeRaisedAddress);
    }

    /**
     * @notice Raises a dispute for a specific case, indicating disagreement with the outcome.
     * Requires depositing a dispute fee, calculated as a percentage of the case deposit amount.
     * @dev Checks if the dispute fee is met and handles the transfer of ERC-20 tokens if necessary.
     * @param caseId The ID of the case being disputed.
     */
    function raiseDispute(uint256 caseId, DisputeLevel newDisputeLevelRequested) external payable {
        Case storage arbitrationCase = cases[caseId];
        require(arbitrationCase.disputeStatus.currentDisputeLevel != newDisputeLevelRequested, "Dispute at this level already raised");
        //require(arbitrationCase.currentDisputeLevel.value - newDisputeLevelRequested.value <= 1, "requesting wrong level of dispute");
        require(block.timestamp < arbitrationCase.settlementDeadline || arbitrationCase.settlementDeadline == 0, "Dispute deadline has passed");
        require(msg.sender == arbitrationCase.party || msg.sender == arbitrationCase.counterparty, "Sender is not a party to the contract");

        // Check for correct currency and amount
        if (arbitrationCase.contractCurrency == CurrencyType.MATIC) {
            // For native currency disputes
            require(msg.value >= arbitrationCase.depositAmount * disputeFeePercentage, "Dispute fee not met");
        } else {
            // For ERC-20 token disputes
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(caseId, arbitrationCase.contractCurrency, msg.sender, address(this), (arbitrationCase.depositAmount * disputeFeePercentage));
        }

        address defender;
        if(msg.sender == arbitrationCase.party)
        {
            defender = arbitrationCase.counterparty;
        }

        if(msg.sender == arbitrationCase.counterparty)
        {
            defender = arbitrationCase.party;
        }

        createDispute(caseId, newDisputeLevelRequested, msg.sender, defender, (arbitrationCase.depositAmount * disputeFeePercentage)); 

        //Store DisputeId's for sake of completion and accessibility
        if(newDisputeLevelRequested == DisputeLevel.InitialDispute)
        {
            arbitrationCase.disputeStatus.initialDisputeID = nextDisputeId;
        }

        if(newDisputeLevelRequested == DisputeLevel.AppealArbitration)
        {
            arbitrationCase.disputeStatus.appealDisputeID = nextDisputeId;
        }

        if(newDisputeLevelRequested == DisputeLevel.AppealFinalJudgement)
        {
            arbitrationCase.disputeStatus.finalJudgementDisputeID = nextDisputeId;
        }

        emit DisputeRaised(caseId, msg.sender);
    }

    /**
     * @notice Allows the opposing party to match the funds raised in the initial dispute.
     * This function ensures that both parties are equally invested in the arbitration process.
     * @dev Requires the counterparty to deposit an amount equal to the dispute fee already paid.
     * @param caseId The ID of the case being counter-disputed.
     */
    function counterDispute(uint256 caseId, uint256 disputeId) external payable {
        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];
        // Ensure that a dispute has been raised for this case
        require(!disputeCase.disputeActive, "No dispute has been raised for this case.");

        // Ensure that the function caller is not the one who raised the dispute
        require(msg.sender != disputeCase.disputeRaisedAddress, "Dispute raiser cannot counter-dispute.");

        // Check that the counterparty is matching the dispute fee
        uint256 requiredDisputeFee = disputeCase.disputerChallengeFeeBalance; // Fee already calculated in raiseDispute
        if (arbitrationCase.contractCurrency == CurrencyType.MATIC) {
            // For native currency (MATIC) disputes
            require(msg.value == requiredDisputeFee, "Dispute fee does not match.");
        } else {
            // For ERC-20 token disputes
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(caseId, arbitrationCase.contractCurrency, msg.sender, address(this), requiredDisputeFee);
        }

        disputeCase.defenderFeeBalance = requiredDisputeFee;

        // Emit an event indicating that the counterparty has matched the dispute fee
        emit CounterDisputeMatched(caseId, msg.sender);
    }

    /**
     * @notice Finalizes the dispute resolution process if no counter-dispute has been matched within 72 hours.
     * @dev Checks if the 72-hour period has passed since the dispute was raised without a matching counter-dispute.
     * @param caseId The ID of the case to check for unmatched counter-dispute.
     */
    function finalizeUnmatchedDispute(uint256 caseId, uint256 disputeId) external payable nonReentrant {
        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];

        require(!arbitrationCase.caseActive, "case is not active");
        require(disputeCase.disputeActive, "dispute is no longer active");
        require(disputeCase.parentCaseID == caseId, "DisputeId does not match Case");
        require(block.timestamp >= disputeCase.disputeRaisedTime + 3 days, "72 hours have not passed");
        require(disputeCase.defenderFeeBalance == 0, "Defense has been raised");
        
        //Valid executution, set dispute and case no longer active, pay out party.
        arbitrationCase.caseActive = false;
        disputeCase.disputeActive = false;


        // Handling based on the currency type of the contract
        if (arbitrationCase.contractCurrency == CurrencyType.MATIC) {
            // For MATIC, transfer the deposit amount minus the maintenance fee to the counterparty.
            payable(disputeCase.disputeRaisedAddress).transfer(arbitrationCase.depositAmount + (disputeCase.disputerChallengeFeeBalance));
        } else {
            // For ERC-20 tokens, use the token contract to transfer
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(caseId, arbitrationCase.contractCurrency, address(this), disputeCase.disputeRaisedAddress, arbitrationCase.depositAmount + (disputeCase.disputerChallengeFeeBalance));
        }

        // Emit an event indicating the dispute has been finalized due to unmatched counter-dispute
        emit DisputeFinalized(caseId, disputeCase.disputeRaisedAddress);
    }

     /**
     * @notice Selects an arbitrator for a case and locks their stake.
     * This function allows an arbitrator to volunteer for a case by staking the required amount.
     * It ensures that only eligible arbitrators can select themselves for a case and that each case can have only one arbitrator.
     * 
     * @dev Before selecting an arbitrator, the function checks:
     * - If the case already has an arbitrator assigned.
     * - If the caller has deposited the required arbitration stake for the case's currency type.
     * The function handles both native currency (MATIC) and ERC-20 token stakes.
     * 
     * @param caseId The ID of the case for which an arbitrator is being selected.
     */
    function selectArbitratorForCase(uint256 caseId, uint256 disputeId) external payable nonReentrant{
        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];
        // Ensure the case does not already have an arbitrator.
        require(disputeCase.selectedArbitrator == address(0), "Case already has an arbitrator");
        require(disputeCase.arbitrationStakeBalance == 0, "Dispute already has arbitrator staked");
        //TODO: Require arbitrator have identity enabled - future requirement requires additional EVM infrastructure to enable
        // The logic to handle stake deposit based on the contract currency type.
        //Set staking requirement for arbitrator.
        uint256 stakingRequirement = 0;
        if (disputeCase.currentDisputeLevel == DisputeLevel.InitialDispute)
        {
            stakingRequirement = (2 * disputeFeePercentage); //meaning for default, 10% min stake for arbitrator to cover both parties stake.
        }
        if (disputeCase.currentDisputeLevel == DisputeLevel.AppealArbitration)
        {
            stakingRequirement = (100); //meaning for default, 100% contract value stake for arbitrator, this is because winner is directly paid out and if appealed it becomes arbitrator vs loser.
        }

        if (arbitrationCase.contractCurrency == CurrencyType.MATIC) {
             // For MATIC, ensure the sent value matches the required arbitration stake.
            require(msg.value >= arbitrationCase.depositAmount * (stakingRequirement/100), "Incorrect deposit amount for MATIC");
            disputeCase.arbitrationStakeBalance = msg.value; 
        } else {
            // For ERC-20 token stakes, ensure no MATIC is sent with the transaction.
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(caseId, arbitrationCase.contractCurrency, msg.sender, address(this), arbitrationCase.depositAmount * (stakingRequirement/100));
            
            disputeCase.arbitrationStakeBalance = arbitrationCase.depositAmount * (stakingRequirement/100);
        }

         // Assign the caller as the selected arbitrator for the case.
        disputeCase.selectedArbitrator = msg.sender;
        emit arbitratorSelected(caseId, disputeId, msg.sender);
    }

    //In the instance that an arbitrator takes a case, and with no reason has undue delay not justifiable to the case, maintenance address can boot off the arbitrator, slash the stake and open up case for new arbitrator.
    function bootArbitratorFromCase(uint256 caseId, uint256 disputeId) external nonReentrant{
        require(msg.sender == maintenanceAddress, "only maintenanceAddress can boot arbitrator for taking too long to make decision");
        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];
        ChangeMaintenenceBalance(arbitrationCase.contractCurrency, disputeCase.arbitrationStakeBalance, true);
        disputeCase.arbitrationStakeBalance = 0;
        address oldArbitrator = disputeCase.selectedArbitrator;
        disputeCase.selectedArbitrator = address(0);
        disputeCase.disputeActive = true;

        emit bootArbitrator(caseId, disputeId, oldArbitrator);
    }

    /**
     * @notice Resolves a dispute for a specific case, determining the winner based on the arbitrator's decision.
     * @param caseId The ID of the case to resolve.
     * @param decisionWinner The decision of the arbitrator, true if in favor of the dispute raiser.
     */
    function resolveDispute(uint256 caseId, uint256 disputeId, address decisionWinner) external nonReentrant
    {
        //Ensure only the arbitrator can decide the outcome
        //Preliminary checks for arbitrator and case status

        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];

        require(!arbitrationCase.caseActive, "case is not active");
        require(disputeCase.disputeActive, "dispute is no longer active");
        require(disputeCase.parentCaseID == caseId, "DisputeId does not match Case");
        require(disputeCase.selectedArbitrator == msg.sender, "Caller is not the selected arbitrator");
    
        disputeCase.disputeActive = false; 
        disputeCase.arbitrationDecisionTime = block.timestamp;

        //Set the dispute and wait for parties to accept of reject arbitration decision. If rejected, new dispute created for appeal.
        if(disputeCase.currentDisputeLevel == DisputeLevel.InitialDispute)
        {
            disputeCase.arbitrationWinner = decisionWinner;
            disputeCase.arbitrationDecisionTime = block.timestamp;
        }

        //This is final Judgement, further appeals must create the new contract mechanism
        if(disputeCase.currentDisputeLevel == DisputeLevel.AppealArbitration)
        {
            disputeCase.arbitrationWinner = decisionWinner;
            disputeCase.arbitrationDecisionTime = block.timestamp;

            //Payout winner their stake and balance.
            casePayoutByCurrencyType(arbitrationCase.contractCurrency, decisionWinner, (arbitrationCase.depositAmount + disputeCase.disputerChallengeFeeBalance)); 
            
            //Check if previous arbitrator made same decision, if so pay out their stake and reward.
            if(disputeCase.arbitrationWinner == disputes[arbitrationCase.disputeStatus.initialDisputeID].arbitrationWinner)
            {
                address oldArbitrator = disputes[arbitrationCase.disputeStatus.initialDisputeID].selectedArbitrator;
                casePayoutByCurrencyType(arbitrationCase.contractCurrency, oldArbitrator, (disputes[arbitrationCase.disputeStatus.initialDisputeID].disputerChallengeFeeBalance + disputes[arbitrationCase.disputeStatus.initialDisputeID].arbitrationStakeBalance)); 
            }
        }
        
        emit DisputeResolved(caseId, disputeCase.arbitrationWinner);
    }

    /**
     * @notice Finalizes arbitration if no challenges are raised within a specified period.
     * This function is called after the arbitration decision has been made and no parties have raised a challenge within the challenge period.
     * It ensures the arbitration decision is respected and the awarded funds are transferred accordingly.
     * 
     * @dev The function performs several checks to ensure the operation is valid:
     * - Confirms that the arbitration has been completed.
     * - Ensures no challenge has been raised against the arbitration decision.
     * - Checks that the challenge period has expired.
     * 
     * The function then transfers the arbitration stake and any arbitration fees to the winning party.
     * It handles both native currency (MATIC) and ERC-20 tokens based on the contract currency.
     * 
     * @param caseId The ID of the case for which the arbitration challenge period has passed.
     */
    function noArbitrationChallenge(uint256 caseId, uint256 disputeId) external nonReentrant
    {
        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];
        require(msg.sender == arbitrationCase.party || msg.sender == arbitrationCase.counterparty || msg.sender == disputeCase.selectedArbitrator || msg.sender == maintenanceAddress, "only involved parties can trigger no arbitration challenge");
        require(arbitrationCase.caseActive, "Already finalized contract");
        require(disputeCase.disputeActive, "already finalized dispute");
        // Ensure arbitration has been completed.
        require(disputeCase.arbitrationWinner != address(0), "Arbitration has not been completed");
        // Ensure no challenge has been raised.
        require(!disputeCase.arbitrationDecisionChallenged, "A challenge has been raised");
        // Ensure the challenge period has expired
        require(block.timestamp > disputeCase.arbitrationDecisionTime + 72 hours, "Challenge period has not yet expired");

        // Mark the case and dispute as fully finalized to prevent further actions
        arbitrationCase.caseActive = false;
        disputeCase.disputeActive = false;

        if(disputeCase.currentDisputeLevel == DisputeLevel.InitialDispute)
        {
            //pay out arbitration winner their balance and stake value.
            casePayoutByCurrencyType(arbitrationCase.contractCurrency, disputeCase.arbitrationWinner, (arbitrationCase.depositAmount + disputeCase.disputerChallengeFeeBalance));
            //pay out arbitrator their stake plus one forfeited challenge fee. (i.e. 5% profit on 10% stake)
            casePayoutByCurrencyType(arbitrationCase.contractCurrency, disputeCase.selectedArbitrator, (disputeCase.arbitrationStakeBalance + disputeCase.disputerChallengeFeeBalance));
        }

        if(disputeCase.currentDisputeLevel == DisputeLevel.AppealArbitration)
        {
            Dispute storage previousDispute = disputes[arbitrationCase.disputeStatus.initialDisputeID];

            //check if previous arbitrator was correct in assessment
            if(previousDispute.arbitrationWinner == disputeCase.arbitrationWinner)
            {
                casePayoutByCurrencyType(arbitrationCase.contractCurrency, previousDispute.selectedArbitrator, (previousDispute.arbitrationStakeBalance + previousDispute.disputerChallengeFeeBalance));
                casePayoutByCurrencyType(arbitrationCase.contractCurrency, disputeCase.selectedArbitrator, (disputeCase.arbitrationStakeBalance + disputeCase.disputerChallengeFeeBalance));
            }

            if(previousDispute.arbitrationWinner != disputeCase.arbitrationWinner)
            {
                casePayoutByCurrencyType(arbitrationCase.contractCurrency, disputeCase.selectedArbitrator, (disputeCase.arbitrationStakeBalance + disputeCase.disputerChallengeFeeBalance + previousDispute.arbitrationStakeBalance + previousDispute.disputerChallengeFeeBalance));
            }
        }

        if(disputeCase.currentDisputeLevel == DisputeLevel.AppealFinalJudgement)
        {
            revert("code should be unreachable");
        }

        // Emit an event to log the finalization
        emit ArbitrationFinalized(caseId, disputeCase.arbitrationWinner);
    }

    //Function to challenge arbitrators decision and escalate to next level of arbitration or court.
    function DisputeArbitratorDecision(uint256 caseId, uint256 disputeId, bool finalJudgementDelawContinue) external payable {
        Case storage arbitrationCase = cases[caseId];
        Dispute storage disputeCase = disputes[disputeId];

         // Validation checks for prerequisites of challenging the arbitration decision.
        require(!disputeCase.arbitrationDecisionChallenged, "Arbitration decision already challenged");
        require(block.timestamp <= disputeCase.arbitrationDecisionTime + 72 hours, "Challenge period has expired");
        require(msg.sender == arbitrationCase.party || msg.sender == arbitrationCase.counterparty, "Sender is not a party to the contract");
        require(msg.sender != disputeCase.arbitrationWinner, "Winner cannot challenge the decision");
        require(disputeCase.arbitrationWinner != address(0), "Primary arbitration not completed");
        
        uint256 disputeFeeRequired = 0;
        DisputeLevel newDisputeLevel = DisputeLevel.InitialDispute; // placeholder

        //This is if only first round arbitration was challenged.
        if(disputeCase.currentDisputeLevel == DisputeLevel.InitialDispute)
        {
            disputeFeeRequired = arbitrationCase.depositAmount * disputeDecisionFeePercentage; //Default set to 30% of the value of the deposit to dispute initial arbitrator
            newDisputeLevel = DisputeLevel.AppealArbitration;
        }

        //This is to challenge appeal arbitration, and trigger new contract creation
        if(disputeCase.currentDisputeLevel == DisputeLevel.AppealArbitration)
        {
            disputeFeeRequired = arbitrationCase.depositAmount * disputeFinalJudgementFeePercentage; //Default set to 100% of the value of the deposit to dispute initial arbitrator
            newDisputeLevel = DisputeLevel.AppealFinalJudgement;
        }

        if (arbitrationCase.contractCurrency == CurrencyType.MATIC) {
            // Get stake
            require(msg.value >= disputeFeeRequired, "Incorrect arbitration stake for appeal");
        } else {
            // Transfer ERC-20 tokens to the winner
            // For ERC-20 token disputes
            require(msg.value == 0, "ERC-20 deposits should not send MATIC");
            //Confirm transfer of award
            transferERC20Token(caseId, arbitrationCase.contractCurrency, msg.sender, address(this), disputeFeeRequired);
        }
        
        address defender = address(0);
        if(msg.sender == arbitrationCase.party)
        {
            defender = arbitrationCase.counterparty;
        }
        if(msg.sender == arbitrationCase.counterparty)
        {
            defender = arbitrationCase.party;
        }

        //Create a new Dispute and close the old one.
        disputeCase.disputeActive = false;
        disputeCase.arbitrationDecisionChallenged = true;
        if(newDisputeLevel != DisputeLevel.AppealFinalJudgement)
        {
            createDispute(caseId, newDisputeLevel, msg.sender, defender, disputeFeeRequired);
        }
        if(newDisputeLevel == DisputeLevel.AppealFinalJudgement)
        {
            createCase(arbitrationCase.contractCurrency, msg.sender, disputeCase.selectedArbitrator, ((((arbitrationCase.depositAmount * 2 ) + (disputeCase.disputerChallengeFeeBalance))*19)/20), 0);
            //If true, this means that this case will continue through regular delaw arbitration. If false, then final Judgement must occur in TradLaw system described by contract.
            Case storage newCase = cases[nextCaseId];
            newCase.appealChallengedNewDeLawContract = finalJudgementDelawContinue;
            if(!finalJudgementDelawContinue)
            {
                ERC721TokenIds[caseId].push(defaultContractTradLawId);
                ERC721TokenURLs[caseId].push(defaultContractTradLawURL);
            }
            //Maint fee to ensure reliability of protocol
            uint256 maintFee = (((arbitrationCase.depositAmount * 2 ) + (disputeCase.disputerChallengeFeeBalance))/20);
            ChangeMaintenenceBalance(arbitrationCase.contractCurrency, maintFee, true);
        }
    }
}
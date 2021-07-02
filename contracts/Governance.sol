// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./TellorVars.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IController.sol";

contract Governance is TellorVars{

    uint256 public voteCount;
    uint256 public disputeFee;
    mapping (address => Delegation[]) delegateInfo;
    mapping(bytes4 => bool) functionApproved;
    mapping(bytes32 => uint[]) voteRounds;//shows if a certain vote has already started
    mapping(uint => Vote) voteInfo;
    mapping(uint => Dispute) disputeInfo;
    mapping(uint => uint) openDisputesOnId;
    mapping(uint => TypeDetails) voteInformation;// (1 - dispute, 2- upgrade proposal, 3- variable change)
    enum VoteResult {FAILED,PASSED,INVALID}

    struct Delegation {
        address delegate;
        uint fromBlock;
    }

    struct Dispute {
        uint requestId;
        uint timestamp;
        bytes value;
        address reportedMiner; //miner who submitted the 'bad value' will get disputeFee if dispute vote fails
    }

    struct Vote {
        bytes32 identifierHash;
        uint256 voteType;
        uint256 voteRound;
        uint startDate;
        uint blockNumber;
        uint256 fee;
        uint tallyDate;
        uint doesSupport;
        uint against;
        bool executed; //is the dispute settled
        VoteResult result; //did the vote pass?
        bool isDispute;
        uint256 invalidQuery;
        bytes data;
        bytes4 voteFunction;
        address voteAddress; //address of contract to execute function on
        address initiator; //miner reporting the 'bad value'-pay disputeFee will get reportedMiner's stake if dispute vote passes
        mapping(address => bool) voted; //mapping of address to whether or not they voted
    }

    struct TypeDetails{
        uint quorum;
        uint voteDuration;
    }
    
    /*Events*/
    event NewDispute(uint256 _id, uint256 _requestId, uint256 _timestamp, address _reporter);
    event NewVote(address _contract, bytes4 _function, bytes _data);
    event Voted(uint256 _voteId, bool _supports, address _voter, uint _voteWeight, bool _invalidQuery);
    event VoteExecuted(uint256 _id, VoteResult _result);
    event VoteTallied(uint256 _id, VoteResult _result);

    constructor(){
        voteInformation[1].quorum = 0;
        voteInformation[1].voteDuration = 2 days;
        voteInformation[2].quorum = 5;
        voteInformation[2].voteDuration = 7 days;
        voteInformation[3].quorum = 2;
        voteInformation[3].voteDuration = 7 days;
        bytes4[11] memory _funcs = [
            bytes4(0x3c46a185),//changeControllerContract(address)
            0xe8ce51d7,//changeGovernanceContract(address)
            0x1cbd3151,//changeOracleContract(address)
            0xbd87e0c9,//changeTreasuryContract(address)
            0x740358e6,//changeUint(bytes32,uint256)
            0x40c10f19,//mint(address,uint256)
            0xe8a230db,//addApprovedFunction(bytes)
            0xfad40294,//changeTypeInformation(uint256,uint256,uint256)
            0xe280e8e8,//changeMiningLock(uint256)
            0x6274885f,//issueTreasury(uint256,uint256,uint256)
            0xf3ff955a//delegateVotingPower(address)
        ];
        for(uint256 _i =0;_i< _funcs.length;_i++){
            functionApproved[_funcs[_i]] = true;
        }
    }
    function addApprovedFunction(bytes4 _func) public{
        require(msg.sender == address(this));
        functionApproved[_func] = true;
    }

    function changeTypeInformation(uint256 _id,uint256 _quorum, uint256 _duration) public {
        require(msg.sender == address(this));
        voteInformation[_id].quorum = _quorum;
        voteInformation[_id].voteDuration = _duration;
    }

    /**
     * @dev Helps initialize a dispute by assigning it a disputeId
     * when a miner returns a false/bad value on the validate array(in Tellor.ProofOfWork) it sends the
     * invalidated value information to POS voting
     * @param _requestId being disputed
     * @param _timestamp being disputed
     */
    function beginDispute(uint256 _requestId,uint256 _timestamp) external {
        address _oracle = IController(TELLOR_ADDRESS).addresses(_ORACLE_CONTRACT);
        require(IOracle(_oracle).getBlockNumberByTimestamp(_requestId, _timestamp) != 0, "Mined block is 0");
        address _reporter = IOracle(_oracle).getReporterByTimestamp(_requestId,_timestamp);
        bytes32 _hash = keccak256(abi.encodePacked(_requestId, _timestamp));
        voteCount++;
        uint256 _id = voteCount;
        voteRounds[_hash].push(_id);
        if (voteRounds[_hash].length > 1) {
            uint256 _prevId = voteRounds[_hash][voteRounds[_hash].length - 2];
            require(block.timestamp - voteInfo[_prevId].tallyDate < 1 days);//1 day for new disputes
        } else {
            require(block.timestamp - _timestamp < IOracle(_oracle).miningLock(), "Dispute must be started within 12 hours...same variable as mining lock");
        }
        Vote storage _thisVote = voteInfo[_id];
        Dispute storage _thisDispute = disputeInfo[_id];
        _thisVote.identifierHash = _hash;
        _thisDispute.requestId = _requestId;
        _thisDispute.timestamp = _timestamp;
        _thisDispute.value = IOracle(_oracle).getValueByTimestamp(_requestId, _timestamp);
        _thisDispute.reportedMiner = _reporter;
        _thisVote.initiator = msg.sender;
        _thisVote.blockNumber = block.number;
        _thisVote.startDate = block.timestamp;
        _thisVote.voteRound = voteRounds[_hash].length;
        _thisVote.isDispute = true;
        openDisputesOnId[_requestId]++;
        uint256 _fee = disputeFee * openDisputesOnId[_requestId] * voteRounds[_hash].length;//check this
        _thisVote.fee = _fee * 9 / 10;
        require(IController(TELLOR_ADDRESS).approveAndTransferFrom(msg.sender, address(this), _fee)); //This is the fork fee (just 100 tokens flat, no refunds.  Goes up quickly to dispute a bad vote)
        IOracle(_oracle).addTip(_requestId,_fee/10);
        IOracle(_oracle).removeValue(_id,_timestamp);//Pull value from on-chain
        IController(TELLOR_ADDRESS).changeStakingStatus(_reporter,3);
        emit NewDispute(_id, _requestId, _timestamp, _reporter);
    }

    function delegate(address _delegate) external{
        Delegation[] storage checkpoints = delegateInfo[msg.sender];
        if (
            checkpoints.length == 0 ||
            checkpoints[checkpoints.length - 1].fromBlock != block.number
        ) {
            checkpoints.push(
                Delegation({
                    delegate: _delegate,
                    fromBlock: uint128(block.number)
                })
            );
        } else {
            Delegation storage oldCheckPoint =
                checkpoints[checkpoints.length - 1];
            oldCheckPoint.delegate = _delegate;
        }
    }

    /**
     * @dev Queries the balance of _user at a specific _blockNumber
     * @param _user The address from which the balance will be retrieved
     * @param _blockNumber The block number when the balance is queried
     * @return The balance at _blockNumber specified
     */
    function delegateOfAt(address _user, uint256 _blockNumber)
        public
        view
        returns (address)
    {
        Delegation[] storage checkpoints = delegateInfo[_user];
        if (
            checkpoints.length == 0 || checkpoints[0].fromBlock > _blockNumber
        ) {
            return address(0);
        } else {
            if (_blockNumber >= checkpoints[checkpoints.length - 1].fromBlock)
                return checkpoints[checkpoints.length - 1].delegate;
            // Binary search of the value in the array
            uint256 min = 0;
            uint256 max = checkpoints.length - 2;
            while (max > min) {
                uint256 mid = (max + min + 1) / 2;
                if (checkpoints[mid].fromBlock == _blockNumber) {
                    return checkpoints[mid].delegate;
                } else if (checkpoints[mid].fromBlock < _blockNumber) {
                    min = mid;
                } else {
                    max = mid - 1;
                }
            }
            return checkpoints[min].delegate;
        }
    }

    function executeVote(uint256 _id) external{
        Vote storage _thisVote = voteInfo[_id];
        require(_id < voteCount);
        require(!_thisVote.executed, "Vote has been executed");
        require(_thisVote.tallyDate > 0, "Vote must be tallied");
        require(voteRounds[_thisVote.identifierHash].length == _thisVote.voteRound, "must be the final vote");
        require(block.timestamp - _thisVote.tallyDate > 86400 * _thisVote.voteRound, "vote needs to be tallied and time must pass");
        _thisVote.executed = true;
        if(!_thisVote.isDispute){
            if(_thisVote.result == VoteResult.PASSED){
                address _destination = _thisVote.voteAddress;
                bool _succ;
                bytes memory _res;
                (_succ, _res) = _destination.call(abi.encodePacked(_thisVote.voteFunction,_thisVote.data));
            }
            emit VoteExecuted(_id, _thisVote.result);
        }else{
            Dispute storage _thisDispute = disputeInfo[_id];
            IController _controller = IController(TELLOR_ADDRESS);
            uint256 _i;
            uint256 _voteID;
            if(_thisVote.result == VoteResult.PASSED){
                for(_i=voteRounds[_thisVote.identifierHash].length-1;_i>=0;_i--){
                    _voteID = voteRounds[_thisVote.identifierHash][_i];
                    if(_i == 0){
                        _controller.slashMiner(_thisDispute.reportedMiner ,_thisVote.initiator);
                    }
                    _controller.transfer(_thisVote.initiator,_thisVote.fee);
                }
                _controller.changeStakingStatus(_thisDispute.reportedMiner,5);
            }else if(_thisVote.result == VoteResult.INVALID){
                _voteID = voteRounds[_thisVote.identifierHash][_i];
                for(_i=voteRounds[_thisVote.identifierHash].length-1;_i>=0;_i--){
                   _controller.transfer(_thisVote.initiator,_thisVote.fee);
                }
                _controller.changeStakingStatus(_thisDispute.reportedMiner,1);
            }else if(_thisVote.result == VoteResult.FAILED){
                _voteID = voteRounds[_thisVote.identifierHash][_i];
                for(_i=voteRounds[_thisVote.identifierHash].length-1;_i>=0;_i--){
                    _controller.transfer(_thisDispute.reportedMiner,_thisVote.fee);
                }
                _controller.changeStakingStatus(_thisDispute.reportedMiner,1);
            }
            openDisputesOnId[_thisDispute.requestId]--;
            emit VoteExecuted(_id, _thisVote.result);
        }
    }

   function proposeVote(address _contract,bytes4 _function, bytes calldata _data, uint256 _timestamp) public{
        voteCount++;
        uint256 _id = voteCount;
        Vote storage _thisVote = voteInfo[_id];
        if(_timestamp == 0){
            _timestamp = block.timestamp;
        }
        bytes32 _hash = keccak256(abi.encodePacked(_contract,_function,_data,_timestamp));
        voteRounds[_hash].push(_id);
        if (voteRounds[_hash].length > 1) {
            uint256 _prevId = voteRounds[_hash][voteRounds[_hash].length - 2];
            require(block.timestamp - voteInfo[_prevId].tallyDate < 1 days);//1 day for new disputes
        } 
        _thisVote.identifierHash = _hash;
        uint256 _fee = 100e18 * 2**(voteRounds[_hash].length - 1);
        //should we add a way to not need to approve here?
        require(IController(TELLOR_ADDRESS).approveAndTransferFrom(msg.sender, address(this), _fee)); //This is the fork fee (just 100 tokens flat, no refunds.  Goes up quickly to dispute a bad vote)
        _thisVote.voteRound = voteRounds[_hash].length;
        _thisVote.startDate = block.timestamp;
        _thisVote.blockNumber = block.number;
        _thisVote.fee = _fee;
        _thisVote.data = _data;
        _thisVote.voteFunction = _function;
        _thisVote.voteAddress = _contract;
        _thisVote.initiator = msg.sender;
        require(_contract == TELLOR_ADDRESS || 
            _contract == IController(TELLOR_ADDRESS).addresses(_GOVERNANCE_CONTRACT) ||
            _contract == IController(TELLOR_ADDRESS).addresses(_TREASURY_CONTRACT) ||
            _contract == IController(TELLOR_ADDRESS).addresses(_ORACLE_CONTRACT)
        );
        require(functionApproved[_function]);
        emit NewVote(_contract,_function,_data);
    }

        /**
     * @dev tallies the votes and begins the 1 day challenge period
     * @param _id is the dispute id
     */
    function tallyVotes(uint256 _id) external {
        Vote storage _thisVote = voteInfo[_id];
        require(_thisVote.executed == false, "Dispute has been already executed");
        require(_thisVote.tallyDate == 0, "vote should not already be tallied");
        require(
            block.timestamp -_thisVote.startDate > voteInformation[_thisVote.voteType].voteDuration,
            "Time for voting haven't elapsed"
        );
        if(_thisVote.invalidQuery > _thisVote.doesSupport && _thisVote.invalidQuery > _thisVote.against){
            _thisVote.result = VoteResult.INVALID;
        }
        else if (_thisVote.doesSupport > _thisVote.against) {
                if (_thisVote.doesSupport >= ((IController(TELLOR_ADDRESS).uints(_TOTAL_SUPPLY) * voteInformation[_thisVote.voteType].quorum) / 100)) {
                _thisVote.result = VoteResult.PASSED;
                Dispute storage _thisDispute = disputeInfo[_id];
                (uint256 _status,) = IController(TELLOR_ADDRESS).getStakerInfo(_thisDispute.reportedMiner);
                if(_thisVote.isDispute && _status == 3){
                        IController(TELLOR_ADDRESS).changeStakingStatus(_thisDispute.reportedMiner,4);
                }
            }
        }
        else{
            _thisVote.result = VoteResult.FAILED;
        }
        _thisVote.tallyDate = block.timestamp;
        emit VoteTallied(_id, _thisVote.result);
    }

        /**
     * @dev This function updates the minimum dispute fee as a function of the amount
     * of staked miners
     */
    function updateMinDisputeFee() public {
        uint256 _stakeAmt = IController(TELLOR_ADDRESS).uints(_STAKE_AMOUNT);
        uint256 _trgtMiners = IController(TELLOR_ADDRESS).uints(_TARGET_MINERS);
        disputeFee = _max(
            15e18,
            (_stakeAmt -
                ((_stakeAmt *
                    (_min(_trgtMiners, IController(TELLOR_ADDRESS).uints(_STAKE_COUNT)) * 1000)) /
                    _trgtMiners) /
                1000)
        );
    }

    function verify() external pure returns(uint){
        return 9999;
    }


    function vote(uint256 _id, bool _supports, bool _invalidQuery) external{
        require(delegateOfAt(msg.sender, voteInfo[_id].blockNumber) == address(0), "the vote should not be delegated");
        _vote(msg.sender,_id,_supports,_invalidQuery);
    }

    function voteFor(address[] calldata _addys,uint256 _id, bool _supports, bool _invalidQuery) external{
        for(uint _i=0;_i<_addys.length;_i++){
            require(delegateOfAt(_addys[_i],voteInfo[_id].blockNumber)== msg.sender);
            _vote(_addys[_i],_id,_supports,_invalidQuery);
        }
    }

    function _vote(address _voter, uint256 _id, bool _supports, bool _invalidQuery) internal {
        require(_id <= voteCount, "vote does not exist");
        Vote storage _thisVote = voteInfo[_id];
        require(_thisVote.tallyDate == 0, "the vote has already been tallied");
        IController _controller = IController(TELLOR_ADDRESS);
        uint256 voteWeight = _controller.balanceOfAt(_voter,_thisVote.blockNumber);
        IOracle _oracle = IOracle(_controller.addresses(_ORACLE_CONTRACT));
        voteWeight +=  _oracle.getReportsSubmittedByAddress(_voter);
        voteWeight += _oracle.getTipsByUser(_voter)/2;
        (uint256 _status,) = _controller.getStakerInfo(_voter);
        require(_status != 3);
        require(_thisVote.voted[_voter] != true, "Sender has already voted");
        require(voteWeight != 0, "User balance is 0");
        _thisVote.voted[_voter] = true;
        if(_thisVote.isDispute && _invalidQuery){
            _thisVote.invalidQuery += voteWeight;
        } else if(_supports) {
            _thisVote.doesSupport += voteWeight;
        } else {
            _thisVote.against += voteWeight;
        }
        emit Voted(_id, _supports, _voter, voteWeight,_invalidQuery);
    }



    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
    /*Getters*/
    function getDelegateInfo(address _holder) external view returns(address,uint){
        return (delegateOfAt(_holder,block.number), delegateInfo[_holder][delegateInfo[_holder].length-1].fromBlock);
    }

    function isFunctionApproved(bytes4 _func) external view returns(bool){
        return functionApproved[_func];
    }

    function getVoteRounds(bytes32 _hash) external view returns(uint256[] memory){
        return voteRounds[_hash];
    }

    function getVoteInfo(uint256 _id) external view returns(bytes32,uint256[9] memory,bool[2] memory,
                                                            VoteResult,bytes memory,bytes4,address[2] memory){
        Vote storage _v = voteInfo[_id];
        return (_v.identifierHash,[_v.voteType,_v.voteRound,_v.startDate,_v.blockNumber,_v.fee,
        _v.tallyDate,_v.doesSupport,_v.against,_v.invalidQuery],[_v.executed,_v.isDispute],_v.result,
        _v.data,_v.voteFunction,[_v.voteAddress,_v.initiator]);
    }


    function getDisputeInfo(uint256 _id) external view returns(uint256,uint256,bytes memory, address){
        Dispute storage _d = disputeInfo[_id];
        return (_d.requestId,_d.timestamp,_d.value,_d.reportedMiner);
    }

    function getOpenDisputesOnId(uint256 _id) external view returns(uint256){
        return openDisputesOnId[_id];
    }

    function getTypeDetails(uint256 _type) external view returns(uint256, uint256){
        return (voteInformation[_type].quorum, voteInformation[_type].voteDuration);
    }

    function didVote(uint256 _id, address _voter) external view returns(bool){
        return voteInfo[_id].voted[_voter];
    }


}
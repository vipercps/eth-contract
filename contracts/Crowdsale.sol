pragma solidity ^0.4.11;


import "./interfaces/Pausable.sol";
import "./interfaces/PullPayment.sol";
import "./SggCoin.sol";

/*
  Crowdsale Smart Contract for the SggCoin.org project
  This smart contract collects ETH, and in return emits SggCoin tokens to the backers
*/
contract Crowdsale is Pausable, PullPayment {

    using SafeMath for uint;

  	struct Backer {
		uint weiReceived; // Amount of Ether given
		uint coinSent;
	}

	/*
	* Constants
	*/
	uint public constant MIN_CAP = 5000000000;       // min: 5,000 SggCoins 
	uint public constant MAX_CAP = 500000000000000;  // max: 500,000,000 SggCoins
	uint public constant MIN_INVEST_ETHER = 100 finney;
	uint private constant CROWDSALE_PERIOD = 30 days;
	uint public constant COIN_PER_ETHER = 5000000000; // 5,000 SggCoins/ETH


	/*
	* Variables
	*/
	/* SggCoin contract reference */
	SggCoin public coin;
    /* Multisig contract that will receive the Ether */
	address public multisigEther;
	/* Number of Ether received */
	uint public etherReceived;
	/* Number of SggCoins sent to Ether contributors */
	uint public coinSentToEther;
	/* Crowdsale start time */
	uint public startTime;
	/* Crowdsale end time */
	uint public endTime;
 	/* Is crowdsale still on going */
	bool public crowdsaleClosed;

	/* Backers Ether indexed by their Ethereum address */
	mapping(address => Backer) public backers;


	/*
	* Modifiers
	*/
	modifier minCapNotReached() {
		if ((now < endTime) || coinSentToEther >= MIN_CAP ) throw;
		_;
	}

	modifier respectTimeFrame() {
		if ((now < startTime) || (now > endTime )) throw;
		_;
	}

	/*
	 * Event
	*/
	event LogReceivedETH(address addr, uint value);
	event LogCoinsEmited(address indexed from, uint amount);

	/*
	 * Constructor
	*/
	function Crowdsale(address _SggCoinAddress, address _to) {
		coin = SggCoin(_SggCoinAddress);
		multisigEther = _to;
	}

	/*
	 * The fallback function corresponds to a donation in ETH
	 */
	function() stopInEmergency respectTimeFrame payable {
		receiveETH(msg.sender);
	}

	/*
	 * To call to start the crowdsale
	 */
	function start() onlyOwner {
		if (startTime != 0) throw; // Crowdsale was already started

		startTime = now ;
		endTime =  now + CROWDSALE_PERIOD;
	}

	/*
	 *	Receives a donation in Ether
	*/
	function receiveETH(address beneficiary) internal {
		if (msg.value < MIN_INVEST_ETHER) throw; // Don't accept funding under a predefined threshold

		uint coinToSend = bonus(msg.value.mul(COIN_PER_ETHER).div(1 ether)); // Compute the number of SggCoin to send
		if (coinToSend.add(coinSentToEther) > MAX_CAP) throw;

		Backer backer = backers[beneficiary];
		coin.transfer(beneficiary, coinToSend); // Transfer SggCoins right now

		backer.coinSent = backer.coinSent.add(coinToSend);
		backer.weiReceived = backer.weiReceived.add(msg.value); // Update the total wei collected during the crowdfunding for this backer

		etherReceived = etherReceived.add(msg.value); // Update the total wei collected during the crowdfunding
		coinSentToEther = coinSentToEther.add(coinToSend);

		// Send events
		LogCoinsEmited(msg.sender ,coinToSend);
		LogReceivedETH(beneficiary, etherReceived);
	}


	/*
	 *Compute the SggCoin bonus according to the investment period
	 */
	function bonus(uint amount) internal constant returns (uint) {
		if (now < startTime.add(2 days)) return amount.add(amount.div(5));   // bonus 20%
		return amount;
	}

	/*
	 * Finalize the crowdsale, should be called after the refund period
	*/
	function finalize() onlyOwner public {

		if (now < endTime) { // Cannot finalise before CROWDSALE_PERIOD or before selling all coins
			if (coinSentToEther == MAX_CAP) {
			} else {
				throw;
			}
		}

		if (coinSentToEther < MIN_CAP && now < endTime + 15 days) throw; // If MIN_CAP is not reached donors have 15days to get refund before we can finalise

		if (!multisigEther.send(this.balance)) throw; // Move the remaining Ether to the multisig address

		uint remains = coin.balanceOf(this);
		if (remains > 0) { // Burn the rest of SggCoins
			if (!coin.burn(remains)) throw ;
		}
		crowdsaleClosed = true;
	}

	/*
	* Failsafe drain
	*/
	function drain() onlyOwner {
		if (!owner.send(this.balance)) throw;
	}

	/**
	 * Allow to change the team multisig address in the case of emergency.
	 */
	function setMultisig(address addr) onlyOwner public {
		if (addr == address(0)) throw;
		multisigEther = addr;
	}

	/**
	 * Manually back SggCoin owner address.
	 */
	function backSggCoinOwner() onlyOwner public {
		coin.transferOwnership(owner);
	}

	/**
	 * Transfer remains to owner in case if impossible to do min invest
	 */
	function getRemainCoins() onlyOwner public {
		var remains = MAX_CAP - coinSentToEther;
		uint minCoinsToSell = bonus(MIN_INVEST_ETHER.mul(COIN_PER_ETHER) / (1 ether));

		if(remains > minCoinsToSell) throw;

		Backer backer = backers[owner];
		coin.transfer(owner, remains); // Transfer SggCoins right now

		backer.coinSent = backer.coinSent.add(remains);

		coinSentToEther = coinSentToEther.add(remains);

		// Send events
		LogCoinsEmited(this ,remains);
		LogReceivedETH(owner, etherReceived);
	}


	/*
  	 * When MIN_CAP is not reach:
  	 * 1) backer call the "approve" function of the SggCoin token contract with the amount of all SggCoins they got in order to be refund
  	 * 2) backer call the "refund" function of the Crowdsale contract with the same amount of SggCoins
   	 * 3) backer call the "withdrawPayments" function of the Crowdsale contract to get a refund in ETH
   	 */
	function refund(uint _value) minCapNotReached public {

		if (_value != backers[msg.sender].coinSent) throw; // compare value from backer balance

		coin.transferFrom(msg.sender, address(this), _value); // get the token back to the crowdsale contract

		if (!coin.burn(_value)) throw ; // token sent for refund are burnt

		uint ETHToSend = backers[msg.sender].weiReceived;
		backers[msg.sender].weiReceived=0;

		if (ETHToSend > 0) {
			asyncSend(msg.sender, ETHToSend); // pull payment to get refund in ETH
		}
	}

}

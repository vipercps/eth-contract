pragma solidity ^0.4.11;

import "./erc20/StandardToken.sol";
import "./interfaces/Ownable.sol";


/**
 *  SggCoin token contract. Implements
 */
contract SggCoin is StandardToken, Ownable {
  string public constant name = "StuffGoGo";
  string public constant symbol = "SGG";
  uint public constant decimals = 6;


  // Constructor
  function SggCoin() {
      totalSupply = 1000000000000000;
      balances[msg.sender] = totalSupply; // Send all tokens to owner
  }

  /**
   *  Burn away the specified amount of SggCoin tokens
   */
  function burn(uint _value) onlyOwner returns (bool) {
    balances[msg.sender] = balances[msg.sender].sub(_value);
    totalSupply = totalSupply.sub(_value);
    Transfer(msg.sender, 0x0, _value);
    return true;
  }

}

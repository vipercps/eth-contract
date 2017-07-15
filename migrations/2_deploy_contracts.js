var SafeMath = artifacts.require("./common/SafeMath.sol");
var SggCoin = artifacts.require("./SggCoin.sol");
var Crowdsale = artifacts.require("./Crowdsale.sol");


module.exports = function(deployer) {

	var owner = web3.eth.accounts[0];
	var wallet = web3.eth.accounts[1];

	// var owner = '';
	// var wallet = '';

	console.log("Owner address: " + owner);
	console.log("Wallet address: " + wallet);

	deployer.deploy(SafeMath, { from: owner });
	deployer.link(SafeMath, SggCoin);
	return deployer.deploy(SggCoin, { from: owner }).then(function() {
		console.log("SggCoin address: " + SggCoin.address);
		return deployer.deploy(Crowdsale, SggCoin.address, wallet, { from: owner }).then(function() {
			console.log("Crowdsale address: " + Crowdsale.address);
			return SggCoin.deployed().then(function(coin) {
				return coin.owner.call().then(function(owner) {
					console.log("SggCoin owner : " + owner);
					return coin.transferOwnership(Crowdsale.address, {from: owner}).then(function(txn) {
						console.log("SggCoin owner was changed: " + Crowdsale.address);
					});
				})
			});
		});
	});
};

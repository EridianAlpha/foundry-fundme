-include .env

build:; forge build # ; is used to run multiple commands in one line

deploy-holesky:
	forge script script/DeployFundMe.s.sol:DeployFundMe --rpc-url $(HOLESKY_RPC_URL) --private-key $(HOLESKY_PRIVATE_KEY) --broadcast -vvvv

deploy-holesky-verify:
	forge script script/DeployFundMe.s.sol:DeployFundMe --rpc-url $(HOLESKY_RPC_URL) --private-key $(HOLESKY_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
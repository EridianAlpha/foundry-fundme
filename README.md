# FundMe Template Project - Foundry

This project is a template showing how to get started with Foundry, testing, and deploying a simple smart contract.

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

<https://book.getfoundry.sh>

## Usage

### Makefile

• Use the Makefile to run common commands

```shell
make help
make anvil
make deploy
make fund
make withdraw
```

### Build

```shell
forge build
```

### Test

```shell
forge test
forge test -vvv
```

### Test Coverage

```shell
forge coverage
```

[Coverage line highlighting in VSCode](https://mirror.xyz/devanon.eth/RrDvKPnlD-pmpuW7hQeR5wWdVjklrpOgPCOA-PJkWFU)

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Anvil

```shell
anvil
```

### Deploy

```shell

```

### Cast

```shell
cast <subcommand>
```

### Help

```shell
forge --help
anvil --help
cast --help
```

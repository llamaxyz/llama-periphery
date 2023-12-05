![Llama](.github/assets/llama-banner.png)

![CI](https://github.com/llamaxyz/llama-periphery/actions/workflows/ci.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# Llama Periphery

Llama is an onchain governance and access control framework for smart contracts.
This repository contains supporting modules for operating Llama instances.
For the core contracts, see the [Llama](https://github.com/llamaxyz/llama)
repository.

## Modules

- **Token Voting:** smart contract policies that allow `ERC20Votes` or `ERC721Votes` tokenholders to create actions enforced by delegated token thresholds or collectively approve or disapprove an action through token voting.

## Prerequisites

[Foundry](https://github.com/foundry-rs/foundry) must be installed.
You can find installation instructions in the [Foundry docs](https://book.getfoundry.sh/getting-started/installation).

We use [just](https://github.com/casey/just) to save and run a few larger, more complex commands.
You can find installation instructions in the [just docs](https://just.systems/man/en/).
All commands can be listed by running `just -l` from the repo root, or by viewing the [`justfile`](https://github.com/llamaxyz/llama/blob/main/justfile).

### VS Code

You can get Solidity support for Visual Studio Code by installing the [Hardhat Solidity extension](https://github.com/NomicFoundation/hardhat-vscode).

## Installation

```sh
$ git clone https://github.com/llamaxyz/llama-periphery.git
$ cd llama
$ forge install
```

## Setup

Copy `.env.example` and rename it to `.env`.
The comments in that file explain what each variable is for and when they're needed:

- The `MAINNET_RPC_URL` variable is the only one that is required for running tests.
- You may also want a mainnet `ETHERSCAN_API_KEY` for better traces when running fork tests.
- The rest are only needed for deployment verification with forge scripts. An anvil default private key is provided in the `.env.example` file to facilitate testing.

### Commands

- `forge build` - build the project
- `forge test` - run tests

### Deploy and Verify

- `just deploy` - deploy and verify payload on mainnet
- Run `just -l` or see the [`justfile`](https://github.com/llamaxyz/llama/blob/main/justfile) for other commands such as dry runs.

## Smart contract reference

Run the following command to generate smart contract reference documentation from our NatSpec comments and serve those static files locally:

```sh
$ forge doc -o reference/ -b -s
```
## Bug bounty program

This repository is subject to the Llama bug bounty program. Details can be found [here](https://github.com/llamaxyz/llama/blob/main/README.md#bug-bounty-program).

## Slither

Use our bash script to prevent slither from analyzing the test and script directories.

```sh
$ chmod +x slither.sh
$ ./slither.sh
```
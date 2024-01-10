# Overview

## What is Llama?

Llama is an onchain governance and access control framework for smart contracts.

Using Llama, teams can deploy fully independent instances that define granular roles and permissions for executing transactions, known as "actions".

Llama instances can adapt over time by adding new participants and expanding the set of available actions. Actions can be any operation that is represented by invoking a smart contract function. This includes transferring funds, updating a registry, changing protocol parameters, or activating an emergency pause.

Learn more about Llama by reading [the protocol documentation](https://github.com/llamaxyz/llama/tree/main/docs).

## What is Llama Periphery?

This repository contains supporting modules for operating Llama instances. Modules are extensions to Llama instances that can be adopted by using a Llama action to configure and deploy.

## Modules

- [Token Voting](https://github.com/llamaxyz/llama-periphery/tree/main/docs/token-voting/README.md): enables governance token holders to create actions enforced by thresholds and collectively vote to approve or disapprove an action.

# Token Adapters

Token Adapters allow the Llama Token Governer to connect to many different implementations of tokens. 

Out of the box, we support ERC20 and ERC721 tokens that implement the [IVotes interface](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol) and checkpoint supply using `block.timestamp`.

Many tokens checkpoint using `block.number`, or have different method names than the `IVotes` interface. The purpose of the adapter is to provide a constant interface for the governor, while being flexible to handle many diffent token implementations.

Currently only timestamp based tokens are supported, but we can extend functionality to tokens that checkpoint in block number by writing a new adapter. 
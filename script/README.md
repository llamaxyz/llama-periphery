# Llama Periphery Scripts

The current Llama periphery scripts are:
* `DeployLlamaTokenVotingFactory.s.sol`, which deploys the LlamaTokenVotingFactory to new chains

## DeployLlamaTokenVotingFactory

To perform a dry-run of the `DeployLlamaFactory` script on a network, first set the
`SCRIPT_RPC_URL` variable in your `.env` file to a local node, e.g. anvil.

To start anvil:

```shell
# Start anvil, forking from the desired network.
anvil --fork-url $OPTIMISM_RPC_URL
```
Next, set `SCRIPT_PRIVATE_KEY` in your `.env` file. For a dry run, you can just
use one of the pre-provisioned private keys that anvil provides on startup.

Then, to execute the call:

```shell
just dry-run-deploy
```

If that looked good, try broadcasting the script transactions to the local node.
With the local node URL still set as `SCRIPT_RPC_URL` in your `.env` file:

```shell
just deploy
```

When you are ready to deploy to a live network, simply follow the steps above
but with `SCRIPT_RPC_URL` pointing to the appropriate node and
`SCRIPT_PRIVATE_KEY` set to the deployer private key.

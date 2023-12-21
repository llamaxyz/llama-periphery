# Llama Periphery Scripts

The current Llama periphery scripts are:
* `DeployLlamaTokenVotingFactory.s.sol`, which deploys the `LlamaTokenVotingFactory` to new chains
* `DeployLlamaTokenVotingModule.s.sol`, which deploys a new Llama token voting module

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

## DeployLlamaTokenVotingModule

The `DeployLlamaTokenVotingModule` script presupposes that the `DeployLlamaTokenVotingFactory` script has already
been run for a given chain. So follow the instructions above before continuing
here.

Once `DeployLlamaTokenVotingFactory` has been run, set a `SCRIPT_DEPLOYER_ADDRESS` in your `.env` that corresponds to the `SCRIPT_PRIVATE_KEY` that you want deploy the Llama instance.
It does *not* have to be the same address that did the initial deploy, but it could be.
Add your desired Llama instance configuration JSON file to `script/input/<CHAIN_ID_OF_DEPLOYMENT_CHAIN>` and update the `run-deploy-voting-module-script` command in the `justfile` to match your configuration's filename.

Once your `.env` file is configured and anvil is running, you can perform a dry
run like this:

```shell
just dry-run-deploy-voting-module
```

If all goes well, broadcast as follows:

```shell
just deploy-voting-module
```

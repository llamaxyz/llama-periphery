#!/usr/bin/env -S just --justfile

set dotenv-load

report:
  forge clean && FOUNDRY_PROFILE=ci forge test --gas-report --fuzz-seed 1 | sed -e/\|/\{ -e:1 -en\;b1 -e\} -ed | cat > .gas-report

yul contractName:
  forge inspect {{contractName}} ir-optimized > yul.sol

run-script script_name flags='' sig='' args='':
  # To speed up compilation we temporarily rename the test directory.
  mv test _test
  # We hyphenate so that we still cleanup the directory names even if the deploy fails.
  - FOUNDRY_PROFILE=ci forge script script/{{script_name}}.s.sol {{sig}} {{args}} \
    --rpc-url $SCRIPT_RPC_URL \
    --private-key $SCRIPT_PRIVATE_KEY \
    -vvvv {{flags}}
  mv _test test

# Token voting module

dry-run-deploy: (run-script 'DeployLlamaTokenVotingFactory')

deploy: (run-script 'DeployLlamaTokenVotingFactory' '--broadcast --verify --slow --build-info --build-info-path build_info')

verify: (run-script 'DeployLlamaTokenVotingFactory' '--verify --resume')

run-deploy-voting-module-script flags: (run-script 'DeployLlamaTokenVotingModule' flags '--sig "run(address,string)"' '$SCRIPT_DEPLOYER_ADDRESS "tokenVotingModuleConfig.json"')

dry-run-deploy-voting-module: (run-deploy-voting-module-script '')

deploy-voting-module: (run-deploy-voting-module-script '--broadcast --verify')

# Account multicall module

dry-run-deploy-acount-multicall-factory: (run-script 'DeployLlamaAccountMulticallFactory')

deploy-acount-multicall-factory: (run-script 'DeployLlamaAccountMulticallFactory' '--broadcast --verify --slow --build-info --build-info-path build_info')

verify-account-multicall-factory: (run-script 'DeployLlamaAccountMulticallFactory' '--verify --resume')

run-deploy-account-multicall-module-script flags: (run-script 'DeployLlamaAccountMulticallModule' flags '--sig "run(address,string)"' '$SCRIPT_DEPLOYER_ADDRESS "accountMulticallConfig.json"')

dry-run-deploy-account-multicall-module: (run-deploy-account-multicall-module-script '')

deploy-account-multicall-module: (run-deploy-account-multicall-module-script '--broadcast --verify --slow')


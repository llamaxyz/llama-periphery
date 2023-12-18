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
    -vvvvv {{flags}}
  mv _test test

run-deploy-voting-module-script flags: (run-script 'DeployLlamaTokenVotingModule' flags '--sig "run(address,string)"' '$SCRIPT_DEPLOYER_ADDRESS "tokenVotingModuleConfig.json"')

dry-run-deploy: (run-script 'DeployLlamaTokenVotingFactory')

deploy: (run-script 'DeployLlamaTokenVotingFactory' '--broadcast --verify --build-info --build-info-path build_info')

dry-run-deploy-voting-module: (run-deploy-voting-module-script '')

deploy-voting-module: (run-deploy-voting-module-script '--broadcast --verify')

verify: (run-script 'DeployLlamaTokenVotingFactory' '--verify --resume')

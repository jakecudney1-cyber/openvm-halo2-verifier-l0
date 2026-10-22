#!/usr/bin/env bash
# Start the LOCAL Scroll lab chain (loopback only). Stop with stop-anvil.sh.
export PATH="$HOME/.foundry/bin:$PATH"
LAB="$(cd "$(dirname "$0")/.." && pwd)"
if pidof anvil >/dev/null; then echo "anvil already running (pid $(pidof anvil))"; exit 0; fi
nohup anvil --host 127.0.0.1 --port 8545 --chain-id 31337 > "$LAB/anvil.log" 2>&1 &
sleep 2
cast chain-id --rpc-url http://127.0.0.1:8545 && echo "anvil up: http://127.0.0.1:8545 chain 31337"

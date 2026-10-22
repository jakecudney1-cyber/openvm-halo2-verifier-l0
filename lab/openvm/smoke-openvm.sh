#!/usr/bin/env bash
set -u; export PATH="$HOME/.foundry/bin:$PATH"
LAB="$(cd "$(dirname "$0")" && pwd)"; RPC=http://127.0.0.1:8545
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
cd "$LAB"
A=$(forge create --broadcast --rpc-url $RPC --private-key $PK src/OpenVmHalo2Verifier.sol:OpenVmHalo2Verifier 2>/dev/null | awk '/Deployed to:/{print $3}')
echo "OpenVmHalo2Verifier: $A"; [ -n "$A" ] || exit 1
MOD=0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
PV32="0x$(python3 -c "print('00'*32)")"
PD1760="0x$(python3 -c "print('00'*1760)")"
ONE=0x0000000000000000000000000000000000000000000000000000000000000001
TWO=0x0000000000000000000000000000000000000000000000000000000000000002
run(){ echo "--- TEST: $1"; shift; out=$(cast call "$@" --rpc-url $RPC 2>&1); echo "exit=$?"; echo "$out"|head -n 4; }
gas(){ echo "--- GAS: $1"; shift; cast send --rpc-url $RPC --private-key $PK "$@" --json 2>&1 | python3 -c "import json,sys
try:
 d=json.load(sys.stdin); print('status:',d['status'],'gasUsed:',int(d['gasUsed'],16))
except Exception as e: print('send err:',e)"; }
# (a) garbage lengths
run "empty publicValues + empty proofData, commits 1/2" $A "verify(bytes,bytes,bytes32,bytes32)" 0x 0x $ONE $TWO
run "PV 32B, proofData 100B (bad length), commits 1/2" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 "0x$(python3 -c "print('00'*100)")" $ONE $TWO
run "PV 31B, proofData 1760B, commits 1/2" $A "verify(bytes,bytes,bytes32,bytes32)" "0x$(python3 -c "print('00'*31)")" $PD1760 $ONE $TWO
# (b) commitments >= modulus, well-formed lengths
run "appExeCommit == MODULUS" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 $PD1760 $MOD $TWO
run "appVmCommit == MODULUS (exe=1)" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 $PD1760 $ONE $MOD
run "appExeCommit == 0xff..ff" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 $PD1760 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff $TWO
# (c) SMALL arbitrary commitments 1 and 2, well-formed zero payload
run "KEY: commits 1/2, PV=32x00, proofData=1760x00" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 $PD1760 $ONE $TWO
gas "KEY as tx (gasUsed on failure)" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 $PD1760 $ONE $TWO
run "commits 0/0, same zero payload" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 $PD1760 0x0000000000000000000000000000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000000000000000000000000000
run "commits MODULUS-1 / MODULUS-1, zero payload" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 $PD1760 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000
# assert gate: proofData[0:4] != 0 with otherwise well-formed lengths + small commits
run "proofData starts 0xdeadbeef + rest zero, commits 1/2" $A "verify(bytes,bytes,bytes32,bytes32)" $PV32 "0xdeadbeef$(python3 -c "print('00'*1756)")" $ONE $TWO
echo "ADDR=$A"

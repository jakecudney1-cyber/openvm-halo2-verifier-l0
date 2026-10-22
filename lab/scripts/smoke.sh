#!/usr/bin/env bash
# Scroll SWIRL Lane C smoke test — LOCAL anvil only (127.0.0.1:8545, chain 31337).
# Deploys the shipped plonk verifier bytecode + ZkEvmVerifier wrappers from
# scroll-contracts @ 81f0db7 and exercises them with repo test vectors + garbage.
set -u
export PATH="$HOME/.foundry/bin:$PATH"
LAB="$(cd "$(dirname "$0")/.." && pwd)"
RPC=http://127.0.0.1:8545
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # anvil dev acct #0, local only
cd "$LAB"
hexof() { python3 -c "import sys; print(open(sys.argv[1],'rb').read().hex())" "$1"; }

echo "== chain =="; cast chain-id --rpc-url $RPC || { echo "ANVIL NOT UP — run scripts/start-anvil.sh"; exit 1; }

deploy_raw() { cast send --rpc-url $RPC --private-key $PK --create "0x$(hexof "vectors/$1")" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['contractAddress'])"; }
PLONK_RC3=$(deploy_raw plonk_verifier_v0.12.0-rc.3.bin); echo "plonk rc.3 raw verifier: $PLONK_RC3"
PLONK_098=$(deploy_raw plonk_verifier_v0.9.8.bin);       echo "plonk v0.9.8 raw verifier: $PLONK_098"
[ -n "$PLONK_RC3" ] && [ -n "$PLONK_098" ] || { echo "raw deploy failed"; exit 1; }

DIGEST_RC3=0x1311a3daed153730f3eef419f61ee0301c742eba04d71ae8af36fba9e3096552
mk() { forge create --broadcast --rpc-url $RPC --private-key $PK "$@" 2>/dev/null | awk '/Deployed to:/{print $3}'; }
V2=$(mk src/ZkEvmVerifierV2.sol:ZkEvmVerifierV2 --constructor-args $PLONK_RC3 $DIGEST_RC3); echo "ZkEvmVerifierV2: $V2"
V1=$(mk src/ZkEvmVerifierV1.sol:ZkEvmVerifierV1 --constructor-args $PLONK_098); echo "ZkEvmVerifierV1: $V1"
PE=$(mk src/ZkEvmVerifierPostEuclid.sol:ZkEvmVerifierPostEuclid --constructor-args $PLONK_RC3 $DIGEST_RC3 0x0000000000000000000000000000000000000000000000000000000000000000); echo "ZkEvmVerifierPostEuclid (digest2=0, exploratory): $PE"
MVRV=$(mk src/MultipleVersionRollupVerifier.sol:MultipleVersionRollupVerifier --constructor-args "[3]" "[$V2]"); echo "MultipleVersionRollupVerifier(v3->V2): $MVRV"
[ -n "$V2" ] && [ -n "$V1" ] && [ -n "$MVRV" ] || { echo "wrapper deploy failed"; exit 1; }

PI=$(python3 scripts/gen_vectors.py | sed -n 's/^v0.12.0-rc.3 publicInput=//p')
PROOF_RC3="0x$(hexof vectors/v0.12.0-rc.3_proof.data)"
PROOF_098="0x$(hexof vectors/v0.9.8_proof.data)"
HASH_098=0x31b430667bc9e8a8b7eda5e5c76f2250c64023f5f8e0689ac9f4e53f5362da66
echo "publicInput: $PI"
echo "proof rc.3 bytes: $(( (${#PROOF_RC3}-2)/2 )), proof v0.9.8 bytes: $(( (${#PROOF_098}-2)/2 ))"

run() { local label="$1"; shift; echo "--- TEST: $label"; out=$(cast "$@" --rpc-url $RPC 2>&1); rc=$?; echo "exit=$rc"; echo "$out" | head -n 6; }
gas() { local label="$1"; shift; echo "--- TEST: $label"; cast send --rpc-url $RPC --private-key $PK "$@" --json 2>&1 | python3 -c "import json,sys
try:
  d=json.load(sys.stdin); print('status:',d['status'],'gasUsed:',int(d['gasUsed'],16))
except Exception as e: print('send failed:',e)"; }

# VALID-SHAPED (repo test vectors)
run "V2 valid vector (cast call)" call $V2 "verify(bytes,bytes)" $PROOF_RC3 $PI
gas "V2 valid vector (cast send, gas)" $V2 "verify(bytes,bytes)" $PROOF_RC3 $PI
run "V2 valid vector via MultipleVersionRollupVerifier.verifyBundleProof(3,0,...)" call $MVRV "verifyBundleProof(uint256,uint256,bytes,bytes)" 3 0 $PROOF_RC3 $PI
run "V1 valid vector v0.9.8 (cast call)" call $V1 "verify(bytes,bytes32)" $PROOF_098 $HASH_098
gas "V1 valid vector (cast send, gas)" $V1 "verify(bytes,bytes32)" $PROOF_098 $HASH_098

# GARBAGE / MALFORMED
PI_REV=$(python3 -c "pi=bytes.fromhex('${PI#0x}'); print('0x'+pi[::-1].hex())")
run "V2 valid proof + REVERSED publicInput (repo negative case)" call $V2 "verify(bytes,bytes)" $PROOF_RC3 $PI_REV
RAND=$(python3 -c "import os; print('0x'+os.urandom(2144).hex())")
run "V2 random-bytes proof (2144 B) + valid publicInput" call $V2 "verify(bytes,bytes)" $RAND $PI
run "V2 truncated proof (100 B) + valid publicInput" call $V2 "verify(bytes,bytes)" "0x${PROOF_RC3:2:200}" $PI
run "V2 empty proof + valid publicInput" call $V2 "verify(bytes,bytes)" 0x $PI
run "V2 valid proof + empty publicInput" call $V2 "verify(bytes,bytes)" $PROOF_RC3 0x
run "V1 valid proof + reversed hash" call $V1 "verify(bytes,bytes32)" $PROOF_098 0x66da62533f54e9f4ac68e068f8f52340c650f262f5c6e5edb7a8e89ec96630b431
run "PostEuclid fed the V2 valid vector (different encoding; exploratory)" call $PE "verify(bytes,bytes)" $PROOF_RC3 $PI
echo "== addresses =="
echo "PLONK_RC3=$PLONK_RC3 PLONK_098=$PLONK_098 V2=$V2 V1=$V1 PE=$PE MVRV=$MVRV"

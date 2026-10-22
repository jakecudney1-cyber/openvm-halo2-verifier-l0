#!/usr/bin/env python3
"""Replicates hardhat-test/ZkEvmVerifierV2.spec.ts genPublicInputs() and the
ZkEvmVerifierV1.spec.ts publicInputHash derivation, byte-for-byte, from the
repo's own test vectors. Pure local file processing."""
import sys, os
V = os.path.join(os.path.dirname(__file__), "..", "vectors")

def gen_public_inputs(inst: bytes) -> bytes:
    pi = bytearray(172)
    # layer2ChainId: last 8 bytes of instances[0x120:0x140]
    for i in range(8):
        pi[i] = inst[0x140 - (8 - i)]
    # numBatches: uint(instances[0x180:0x1a0]) + 1, big-endian 4 bytes
    nb = int.from_bytes(inst[0x180:0x1A0], "big") + 1
    pi[8:12] = nb.to_bytes(4, "big")
    # fields: concat(last16(word_k), last16(word_k+1)) per spec code
    def field(out_off, w1, w2):
        for i in range(16):
            pi[out_off + i] = inst[w1 - (16 - i)]
            pi[out_off + 16 + i] = inst[w2 - (16 - i)]
    field(12, 0x40, 0x60)    # prevStateRoot
    field(44, 0x80, 0xA0)    # prevBatchHash
    field(76, 0xC0, 0xE0)    # postStateRoot
    field(108, 0x100, 0x120) # batchHash
    field(140, 0x160, 0x180) # withdrawRoot
    return bytes(pi)

for ver in ["v0.12.0-rc.2", "v0.12.0-rc.3"]:
    inst = open(os.path.join(V, f"{ver}_pi.data"), "rb").read()
    assert len(inst) == 416, len(inst)
    pi = gen_public_inputs(inst)
    digest = inst[0:32]
    print(f"{ver} digest=0x{digest.hex()}")
    print(f"{ver} publicInput=0x{pi.hex()}")
    print(f"{ver} chainId={int.from_bytes(pi[0:8],'big')} numBatches={int.from_bytes(pi[8:12],'big')}")

# V1: publicInputHash[i] = instances[i*32+31]
inst = open(os.path.join(V, "v0.9.8_pi.data"), "rb").read()
h = bytes(inst[i*32+31] for i in range(32))
print(f"v0.9.8 publicInputHash=0x{h.hex()}")
assert h.hex() == "31b430667bc9e8a8b7eda5e5c76f2250c64023f5f8e0689ac9f4e53f5362da66", "V1 hash mismatch vs spec assertion"
print("V1 hash matches the value asserted in ZkEvmVerifierV1.spec.ts")

# Scroll SWIRL — Lane C Local PoC Proving Lab (LAB.md)

Journal run: `scroll-swirl-2026-10-19` · Lane C · Status: **CHECKPOINTED 2026-10-19 ~03:05 EDT** (pool protection stop). All state on disk; cold-restartable via the scripts below.

## ⭐ HEADLINE RESULT (dynamic, local chain)

**The static HIGH (missing commitment binding in `OpenVmHalo2Verifier`) is DYNAMICALLY CONFIRMED at wrapper level.**
With well-formed lengths (`publicValues` = 32 B, `proofData` = 1760 B, all-zero payload), the wrapper accepts **arbitrary** commitments — tested `1/2`, `0/0`, and `MODULUS−1/MODULUS−1` — passing every wrapper-level check and failing **only** inside the Halo2 pairing verification with `ProofVerificationFailed()` (selector `0xd611c318`, gasUsed **329,647** for the 1/2 case, tx `0xc387e69e…b16d88` on the local chain). The wrapper's only commitment checks are `< BN254_SCALAR_MODULUS`. It binds the commitments to **nothing**. Full matrix in §5. This is the dynamic anchor for link L-0; per orders, no follow-on exploitation was self-funded.

## 1. Environment inventory

| | This VM (lab host) | Linode box (100.73.48.33) |
|---|---|---|
| CPU | 2 vCPU, AMD EPYC 9D25 | 6 vCPU |
| RAM | 7.7 GiB total (MemAvailable fluctuated 0.77 GiB → 6.3 GiB during the session) | 15 GiB total, 5.6 GiB avail |
| Disk | 100 G, 84 G free | 315 G, 218 G free |
| Load / tenants | hatch runtime only | **Busy**: solana-test-validator ~218% CPU, Monad solonet, Ark/Bark/Bitcoin docker stacks — **not disturbed** (read-only checks only) |
| Tooling at start | node v24.20.0, python3; **no** forge/anvil/cast/solc/cargo | no foundry either |

Installed (user-level, this VM): **Foundry v1.8.5** via foundryup → `~/.foundry/bin/{forge,anvil,cast}` (attestation-verified).

## 2. Placement decision

**Lab lives on THIS VM; nothing was placed on the Linode.**
- Verifier-contract work (anvil + forge + solc) is light and self-contained; the Linode is contended (load ~2.4, 218%-CPU validator, three other hunts' live stacks) and the brief forbids disturbing it.
- One resource incident: compiling `Halo2Verifier.sol` (2,130 lines) with the optimizer ON got solc **SIGKILL (OOM)** on this VM. With `optimizer = false` it compiles in <1 s. (Bytecode differs from the optimized shipped `verifier.bin`; semantics for the wrapper-binding tests are unaffected — noted as a caveat.)
- Prover work: **nowhere locally** — see §7.

## 3. Repos & pins used

| Repo | Commit | Where |
|---|---|---|
| scroll-tech/scroll | `bced8c26f55a8be9067eaeb0b6ad63dce3326101` (HEAD at clone; shallow, depth 50 — **flagged for reconciliation vs Lane A pins**) | `repos/scroll/` (cloned by Lane C before Lane A pins landed) |
| ↳ submodule scroll-contracts | `81f0db72ca5335e0dddfaa99cb415e3d1cee895f` | `…/repos/scroll/scroll-contracts/` |
| scroll-tech/zkvm-prover | `bf887150bb671af9b17dd53e92b7f2bbf01ec745` (guest v0.9.0; **matches Lane A pin**) | Lane A clone: `repos/zkvm-prover/`; Lane C's working copies came from the identical 2026-10-10 clone at `zkvm-prover/` — `verifier.sol` and `Halo2Verifier.sol` **diff-verified byte-identical** across both clones |
| scroll-contracts (PostFeynman control) | from 2026-10-10 clone under `scroll/scroll-contracts/` (Lane A pin for the scroll-swirl clone: `dfbd661`) | source copied into lab |
| OpenZeppelin contracts | tag `v4.9.3` (matches scroll-contracts `package.json`) | `lab/lib/openzeppelin-contracts/` |

No literal string "SWIRL" exists in either repo. On-chain, the SWIRL/OpenVM STARK proofs are wrapped into a Halo2 SNARK verified by `OpenVmHalo2Verifier`; STARK verification itself is off-chain (libzkp/coordinator). The pre-SWIRL finalization path is the halo2-PLONK `ZkEvmVerifierV1/V2/PostEuclid/PostFeynman` family behind `MultipleVersionRollupVerifier`.

Dev bundle commitments (reference, `zkvm-prover/crates/verifier/src/commitments/`, `[u32;8]`):
- `EXE_COMMIT = [230646913, 1550155984, 1593546189, 445636947, 993877920, 922842868, 418587344, 1363280000]`
- `VM_COMMIT = [1986621377, 858531750, 1460740544, 1489416258, 402142684, 1028207948, 2010771520, 956067622]`

## 4. Lab layout & cold restart

```
lab/
  foundry.toml            # plonk-verifier project, solc 0.8.24, cancun
  src/                    # verbatim copies: ZkEvmVerifierV1/V2/PostEuclid/PostFeynman,
                          #   MultipleVersionRollupVerifier, IZkEvmVerifier, IRollupVerifier
  vectors/                # plonk_verifier_*.bin (v0.9.8, v0.12.0-rc.2, v0.12.0-rc.3) + *_pi.data/*_proof.data
  scripts/start-anvil.sh  # anvil --host 127.0.0.1 --port 8545 --chain-id 31337 (loopback ONLY)
  scripts/stop-anvil.sh
  scripts/gen_vectors.py  # replicates hardhat spec genPublicInputs() byte-for-byte (validated vs spec assertions)
  scripts/smoke.sh        # plonk stack deploy + test matrix → smoke-results.txt
  openvm/foundry.toml     # solc 0.8.19, optimizer OFF (OOM, see §2)
  openvm/src/             # OpenVmHalo2Verifier.sol + Halo2Verifier.sol + interfaces/IOpenVmHalo2Verifier.sol (verbatim)
  openvm/smoke-openvm.sh  # OpenVM matrix → openvm/smoke-openvm-results.txt
  smoke-results.txt / openvm/smoke-openvm-results.txt   # raw recorded runs
```
Restart: `lab/scripts/start-anvil.sh` → `lab/scripts/smoke.sh` and/or `lab/openvm/smoke-openvm.sh` (each redeploys everything; addresses are nonce-deterministic on a fresh anvil). Anvil was left **running** at checkpoint (chain 31337, loopback only). **No mainnet/testnet RPC was ever touched; no forking; local source → local chain only.**

## 5. Smoke results — `OpenVmHalo2Verifier` (PRIME TARGET)

Deployed at `0x5FbDB2315678afecb367f032d93F642f64180aa3` on the local chain. Signature: `verify(bytes publicValues, bytes proofData, bytes32 appExeCommit, bytes32 appVmCommit)`; `PUBLIC_VALUES_LENGTH = 32`, `PROOF_DATA_LENGTH = (12+43)*32 = 1760`, modulus `0x30644e72…f0000001`.

| # | Input | Result |
|---|---|---|
| a1 | PV len 0, PD len 0, commits 1/2 | revert `InvalidPublicValuesLength(32, 0)` (sel. `0x604a5115`) |
| a2 | PV 32 B, PD 100 B, commits 1/2 | revert `InvalidProofDataLength(1760, 100)` (sel. `0x5b78f998`) |
| a3 | PV 31 B, PD 1760 B | revert `InvalidPublicValuesLength(32, 31)` |
| b1 | commits: exe = **MODULUS**, vm = 2 | revert `InvalidAppExeCommit(0x3064…0001)` (sel. `0xf6872d06`) |
| b2 | exe = 1, vm = **MODULUS** | revert `InvalidAppVmCommit(0x3064…0001)` (sel. `0xe1c033d0`) |
| b3 | exe = `0xff…ff` | revert `InvalidAppExeCommit(0xff…ff)` |
| **c1 ⭐** | **exe = 1, vm = 2**, PV = 32×0x00, PD = 1760×0x00 | **passes ALL wrapper checks** → revert `ProofVerificationFailed()` (`0xd611c318`) from the inner Halo2 self-call only. **gasUsed 329,647** (tx `0xc387e69e777f68ebb9c0a150398d2636ba12c1788a0a408e1f5bb09646b16d88`, status 0x0) |
| c2 | exe = 0, vm = 0, same zero payload | same: `ProofVerificationFailed()` only |
| c3 | exe = vm = MODULUS−1, same zero payload | same: `ProofVerificationFailed()` only |
| a4 | PD starts `0xdeadbeef` + zeros, commits 1/2 | revert **Panic 0x01** (the `assert(bytes4(proofData[0:4]) == 0)` gate — fires after length+commitment checks) |

Reading: the failure point for c1–c3 is *inside* the Halo2 verifier (the constructed proof splices the caller-supplied commitments in as public instances at offsets 0x180/0x1a0 and the pairing check rejects the garbage proof) — the wrapper itself contributes **no** expected-value binding. A forger still needs a Halo2 proof whose public instances match attacker-chosen commitments; what is proven here is exactly the wrapper-level gap the static audit flagged (H1/L-0 anchor): **commitment correctness rests entirely on the inner proof, and any caller/verifier-composition that trusts `verify()` success for a *specific* exe/vm is unprotected by this contract.**

Not done (pool stop): no real dev proof fixture exists in the checked-in tree (`releases/dev/` contains only `verifier/` — no proofs, no `openVmVk.json`), so test (3) "real proof with swapped commitments" is **blocked on fixture availability**, not attempted. The S3 `releases/v0.9.0/bundle/verifier.sol` production twin is **not in-repo** — dev-vs-production diff **not done**.

## 6. Smoke results — legacy PLONK stack (original brief)

Deployed on an earlier anvil instance (fresh-anvil addresses in `smoke-results.txt`: raw plonk rc.3 `0x5FbD…80aa3`, V2 `0x9fE4…a6e0`, V1 `0xCf7E…0Fc9`, MVRV `0x5FC8…5707`):
- ✅ `ZkEvmVerifierV2` + repo vector v0.12.0-rc.3 (proof 2,144 B; publicInput 172 B built by `gen_vectors.py` from `*_pi.data`; digest `0x1311a3da…096552`): **verify succeeds** — `cast call` exit 0; `cast send` status 0x1, **gasUsed 375,335**.
- ✅ Same vector through `MultipleVersionRollupVerifier.verifyBundleProof(3, 0, …)`: **succeeds**.
- ✅ `ZkEvmVerifierV1` + v0.9.8 vector (publicInputHash `0x31b43066…362da66`, matches the spec's asserted value): `cast call` **succeeds**.
- ⚠️ **INCOMPLETE (service restart + pool stop):** the V1 gas measurement and all garbage-input cases for the PLONK stack (reversed publicInput, random/truncated/empty proof) were mid-run when interrupted and are **not recorded**. `scripts/smoke.sh` re-runs the whole matrix in one go on restart.

Differential control — `ZkEvmVerifierPostFeynman` (design (a)): deployed locally at `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` with constructor `(plonkVerifier, verifierDigest1, verifierDigest2, protocolVersion)`; its digests are **immutable, baked into bytecode** (read back on-chain: digest1 `0x1311a3da…096552`, digest2 `0x0`, set at construction and unchangeable), and `verify(bundleProof, publicInput)` takes **no caller-supplied commitment/digest parameters at all**. Contrast: `OpenVmHalo2Verifier.verify()` takes both commitments as **free calldata** with range-check-only validation. (PostEuclid in `lab/src/` is the same immutable-digest pattern, minus `protocolVersion`.)

## 7. Prover feasibility — HONEST verdict: NOT feasible locally; NOT attempted (per brief + pool rule)

From the repos' own docs (zkvm-prover `AGENTS.md` / README, scroll `zkvm-prover/README.md`):
- Toolchain: Rust **nightly-2025-11-20** + `riscv32im` target; guests must be force-rebuilt (`build-guest --mode force`) in chunk→batch→bundle order.
- Requires KZG SRS files in `~/.openvm/params/`: **`kzg_bn254_24.srs` alone is 2 GB** (plus 22/23 for the SNARK step).
- Bundle SNARK on CPU: "tens of minutes" per repo docs; GPU path wants a **24 GB-class GPU** (e2e bundle peaks ~23.5 GiB VRAM). Neither machine has a GPU; this VM has 2 vCPU / ≤7.7 GiB RAM and already OOM-killed one solc run; the Linode (6 vCPU / 15 GiB) is loaded with other hunts.
- Verdict: **the full STARK prover/aggregator does not run in this lab.** What runs locally is the complete **on-chain verification half** (both verifier generations, real vectors) — which is where the chain-first strategy aims (mis-verification), so the lab is fit for purpose. Depth waits for the Oct 21 reset / a bigger box.

## 8. Capability statement

- ✅ Local anvil chain; both verifier generations deployed from pinned source and exercised with crafted inputs; real repo proof vectors verify (PLONK V2/V1).
- ✅ Wrapper-level commitment-binding gap in `OpenVmHalo2Verifier` **dynamically demonstrated** (§5 c1–c3).
- ❌ No proof *generation* (no prover, no new valid OpenVM/PLONK proofs can be minted here — vectors are repo fixtures only).
- ❌ No ScrollChain/bridge end-to-end finalization exercised yet (contracts identified; deployment is scripted in scroll-contracts but not run — next chunk if funded).
- ❌ Dev-vs-production verifier diff and swapped-commitment-on-real-proof test: blocked on assets not in-repo (S3 twin / proof fixtures).

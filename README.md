# The OpenVM v2.0 reference verifier does not bind caller-supplied program commitments

## Scope banner — read first

> **Scroll's production deployment is NOT affected by this issue, and no funds
> are at risk.** Scroll's production finalization path uses a different
> verifier (`ZkEvmVerifierPostFeynman`) whose expected digests are baked into
> the contract as construction immutables; this was verified directly on
> Ethereum L1 (details in §2). What follows is a design gap in the
> **development/reference verifier** `OpenVmHalo2Verifier` shipped with OpenVM
> v2.0 — and in the interface pattern it sets for anyone who adopts it.

## TL;DR

`OpenVmHalo2Verifier.verify(publicValues, proofData, appExeCommit, appVmCommit)`
— the wrapper verifier shipped in `scroll-tech/zkvm-prover` @
`bf887150bb671af9b17dd53e92b7f2bbf01ec745` (`releases/dev/verifier/verifier.sol`)
— accepts the application executable commitment and the VM-configuration
commitment as free calldata. The only validation it performs on them is a
range check: each must be less than the BN254 scalar-field modulus. It never
compares them to any expected value — there are no stored digests, no
immutables, and no derivation from the proof inside the wrapper. The
commitments are spliced into the constructed proof as public instances and
handed to the inner Halo2 verifier, so the wrapper itself contributes **no
identity binding**: a canonical but arbitrary commitment is accepted exactly
as readily as the correct one.

This was confirmed dynamically on a local chain: commitment pairs `1/2`,
`0/0`, and `MODULUS−1/MODULUS−1` all pass every wrapper check and fail only
inside the inner Halo2 pairing verification. Canonicality constrains the
*format* of the commitments, not their *identity*.

The finding was disclosed privately to the OpenVM security team on
2026-10-19. Their response, quoted in full in §8, is that this is the
intended design of the verifier and not a vulnerability. This writeup
publishes the technical record and the position taken here: a reference
implementation is the pattern consumers copy, and a verifier whose success
can be read as attesting to a *specific* program should bind that program's
commitments itself.

## 1. How this was found

This came out of a review of Scroll's OpenVM v2.0 ("SWIRL") proving-stack
integration — Scroll's wholesale swap of its proving stack to OpenVM v2.0
STARK proofs (WHIR commitments, LogUp-GKR), with the bundle STARK wrapped in
a Halo2 SNARK for L1 verification. The review traced the verification chain
link by link: which contract verifies what, and what each input to each
verifier is bound to. The production chain checked out (§2). The development
verifier shipped alongside it did not: its commitment inputs are bound to
nothing at the wrapper level.

## 2. What was checked in production (and is not affected)

On Ethereum L1, the verifier registered for the current protocol version
(10) in Scroll's `MultipleVersionRollupVerifier`
(`0x4CEA3E866e7c57fD75CB0CA3E9F5f1151D4Ead3F`) is
`0x7966FE0De13e3B81533470640Ac489223476B254`, a `ZkEvmVerifierPostFeynman`
deployed 2026-09-15 whose digests are construction immutables
(`verifierDigest1 = 0x006770fb0f71f20718b614c8c5d3fb39482f0527806e67b0ea00ab5508245655`).
Callers of the production path supply only the bundle proof and the public
input; there are no caller-supplied commitments to bind or to abuse. The
production adapter design is the correct pattern — and, as §6 notes, it is
also the contrast that makes the reference verifier's gap visible.

## 3. The finding

Affected component: `OpenVmHalo2Verifier`, in
`scroll-tech/zkvm-prover` @ `bf887150bb671af9b17dd53e92b7f2bbf01ec745`,
`releases/dev/verifier/verifier.sol` (with `Halo2Verifier.sol` and
`interfaces/IOpenVmHalo2Verifier.sol` in the same directory). The contract
describes itself as "a thin wrapper around the Halo2 verifier outputted by
`snark-verifier`, exposing a more user-friendly interface," for OpenVM
version 2.0.

Its `verify()` performs exactly these checks (line references are to the
shipped file):

- `publicValues.length == 32` and `proofData.length == 1760` (lines 74–77);
- `uint256(appExeCommit) < BN254_SCALAR_MODULUS`, else
  `InvalidAppExeCommit` (line 78);
- `uint256(appVmCommit) < BN254_SCALAR_MODULUS`, else
  `InvalidAppVmCommit` (line 79);
- `assert(bytes4(proofData[0:4]) == bytes4(0x00000000))` (line 94) — the
  selector-collision guard discussed in §5.

Then `_constructProof` splices the two caller-supplied commitments into the
constructed proof at offsets `0x180` (exe) and `0x1a0` (vm) and self-calls
the Halo2 verifier fallback (lines 151–190). At no point is either
commitment compared against an expected value. There is nothing in the
contract to compare against: no immutable, no storage slot, no constant
holds the intended program's commitments.

Consequence: whatever protection exists rests entirely on the inner proof.
A caller — or a composing contract — that treats a successful `verify()` as
attesting to a *specific* exe/vm receives no such assurance from this
contract. The wrapper's own interface invites exactly that reading: its
parameters are documented as "The commitment to the OpenVM application
executable whose execution is being verified" and "The commitment to the VM
configuration."

## 4. Dynamic evidence (local chain only)

The shipped `verifier.sol` was compiled with `Halo2Verifier.sol` and deployed
to a local anvil chain (Foundry v1.8.5, chain-id 31337, loopback only; no
mainnet or public testnet was touched at any point). Deployed address:
`0x5FbDB2315678afecb367f032d93F642f64180aa3`. `verify()` was called with
well-formed lengths (`publicValues` = 32 zero bytes, `proofData` = 1760 zero
bytes) and the following commitment pairs:

| appExeCommit / appVmCommit | Result |
|---|---|
| `1` / `2` | Passed **all** wrapper checks; reverted only inside the inner Halo2 verification with `ProofVerificationFailed()` (selector `0xd611c318`); 329,647 gas; local tx `0xc387e69e777f68ebb9c0a150398d2636ba12c1788a0a408e1f5bb09646b16d88` |
| `0` / `0` | Same: `ProofVerificationFailed()` only |
| `MODULUS−1` / `MODULUS−1` | Same: `ProofVerificationFailed()` only |

Controls behaved exactly as coded, confirming the checks that *do* exist
are the only ones present:

- commitment = `MODULUS` → typed revert `InvalidAppExeCommit` /
  `InvalidAppVmCommit` (selectors `0xf6872d06` / `0xe1c033d0`);
  `0xff…ff` likewise reverts `InvalidAppExeCommit`;
- wrong `publicValues`/`proofData` lengths → typed length reverts
  (`InvalidPublicValuesLength` `0x604a5115`, `InvalidProofDataLength`
  `0x5b78f998`);
- `proofData` beginning `0xdeadbeef` → Panic 0x01 at the
  `assert(bytes4(proofData[0:4]) == 0)` gate, which fires only *after* the
  length and commitment checks pass.

**Honest limitation of the evidence.** The dev release tree contains no
real proof fixtures, so no "valid proof with swapped commitments" test was
run; the payloads above are well-formed-length zero bytes, and the inner
pairing check is what rejected them. What is demonstrated is precisely the
wrapper-level gap, and the claim is scoped to exactly that: the contract
performs no binding of its own. A forger still needs a Halo2 proof whose
public instances match the commitments supplied; the point is that the
*wrapper* — the component a consumer integrates and trusts — contributes
nothing to that requirement, despite presenting the commitments as its own
inputs.

## 5. Lineage

This appears to be the un-closed half of **GHSA-w82q-w67c-67wv**
(CVE-2026-62335, OpenVM v1.7.0 security release, 2026-06-26). That
advisory's fix added the modulus/canonicality rejection, and it is present
and working here (see the `MODULUS` controls in §4). But the fix constrained
the *format* of the commitments, not their *identity* — the flaw was
transformed rather than closed.

The second control in §4, the `assert` on the first four bytes of
`proofData`, is the fix for **GHSA-j29p-wr24-hp4f** (CVE-2026-62334). It is
present and fires in the tested order. Neither advisory addressed binding
the commitments to expected values.

## 6. The contrast: the production pattern binds; the reference pattern doesn't

`ZkEvmVerifierPostFeynman` — the legacy verifier family Scroll actually
deploys — takes **no** caller-supplied commitments: its digests are
constructor immutables baked into the bytecode, set at construction and
unchangeable. This was verified both on L1 (§2) and in the local lab, where
the contract was deployed as a differential control (digests read back
on-chain, immutable).

That is the binding the reference wrapper lacks, and it exists in the same
ecosystem, in the older code. A developer adopting the v2.0 reference
verifier as their starting point moves from a pattern where the verifier
knows which program it verifies to one where it cannot know.

## 7. Impact — honestly bounded

As shipped, this is a development verifier, and no production funds are at
risk from it today (§2 covers the one production deployment checked).

The risk is adoption-shaped. A dev/reference verifier is the implementation
consumers copy. Any production adapter that parses exe/vm commitments from
calldata into this wrapper inherits a verification-integrity gap: proofs
would be evaluated against attacker-chosen commitments rather than the
commitments of the intended program, and any downstream logic that trusts
`verify()` success as binding to a specific program is unprotected. Under
that adoption condition, the issue is High-shaped; as a standalone property
of the dev verifier, it is a design gap / hardening issue. No live exploit
and no production vulnerability is claimed.

## 8. Disclosure timeline

- **2026-10-19 (~03:29 EDT)** — Full private disclosure sent to
  security@openvm.dev, including the dynamic evidence above, the production
  statement in §2, suggested remediation (§9), and an offer of the complete
  local reproduction. The letter stated that the finding had not been
  disclosed to anyone else and would not be published without coordinating
  with the OpenVM team first, and that the timeline was flexible.
- **2026-10-19 (13:13 EDT)** — Response received from Yi Sun (OpenVM),
  quoted here in full:

  > Hi Jacob,
  >
  > Thank you for this report. This is the intended design of the verifier, and not a vulnerability.
  >
  > Best,
  >
  > Yi

- **Publication** — This writeup is published following that exchange. The
  disagreement is narrow and is stated here without embellishment: the
  vendor's position is that unbound caller-supplied commitments are the
  intended design of this verifier. The position taken in this writeup is
  that, intended or not, a reference implementation sets the pattern
  consumers copy — and this pattern accepts any canonical commitment as
  readily as the correct one, which is a property integrators should know
  about before they build on it. Readers can weigh both positions against
  the evidence in §4, which is fully reproducible from §10.

## 9. Suggested remediation

Bind the commitments in the wrapper, e.g.:

- store the expected exe/vm commitments as construction immutables (the
  `ZkEvmVerifierPostFeynman` pattern) and compare caller-supplied values
  against them, or remove them from the caller-facing interface entirely; or
- derive the commitments from the proof/public values inside the wrapper and
  verify consistency, rather than accepting them as independent inputs.

Canonicality (range) checking alone is insufficient, because it constrains
format, not identity.

If the design is retained as-is, a prominent notice in the reference
verifier — stating that the commitments are **not** bound by the contract
and that integrators must bind them externally — would close most of the
adoption risk at no functional cost.

## 10. Reproduction

All work was done on a local chain; no mainnet or public testnet was
touched. The lab record is `LAB.md` at the root of this repository; the
artifacts below are named by their paths in this repository (`lab/`).
The binary test vectors under `lab/vectors/` are the public artifacts
shipped with the pinned zkvm-prover releases and are regenerable with
`lab/scripts/gen_vectors.py`.

**Target sources (verbatim copies, diff-verified byte-identical to the
pinned repo):**

- `lab/openvm/src/OpenVmHalo2Verifier.sol` — copy of
  `releases/dev/verifier/verifier.sol` from scroll-tech/zkvm-prover @
  `bf887150bb671af9b17dd53e92b7f2bbf01ec745`
- `lab/openvm/src/Halo2Verifier.sol`
- `lab/openvm/src/interfaces/IOpenVmHalo2Verifier.sol`
- `lab/openvm/foundry.toml` — solc 0.8.19, optimizer **off** (the optimizer
  build OOM-killed solc on the lab host; the resulting bytecode therefore
  differs from the shipped optimized `verifier.bin`. Wrapper semantics —
  the subject of every test here — are unaffected.)

**Setup:**

- `lab/scripts/start-anvil.sh` — starts anvil on `127.0.0.1:8545`,
  chain-id 31337, loopback only
- `lab/scripts/stop-anvil.sh`
- Toolchain: Foundry v1.8.5 (`forge` / `anvil` / `cast`)

**Test matrix and recorded output:**

- `lab/openvm/smoke-openvm.sh` — deploys `OpenVmHalo2Verifier` and runs the
  full input matrix of §4 (length controls, modulus controls, the
  `0xdeadbeef` assert control, and the three arbitrary-commitment cases)
- `lab/openvm/smoke-openvm-results.txt` — the recorded run output,
  including the deployed address `0x5FbDB2315678afecb367f032d93F642f64180aa3`
  and every revert quoted in §4

**Differential control (production pattern):**

- `lab/src/ZkEvmVerifierPostFeynman.sol` — verbatim copy deployed locally
  as the immutable-digest control (alongside `ZkEvmVerifierV1.sol`,
  `ZkEvmVerifierV2.sol`, `ZkEvmVerifierPostEuclid.sol`,
  `MultipleVersionRollupVerifier.sol` in the same directory)
- `lab/scripts/smoke.sh` → `lab/smoke-results.txt` — recorded control runs
  (real repo proof vectors verifying through the PLONK stack)
- `lab/scripts/gen_vectors.py`, `lab/vectors/` — public-input generation
  and the repo proof vectors used for the control runs
- `lab/anvil.log` — local chain log for the session

**Not reproduced here, by design:** no proof generation was attempted (the
full OpenVM prover does not run in this lab — see the honest capability
statement in `LAB.md` §7), and no valid-proof-with-swapped-commitments test
exists, for the fixture reason stated in §4.

---

*Jacob F Cudney (aragondragon) — independent security researcher.*
*Finding L-0, Scroll SWIRL review, 2026-10-19.*

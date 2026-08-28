# RFC: Gooo Workgraph External Consumer Contract v1

Status: Implemented for released-CLI semantic readiness

## Decision

Gooo Workgraph is a separate public project. It must not import internal Go
packages, branches, or go.mod replacements from meta-ontology-go. It may
consume only a released gooo executable and explicitly versioned JSON wire
schemas.

This boundary makes external utility falsifiable. A missing pinned release is
UNKNOWN; a development checkout is not silently accepted as a release.

## Fixed seven-gate observer denominator

| Gate | Stage / step | Proof choice |
|---|---|---|
| SOURCE_AUTHORITY | SOURCE / DECLARE_AUTHORITY | FOUNDATION |
| SYNTAX_ACCEPTED | COMPILER / CHECK_SOURCE | FOUNDATION |
| META_BOUND | META / BIND_ACTIVITIES | COHERENCE |
| DETERMINISTIC_REPLAY | GENERATOR / REPLAY_GENERATION | REGRESSION |
| ARTIFACT_GENERATED | GENERATOR / EMIT_ARTIFACT | COHERENCE |
| RESOURCE_OBSERVED | RUNTIME / SAMPLE_RESOURCES | REGRESSION |
| USER_ROUNDTRIP | USER / CLOSE_CLAIM | COHERENCE |

Gate order and denominator 7 are part of gooo/workgraph-project/v1.
Adding or removing a gate requires v2.

## Released-CLI readiness denominator

The separate readiness denominator v2 has exactly 12 tasks. It pins
v0.1.0-dev, its annotated commit target, all 8 GitHub asset digests, and the
public gooo-version/v1 and gooo/diagnostics/v1 schemas.

The first evaluation intentionally has 10/12 CLOSED and two explicit unknowns
at EVALUATOR / OBSERVE_INITIAL_REPORT. A second evaluation must consume the
first report digest and exact claim coordinates before INITIAL_REPORT_OBSERVED
and UNKNOWN_TRACE_PRESERVED can close. The final state is 12/12 CLOSED,
0 UNKNOWN, 0 REFUTED.

The v3 denominator preserves those twelve task identities except for replacing
the ambiguous syntax-only check task with
`CORE_SEMANTIC_RECEIPTS_OBSERVED / ObserveReleasedSemanticReceipts`. The
replacement does not increase the denominator. It requires four separate
released CLI receipts: version, syntax check, explicit semantic check, and
semantic graph.

Default `check --json` proves syntax only. `check --semantic --json` proves
that semantic lowering completed and exposes a semantic hash. `graph dump`
provides the source digest, semantic IR digest, graph hash, and canonical
activity nodes. No one receipt substitutes for another.

The graph activity set must equal the twelve denominator activities exactly.
This replaces source-text matching. Source spans and cross-format semantic
equivalence are not claimed by this contract.

The evaluator proves three counterexamples: a private repository refutes
PUBLIC_REPOSITORY, a one-byte release digest contradiction refutes
CORE_BINARY_DIGEST_LOCKED, and a missing released graph activity refutes
CORE_SEMANTIC_RECEIPTS_OBSERVED at its exact compiler stage and step.

## Claim and incomplete knowledge

Allowed cell states are CLOSED, UNKNOWN, and REFUTED. Every UNKNOWN retains
stage, step, reason, and next_operation. A later report retains the predecessor
artifact digest, predecessor report digest, and previous claim coordinates.
Natural-language confidence cannot close a cell.

FOUNDATION identifies authority, COHERENCE checks structural relationships,
and REGRESSION requires a second observation. These are proof choices, not
scores.

## Read-only effect boundary

The observer reads source, contracts, public release metadata, and two release
assets. It writes generated evidence only under the runner temporary
directory. repository_writes is zero only when exact pre/post input-repository
snapshots match; without both snapshots it remains unknown.

Network waiting, checkout, artifact download, and artifact upload are outside
the measured repository-write boundary.

## Replay and refutation

The final evaluation executes twice against the same predecessor and compares
raw report bytes. Absolute temporary paths and timestamps are excluded.

A release digest mutation produces FAIL_CLOSED / EXACT with reason
CORE_RELEASE_ASSET_SET_MISMATCH at RELEASE / LOCK_CORE_RELEASE_ASSET_SET.

## Human indicators

The readiness report exposes exact numerators and denominators for 12 tasks,
4 released-CLI receipts, 2 predecessor bindings, 12 Gooo activity bindings,
unknown and refuted tasks, and repository writes. It reports separate
FOUNDATION, COHERENCE, and REGRESSION closure totals.

## Release slices

1. v0.1.0 closes released-CLI readiness: pinned release observation,
   digest-locked execution, source/head binding, zero-write snapshots, and a
   preserved unknown-to-closed predecessor transition.
2. v0.2.0 executes two external-temp generations, compares raw bytes, records
   one resource sample, and emits the seven-gate Workgraph report.
3. v1.0.0 adds predecessor-identity and unsupported-schema counterexamples
   plus a released-core compatibility matrix.

## Compatibility

Core and Workgraph releases are independent. Workgraph locks an exact core tag,
annotated target commit, and asset set. Additive JSON fields are allowed within
a schema major, while new decision enum values lower resolution to UNKNOWN.
Gate or state semantic changes require a new schema major. A Workgraph
compatibility failure never blocks an unrelated core merge.

The design borrows boundary principles from Cargo machine output, Bazel Build
Event Protocol, Nix input locks, in-toto attestations, and SLSA external
parameters. It does not claim compatibility or compliance with those systems.

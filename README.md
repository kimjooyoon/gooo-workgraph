# Gooo Workgraph

Gooo Workgraph is an independent, read-only evidence consumer for Gooo
projects. It communicates with Gooo through released CLI processes and
versioned JSON only. It never imports the core repository's internal Go
packages.

## Current boundary

The immutable v1 readiness report established a truthful bootstrap state:
4/12 CLOSED, 8 UNKNOWN, and no asserted repository-write value before a
released CLI existed.

The v2 readiness contract consumes the public v0.1.0-dev prerelease:

- it locks the annotated tag target and all 8 release asset digests;
- it downloads only the Linux CLI archive and SHA256SUMS;
- it executes released version and check JSON commands;
- it binds the checked source to the exact Workgraph commit;
- it compares pre/post repository snapshots;
- it first emits 10/12 CLOSED and 2 UNKNOWN, then consumes that predecessor
  and emits 12/12 CLOSED, 0 UNKNOWN, 0 REFUTED;
- it keeps all generated evidence outside the input repository.

The v3 contract preserves the same twelve-task denominator while increasing
the compiler observation resolution:

- released receipts are counted separately as version, syntax check, explicit
  semantic check, and semantic graph (`4/4`);
- default `check --json` remains syntax-only and is never promoted into
  semantic evidence;
- the released graph must contain exactly the twelve activities declared by
  the denominator and must carry the checked source digest;
- meta binding is computed from graph nodes rather than source-text matching;
- a missing graph activity is REFUTED at
  `COMPILER / OBSERVE_RELEASED_SEMANTIC_RECEIPTS`.

A contradictory release digest or non-public repository is REFUTED, never
silently lowered into success.

See the external consumer RFC in docs/rfcs/workgraph-external-consumer-v1.md.

## Ownership boundary

- meta-ontology-go owns the released gooo executable and its wire schemas.
- This repository owns Workgraph contracts, release locks, evaluation,
  fixtures, and reports.
- Either project can release without merging or importing the other project.

## Workspace inventory vertical slice

The additive workspace inventory experiment turns one local project tree into
a deterministic, read-only report. It exposes nested directory and regular
file totals, per-file language and physical line counts, aggregate Go and Gooo
line counts, and an explicit root README policy. A root README is never a
readiness prerequisite.

The inventory is implemented as a Go 1.27 command, while its twelve acceptance
cells are declared by Gooo activities in
`examples/workspace-inventory/main.gooo`. CI binds those activities through
the released semantic graph before accepting any metric. Missing roots remain
typed UNKNOWN, invalid roots are REFUTED, and observation writes remain zero.

## Transformation effect adoption

Workgraph independently consumes the released Gooo evidence-generator
transformation-effect artifact. It verifies the annotated release identity,
outer asset digests, all five inner manifests, byte-identical normal replay,
the exact `11 CLOSED / 1 UNKNOWN -> 12 CLOSED / 0 UNKNOWN` fixture pair, and
the producer's UNKNOWN and REFUTED cases. It does not trust the producer's
top-level decision as its own authority.

The adoption closes one independent public consumer path. It does not claim an
external user outcome or language-wide generalization, and it never edits the
producer, Workgraph, or an input project. See
[the adoption RFC](docs/rfcs/transformation-effect-adoption-v1.md).

## Released test receipt reuse

Workgraph also independently consumes the public
`gooo-evidence-generator v0.5.0-dev` test-receipt release. The workflow pins
the annotated tag object and target commit, verifies both release assets and
their checksum, and inspects all 44 extracted files. It reads exactly one
producer input file through the immutable contents API at the pinned commit;
it never checks out the producer repository or reruns its test.

The Workgraph-owned `examples/test-receipt-reuse/main.gooo` declares exactly
12 activities and is bound one-for-one to the released syntax, semantic,
graph, and activity-resolution receipts. The consumer independently checks the
released Gooo tag/commit/asset digest and the baseline `PASS`, result digest,
semantic hash, and test scope.

CI preserves the normal `12 CLOSED / 0 UNKNOWN / 0 REFUTED` adoption and
exercises missing release/receipt, stale scope/blob, result contradiction,
REFUTED-over-UNKNOWN, authority escalation, and unrecognized `FIXED_POINT`
cases. Every case retains a 12-cell denominator. Test-time savings and
external utility remain UNKNOWN; this evidence closes exactly one independent
released receipt consumer.

See [the test receipt reuse RFC](docs/rfcs/test-receipt-reuse-v1.md).

## Actual receipt and already-tested selective CI

The selective-CI workflow binds a real released-Gooo fixture execution to an
explicit already-tested boundary. `REUSE` is CLOSED only when immutable input,
toolchain, and scenario digests all match the actual execution receipt, the
prior released receipt and result are independently verified, and authority is
clean. Missing, stale, changed, unknown, contradictory, or digest-laundered
evidence selects `RERUN_REQUIRED` and remains UNKNOWN or REFUTED; REFUTED takes
priority over UNKNOWN.

The fixed 12-cell denominator is bound one-for-one to Gooo activities for
`PlannedTest`, `ExecutedTest`, `ReusedPriorReceipt`, `InvalidatedReceipt`,
`RequiredWork`, and `UnknownCausalFrontier`, plus the digest, IR, authority,
and report links. CI exercises normal, missing-receipt, stale,
changed-input, digest-laundering, mixed, authority-escalation, and
unknown-decision fixtures without lowering the denominator.

Reports expose `tests_planned`, `tests_executed`, `tests_reused`,
`tests_invalidated`, and `tests_required_to_execute`, together with fixture
`test_wall_ms` and `test_peak_rss_kib`. `saved_test_ms` remains UNKNOWN without
an exact before/after timing pair. The report also records
`repository_writes=0`, `local_test_executions=0`, and
`cross_project_required_gates=0` for the clean path, and retains the six-field
UNKNOWN causal frontier.

The report is linked to a deterministic manifest and human dossier. CI
publishes root-README-excluded regular-file, descendant-directory,
physical-line, Go, and Gooo inventory, artifact file count, and Go 1.27 in
both human-readable and artifact evidence. See
[the selective-CI RFC](docs/rfcs/selective-ci-work-selection-v1.md).

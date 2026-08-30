# RFC: Workgraph actual receipt and already-tested selective-CI boundary v1

Status: Implemented actual execution receipt and already-tested boundary

## Decision

Workgraph turns one real released-Gooo fixture execution and one released
exact test receipt into a CI work-selection decision. `REUSE` is CLOSED only
when the immutable input digest, toolchain digest, scenario digest, complete
scope, result digest, trusted semantic hash, and clean authority all match.
Missing, stale, changed, unknown, contradictory, or laundered evidence is
fail-closed as `RERUN_REQUIRED`; a known REFUTED result has priority over
UNKNOWN evidence.

This is a new consumer boundary on top of the released receipt. It does not
duplicate the full receipt-corpus adoption in the existing #7 workflow and it
does not run the producer or consumer test while making the selection.

## Fixed denominator and meta binding

The contract has exactly 12 cells and the Gooo meta source has exactly 12
activities. The source explicitly declares `PlannedTest`, `ExecutedTest`,
`ReusedPriorReceipt`, `InvalidatedReceipt`, `RequiredWork`, and
`UnknownCausalFrontier`. CI obtains generated semantic IR and the graph from
the released Gooo CLI and checks the activity name set, source digest,
semantic digest, and resolution entries one-for-one against the denominator.
The report emits an exact cell-to-activity-to-IR pointer for every metric.

The denominator is balanced as `FOUNDATION 4 / COHERENCE 4 / REGRESSION 4` and
`DRIVER 4 / OUTCOME 4 / GUARDRAIL 4`.

## Selection key

Each planned test has one serialized scope containing:

- the input file path and SHA-256;
- the released toolchain repository, tag, target commit, binary SHA-256, and platform;
- the exact command vector.

Reuse requires byte-for-byte equality of the current scope and receipt scope,
an explicit `PASS`, a successful diagnostics result, a result file digest that
matches both the receipt and the release lock, and a semantic hash that matches
the trusted result. A syntactically valid or digest-shaped semantic value is
not sufficient.

## Required cases

| Case | Selection | Workgraph result |
|---|---|---|
| normal | `REUSE` | 12 CLOSED / 0 UNKNOWN / 0 REFUTED |
| missing-receipt | `RERUN_REQUIRED` | UNKNOWN; six UNKNOWN fields preserved |
| stale | `RERUN_REQUIRED` | REFUTED; stale scenario digest |
| changed-input | `RERUN_REQUIRED` | REFUTED; immutable input digest changed |
| digest-laundering | `RERUN_REQUIRED` | REFUTED; trusted semantic identity disagrees |
| mixed | `RERUN_REQUIRED` | REFUTED takes priority over UNKNOWN |
| authority-escalation | `RERUN_REQUIRED` | REFUTED; cross-project gate escalated |
| unknown-decision | `RERUN_REQUIRED` | UNKNOWN; decision is not promoted |

All UNKNOWN and REFUTED cells retain `stage`, `step`, `reason`,
`unknown_class`, `next_operation`, and `blocked_by`. A REFUTED predecessor is
resolved before an UNKNOWN predecessor and controls the top-level claim.

## Metrics and authority

The report exposes the five boundary counts as either an integer or the
literal `UNKNOWN`: `tests_planned`, `tests_executed`, `tests_reused`,
`tests_invalidated`, and `tests_required_to_execute`, while retaining producer
and consumer execution observations. The normal fixture is
`1 / 1 / 1 / 0 / 0` in that order. It also records fixture `test_wall_ms` and
`test_peak_rss_kib`; `saved_test_ms` remains `UNKNOWN` unless an exact
before/after timing pair under identical conditions exists.

The evaluator writes only to an empty caller-owned temporary directory. CI
asserts `repository_writes=0`, `local_test_executions=0`, and
`cross_project_required_gates=0` for the clean path; authority-escalation is
retained as a REFUTED counterexample. The changed-input and stale cases verify
that work is required without silently reusing the prior receipt.

The report links to a deterministic manifest and human dossier. Both preserve
fixture and evaluator wall/RSS observations, the six-field UNKNOWN causal
frontier, root-README-excluded regular files, descendant directories,
physical lines, Go files/lines, Gooo files/lines, artifact file count, and Go
1.27. These observations are not quality scores or improvement claims.

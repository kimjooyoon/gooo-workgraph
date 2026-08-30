# RFC: Workgraph exact receipt selective-CI work selection v1

Status: Implemented independent selective-CI consumer

## Decision

Workgraph turns one released exact Gooo test receipt into a CI work-selection
decision. An exact match selects `REUSE`; a changed input, toolchain, command,
or scope selects `RERUN_REQUIRED`. A missing receipt is `UNKNOWN` evidence and
the safe work action is still `RERUN_REQUIRED`. The decision is deterministic:
it compares the complete serialized test scope and independently verifies the
result digest and trusted semantic hash before selecting reuse.

This is a new consumer boundary on top of the released receipt. It does not
duplicate the full receipt-corpus adoption in the existing #7 workflow and it
does not run the producer or consumer test while making the selection.

## Fixed denominator and meta binding

The contract has exactly 12 cells and the Gooo meta source has exactly 12
activities. CI obtains the graph from the released Gooo CLI and checks the
activity name set and resolution entries one-for-one against the denominator.
No selection metric is accepted without its corresponding activity.

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
| exact-match-reuse | `REUSE` | 12 CLOSED / 0 UNKNOWN / 0 REFUTED |
| changed-input-rerun | `RERUN_REQUIRED` | REFUTED; rerun required |
| missing-receipt | `RERUN_REQUIRED` | UNKNOWN; six UNKNOWN fields preserved |
| digest-valid-semantic-laundering | `RERUN_REQUIRED` | REFUTED |
| mixed | `RERUN_REQUIRED` | REFUTED takes priority over UNKNOWN |
| authority-escalation | `RERUN_REQUIRED` | REFUTED |

All UNKNOWN and REFUTED cells retain `stage`, `step`, `reason`,
`unknown_class`, `next_operation`, and `blocked_by`. A REFUTED predecessor is
resolved before an UNKNOWN predecessor and controls the top-level claim.

## Metrics and authority

The report exposes these six metrics as either an integer or the literal
`UNKNOWN`: `tests_planned`, `tests_reused`, `tests_required_to_execute`,
`producer_test_executions_observed`, `consumer_test_executions`, and
`saved_test_ms`. The normal fixture is `1 / 1 / 0 / 1 / 0 / UNKNOWN` in that
order. A missing receipt does not become a false zero for observed producer
executions. No time improvement is claimed: `saved_test_ms` remains `UNKNOWN`
unless an exact before/after timing pair under identical conditions exists.

The evaluator writes only to an empty caller-owned temporary directory. CI
asserts `repository_writes=0`, `local_test_executions=0`, and
`consumer_test_executions=0`. The changed-input and authority cases verify
that a rerun is required without performing that rerun in this consumer job.

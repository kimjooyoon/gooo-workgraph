# RFC: Workgraph released test receipt reuse v1

Status: Implemented independent public consumer

## Decision

Workgraph consumes the immutable `gooo-evidence-generator v0.5.0-dev` test
receipt release. The release lock records the producer repository, annotated
tag object, target commit, release ID, ZIP and checksum asset IDs, sizes, and
SHA-256 digests. The release contains exactly 44 files.

The consumer also verifies the released Gooo metadata used to produce the
receipt: `v0.2.0-dev`, its annotated tag and target commit, the Linux asset
digest, the baseline result digest, semantic hash, and explicit `PASS`
decision. This is an evidence boundary, not an import or a source dependency.

## Acquisition boundary

Actions checks the producer tag through the Git refs and annotated-tag APIs,
checks release and asset metadata, downloads only the two public release
assets, verifies `SHA256SUMS`, and extracts the ZIP into runner temporary
storage. It makes exactly one contents API request for
`examples/test-receipt-reuse/main.gooo` at the pinned producer commit and
recomputes its SHA-256. The Workgraph copy must have the same digest.

The workflow never checks out the producer repository, reads a sibling
checkout, copies or runs the producer evaluator, or reruns the producer test.
It consumes the released `version`, syntax, semantic, graph, resolution,
receipt, result, scope, and scenario evidence as data. Workgraph's own report
derives cell state from the raw observation and locked fields rather than
promoting a producer top-level decision.

## Fixed denominator

The Workgraph source declares exactly these 12 activities. The denominator
has 12 cells; `FOUNDATION`, `COHERENCE`, and `REGRESSION` each own four cells,
and `DRIVER`, `OUTCOME`, and `GUARDRAIL` each own four cells.

| # | Cell | Activity | Proof | Indicator |
|---:|---|---|---|---|
| 1 | RELEASED_GOOO_IDENTITY | ObserveReleasedTestCore | FOUNDATION | DRIVER |
| 2 | META_ACTIVITY_AUTHORITY | BindTestReceiptReuseActivities | FOUNDATION | GUARDRAIL |
| 3 | SUBJECT_SCOPE | PinTestSubjectScope | FOUNDATION | DRIVER |
| 4 | BASELINE_TEST_EXECUTION | RecordBaselineTestExecution | FOUNDATION | OUTCOME |
| 5 | TEST_RECEIPT | PublishExactTestReceipt | COHERENCE | DRIVER |
| 6 | RECEIPT_IDENTITY | VerifyTestReceiptIdentity | COHERENCE | DRIVER |
| 7 | SCOPE_EQUIVALENCE | CompareTestScopeDigests | COHERENCE | OUTCOME |
| 8 | REUSE_DECISION | AuthorizeExactTestReceiptReuse | COHERENCE | OUTCOME |
| 9 | EXECUTION_AVOIDANCE | RecordReceiptReuseWithoutConsumerTest | REGRESSION | GUARDRAIL |
| 10 | UNKNOWN_CAUSALITY | PreserveTestReceiptUnknown | REGRESSION | GUARDRAIL |
| 11 | REFUTATION_PRECEDENCE | RefuteStaleOrContradictoryReceipt | REGRESSION | GUARDRAIL |
| 12 | HUMAN_REPORT | PublishTestReceiptReuseReport | REGRESSION | OUTCOME |

No metric is accepted without a corresponding activity. The graph activity
set and released activity-resolution entries must equal this set exactly,
with one closed resolution for each activity.

## Cases and precedence

The normal fixture is observed twice and must produce identical Workgraph
report bytes. The release scenarios and CI counterexamples cover:

| Case | Expected shape or invariant |
|---|---|
| normal | 12 CLOSED / 0 UNKNOWN / 0 REFUTED; one exact scope pair and one receipt reuse |
| missing-release | Missing release is UNKNOWN and dependency cells remain UNKNOWN |
| missing-receipt | 5 CLOSED / 7 UNKNOWN / 0 REFUTED |
| stale-scope | 8 CLOSED / 0 UNKNOWN / 4 REFUTED |
| stale-blob | A source/blob contradiction is REFUTED |
| result-contradiction | A known result contradiction is REFUTED |
| refuted-over-unknown | 7 CLOSED / 1 UNKNOWN / 4 REFUTED; top-level claim is REFUTED |
| authority-escalation | 10 CLOSED / 0 UNKNOWN / 2 REFUTED |
| unrecognized-fixed-point | `FIXED_POINT` is REFUTED, never treated as PASS |

Known contradiction is evaluated before dependency UNKNOWN. Every UNKNOWN
cell carries `stage`, `step`, `reason`, `unknown_class`, `next_operation`, and
`blocked_by`. REFUTED cells keep the same structured fields with a null
`unknown_class`.

## Metrics and non-claims

The normal report exposes independent released receipt consumers `1/1`,
released receipt reuses `1/1`, producer test executions observed `1`, and
consumer producer-scope test executions `0`. It also reports the 44-file
corpus, 21 manifest entries, repository files and descendant directories,
physical lines, Go and Gooo file/line totals, evaluator wall time, peak RSS,
root README exclusion, and zero repository writes.

`saved_test_ms` is UNKNOWN because no equivalent independent timing pair is
observed. External utility and language-wide generalization are UNKNOWN. The
consumer closes exactly one independent public released-receipt path; it does
not claim language-wide utility or actual saved milliseconds.

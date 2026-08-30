# RFC: Workgraph transformation effect adoption v1

Status: Experimental independent public consumer

## Decision

Workgraph consumes the immutable `gooo-evidence-generator v0.4.0-dev`
transformation-effect release. It does not import generator source or trust the
producer's decision as Workgraph authority. It re-verifies the annotated tag,
asset IDs, sizes and SHA-256 digests, checksum file, 56-file corpus, five inner
manifests, normal replay, exact fixture integers, uncertainty tuple, refutation
precedence, and zero-write/build/test boundary.

This closes the producer's first independent public adoption requirement. It
does not close language-wide generalization or external user utility.

## Provenance boundary

in-toto models materials and products with link metadata, while SLSA provenance
separates build definition, resolved dependencies, builder identity, invocation,
and byproducts:

- https://in-toto.io/
- https://slsa.dev/spec/v1.0/provenance

Workgraph adopts immutable material identity and independently checked products.
It rejects the stronger interpretation that provenance alone proves semantic
improvement. The producer receipt is an input claim; Workgraph recomputes the
normal effect and adversarial behavior before issuing its own adoption claim.

## User path

1. Resolve the annotated producer tag to its exact commit.
2. Verify the released ZIP and checksum assets by ID, size, and digest.
3. Verify exactly 56 extracted files and 40 inner manifest entries.
4. Recompute the normal `11 CLOSED / 1 UNKNOWN -> 12 CLOSED / 0 UNKNOWN`
   pair and zero unrelated changes.
5. Recompute the missing-pattern UNKNOWN tuple and both REFUTED producer cases.
6. Preserve REFUTED over UNKNOWN when a semantic contradiction and missing
   uncertainty receipt coexist.
7. Publish a read-only Workgraph adoption report.

## Fixed denominator

The denominator is exactly 12 cells with exactly 12 released Gooo activities.
`FOUNDATION`, `COHERENCE`, and `REGRESSION` each own 4 cells. `DRIVER`,
`OUTCOME`, and `GUARDRAIL` each own 4 cells. No aggregate score exists.

| # | Cell | Activity | Proof | Indicator |
|---:|---|---|---|---|
| 1 | PRODUCER_RELEASE | ObserveReleasedTransformationProducer | FOUNDATION | DRIVER |
| 2 | CORE_RELEASE | ObserveReleasedTransformationCore | FOUNDATION | DRIVER |
| 3 | META_ACTIVITY_AUTHORITY | BindTransformationAdoptionActivities | FOUNDATION | GUARDRAIL |
| 4 | RELEASE_ARTIFACT | VerifyTransformationReleaseArtifact | FOUNDATION | DRIVER |
| 5 | NORMAL_MANIFEST_CORPUS | VerifyTransformationManifestCorpus | COHERENCE | DRIVER |
| 6 | EXACT_FIXTURE_EFFECT | AdoptExactFixtureEffect | COHERENCE | OUTCOME |
| 7 | UNKNOWN_CAUSALITY | PreserveAdoptedUnknownCausality | COHERENCE | OUTCOME |
| 8 | REFUTATION_PRECEDENCE | PreserveAdoptedRefutationPrecedence | COHERENCE | OUTCOME |
| 9 | AUTHORITY_BOUNDARY | PreserveAdoptedAuthorityBoundary | REGRESSION | GUARDRAIL |
| 10 | WORKGRAPH_DECISION | PublishWorkgraphTransformationDecision | REGRESSION | OUTCOME |
| 11 | ADOPTION_REPLAY | VerifyTransformationAdoptionReplay | REGRESSION | GUARDRAIL |
| 12 | CONTRADICTION_REJECTION | RejectTransformationEvidenceContradiction | REGRESSION | GUARDRAIL |

## Cases

CI evaluates exactly five semantic cases and executes the normal evaluator
twice for deterministic report replay.

| Case | Cells | Decision |
|---|---:|---|
| normal | 12 CLOSED / 0 UNKNOWN / 0 REFUTED | WORKGRAPH_TRANSFORMATION_EFFECT_ADOPTED |
| missing-unknown | 9 CLOSED / 3 UNKNOWN / 0 REFUTED | ADOPTION_EVIDENCE_UNKNOWN |
| laundered-effect | 9 CLOSED / 0 UNKNOWN / 3 REFUTED | FAIL_CLOSED |
| refuted-over-unknown | 8 CLOSED / 1 UNKNOWN / 3 REFUTED | FAIL_CLOSED |
| authority-escalation | 9 CLOSED / 0 UNKNOWN / 3 REFUTED | FAIL_CLOSED |

The laundered case changes both normal receipts and recomputes their manifests.
It proves that matching digests do not replace semantic comparison. The mixed
case combines that contradiction with a missing UNKNOWN receipt; its top-level
claim must remain REFUTED.

Every UNKNOWN cell preserves `stage`, `step`, `reason`, `unknown_class`,
`next_operation`, and `blocked_by`.

## Exact adoption and non-claims

The following become CLOSED only in the normal case:

- released producer assets: `2/2`;
- release artifact files: `56/56`;
- inner manifest entries: `40/40`;
- exact fixture pairs: `1/1`;
- producer cases: normal `1`, UNKNOWN `1`, REFUTED `2`;
- refutation precedence: `1/1`;
- Gooo meta activities: `12/12`;
- independent public consumers: `1/1`.

Language-wide generalization remains `0/1 UNKNOWN` until a second independent
domain consumes the result. External user utility remains `0/1 UNKNOWN` until
one user makes and records a real decision from the adoption dossier.

## Execution and authority

The adoption workflow uses Go `1.27.0` but executes no Go build, Go test,
product build, product test, local test, `go fix`, or source mutation. It reuses
five released producer conformance receipts but does not call them test
receipts. Test-time savings remain UNKNOWN.

Allowed writes are caller-owned runner temporary files and the Actions artifact.
Repository writes, sibling checkout reads, producer source checkout, automatic
promotion, remote mutation, and cross-project required gates are zero or
forbidden. The root README is excluded from readiness and inventory.

CI publishes exactly 68 files: the 56-file producer corpus, six Workgraph
reports, acquisition and runtime receipts, and four released Gooo receipts.

## Falsification

The adoption is REFUTED if any immutable identity differs, any manifest entry
cannot be recomputed, the normal integers or unrelated-cell digest differ,
UNKNOWN loses any causal field, REFUTED does not outrank UNKNOWN, authority
becomes nonzero, report replay differs, or any of the 12 Gooo activities is not
bound exactly once.

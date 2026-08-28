# RFC: Workgraph claim resolution adoption v1

Status: Experimental independent consumer

## Decision

Workgraph directly adopts the released Gooo
`gooo.primitive.claim-resolution-tuple.v1` operation. The workspace inventory
observer and its existing twelve-cell product denominator remain unchanged.
The new layer resolves claims already published in immutable Workgraph v0.2
evidence.

The three source scenarios are:

- observed workspace: CLOSED with `WORKSPACE_INVENTORY_OBSERVED`;
- missing workspace: UNKNOWN at `INPUT / OBSERVE_WORKSPACE_ROOT`, class
  `DIRECT_MISSING`, next operation `PROVIDE_WORKSPACE_ROOT`;
- non-directory root: REFUTED at `INPUT / VALIDATE_WORKSPACE_ROOT`, next
  operation `SELECT_WORKSPACE_DIRECTORY`.

The release contributes 18 claim fields and the core must produce 18 equal
fields. Nine exact inventory facts also remain bound: directory and file
counts, Go and Gooo file and line counts, and the three root README facts.

## Meta binding

Twelve fixed cells name twelve `claim.resolve:v1` activities in
`examples/claim-resolution-adoption/main.gooo`. Every core receipt must resolve
its selected activity exactly once and identify the candidate primitive.
FOUNDATION, COHERENCE, and REGRESSION each own 4/12 cells. DRIVER, OUTCOME, and
GUARDRAIL each own 4/12 cells.

## Resolution lowering

A missing core receipt becomes UNKNOWN at `CORE_RECEIPT /
OBSERVE_CLAIM_RESOLUTION_RECEIPT`. A missing released UNKNOWN scenario remains
UNKNOWN at `WORKGRAPH_RELEASE_EVIDENCE /
OBSERVE_RELEASED_WORKSPACE_UNKNOWN_CLAIM`. Both expose `DIRECT_MISSING` and an
explicit next operation. Changed claim fields or inventory facts are REFUTED.
Incomplete UNKNOWN tuples and unrecognized parent states must fail closed.

## Tool and authority boundary

The released product evidence records Go 1.27.0, three CI tests, one actual Go
module root, and zero `go fix` writes. This adoption layer runs no local tests
and no additional `go fix`; the existing product workflow continues to perform
Go conformance in CI. Build execution, task execution, source mutation, core
mutation, generator authority, and cross-project required gates are not
authorized.

## Human-readable evidence

CI reports all fixed denominators, repository files and descendant folders,
total and per-file Go and Gooo lines, claim-resolution RSS and wall time,
module-root and CI-test counts, and repository writes. Root README readiness is
excluded.

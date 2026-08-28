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

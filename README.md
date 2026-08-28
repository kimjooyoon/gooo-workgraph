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

A contradictory release digest or non-public repository is REFUTED, never
silently lowered into success.

See the external consumer RFC in docs/rfcs/workgraph-external-consumer-v1.md.

## Ownership boundary

- meta-ontology-go owns the released gooo executable and its wire schemas.
- This repository owns Workgraph contracts, release locks, evaluation,
  fixtures, and reports.
- Either project can release without merging or importing the other project.

# Gooo Workgraph

Gooo Workgraph is an independent, read-only evidence consumer for Gooo
projects. It communicates with Gooo through released CLI processes and
versioned JSON/NDJSON only. It never imports the core repository's internal Go
packages.

## Current boundary

The repository starts with a release-readiness observation rather than a fake
successful demo. Its fixed denominator has 12 tasks:

- 4 repository and contract prerequisites can close without a Gooo release.
- 8 runtime and evidence tasks remain `UNKNOWN` while no released Gooo CLI is
  available.
- `repository_writes` remains `null` until a pre/post repository observation
  exists. Missing evidence is never converted to zero.

The eventual read-only observer has a separate seven-gate denominator. Its
first useful state is `4/7 CLOSED`, `3 UNKNOWN`, `0 REFUTED`, with
`RUN_GOOO_GENERATE_REPLAY` as the next operation.

See [the external consumer RFC](docs/rfcs/workgraph-external-consumer-v1.md).

## Ownership boundary

- `meta-ontology-go` owns the released `gooo` executable and its wire schemas.
- This repository owns Workgraph contracts, evaluation, fixtures, and reports.
- Either project can release without merging or importing the other project.

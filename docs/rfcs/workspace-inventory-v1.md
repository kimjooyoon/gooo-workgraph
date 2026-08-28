# RFC: Gooo Workgraph Workspace Inventory v1

Status: Experimental; conformance is decided only by published CI evidence.

## Decision

Workgraph will close one small user-visible case: observe a local directory and
emit deterministic per-file and aggregate structure metrics without modifying
the observed repository. This is not a build system, task runner, dependency
resolver, or general project generator.

The implementation is a Go 1.27 command. Metric authority remains the Gooo
source in `examples/workspace-inventory/main.gooo`; the released Gooo semantic
graph must bind exactly all twelve denominator activities before the metrics
can close.

## Observable result

The v1 report contains:

- nested directory and regular file totals;
- one sorted entry per regular file with path, language, physical lines, and
  bytes;
- aggregate Go, Gooo, and other file and line totals;
- an explicit root README policy;
- a claim state and exact UNKNOWN or REFUTED coordinates.

A physical line is one newline-terminated sequence, plus one final sequence
when a non-empty file does not end in a newline. Empty files contain zero
physical lines. Extension matching is case-insensitive for `.go` and `.gooo`.

## Root README rule

A repository-root README may be present or absent. It is counted as a regular
file when present, but it is never required for readiness. The report always
exposes `root_readme_required=false` and `root_readme_excluded=true` so a
missing root README cannot be converted into an implicit failure.

## Claim resolution

- A directory that can be traversed produces `CLOSED`.
- A missing root produces `UNKNOWN` at
  `INPUT / OBSERVE_WORKSPACE_ROOT`, class `DIRECT_MISSING`, with next operation
  `PROVIDE_WORKSPACE_ROOT`.
- A regular file, symlink root, traversal contradiction, or undeclared
  symbolic-link boundary produces `REFUTED`; no fallback path is selected.

Every result is emitted on stdout. Observation mode creates no cache, lock,
manifest, or generated source in the input repository.

## Fixed denominator

The denominator contains exactly twelve cells. FOUNDATION, COHERENCE, and
REGRESSION each own 4/12 cells. DRIVER, OUTCOME, and GUARDRAIL each own 4/12
cells. A metric without its exact Gooo activity is REFUTED rather than merely
unreported.

The canonical fixture closes with these exact observations:

| Observation | Value |
|---|---:|
| Nested directories | 7 |
| Regular files | 5 |
| Go files / lines | 2 / 6 |
| Gooo files / lines | 2 / 8 |
| Other files / lines | 1 / 2 |
| Root README present / required | false / false |

Runtime wall time and peak RSS are reported as observations without an initial
performance target. A later threshold requires a new denominator version and
cannot retroactively redefine v1 success.

## Go 1.27 conformance

CI uses exactly Go 1.27.0. It runs `go mod tidy`, `go fix ./...`, `gofmt`,
`go vet`, and three Go test cases. The first three tools may propose source
changes in the ephemeral runner, but any resulting repository difference
fails conformance. Go 1.27's `go fix` modernizers are described in the official
[Go 1.27 release notes](https://go.dev/doc/go1.27).

## Independence and promotion

The workflow consumes only the immutable `meta-ontology-go v0.3.0-dev` release
asset locked by tag target, asset ID, size, and SHA-256. It does not import core
packages or depend on a core branch. Workgraph CI is not a required gate for
core or any other project.

An immutable Workgraph release is eligible only after:

- 12/12 meta-bound cells close;
- CLOSED, UNKNOWN, and REFUTED scenarios are all observed;
- deterministic replay is byte-identical;
- repository writes are exactly zero;
- memory and wall-time observations are present;
- local test executions remain zero.

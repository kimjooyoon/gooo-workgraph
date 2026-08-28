#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 9; then
  echo "usage: workspace-inventory-report.sh GRAPH DENOMINATOR COMPLETE REPLAY UNKNOWN REFUTED RUNTIME OUTPUT SUBJECT_SHA" >&2
  exit 2
fi

graph=$1
denominator=$2
complete=$3
replay=$4
unknown=$5
refuted=$6
runtime=$7
output=$8
subject_sha=$9

for file in "$graph" "$denominator" "$complete" "$replay" "$unknown" "$refuted" "$runtime"; do
  test -f "$file" || { echo "missing required input: $file" >&2; exit 2; }
done

jq -e '
  .schema=="gooo/workgraph-workspace-inventory-denominator/v1" and
  .candidate_id=="gooo.product.workspace-inventory.v1" and
  .total==12 and (.cells|length)==12 and
  ([.proofs[].total]|add)==12 and
  ([.indicator_classes[].total]|add)==12
' "$denominator" >/dev/null

jq -e --slurpfile denominator "$denominator" '
  . as $graph |
  .schema_version=="gooo-graph/v1" and
  ([$graph.nodes[]|select(.kind=="Activity")]|length)==12 and
  ([$denominator[0].cells[] as $cell |
    select(([$graph.nodes[]|select(.kind=="Activity" and .name==$cell.activity)]|length)==1)
  ]|length)==12
' "$graph" >/dev/null

cmp -s "$complete" "$replay"

jq -e '
  .schema=="gooo/workgraph-workspace-inventory/v1" and
  .decision=="WORKSPACE_INVENTORY_OBSERVED" and
  .subject.root=="testdata/workspace" and .subject.root_kind=="DIRECTORY" and
  .claim.state=="CLOSED" and .claim.reason=="WORKSPACE_INVENTORY_OBSERVED" and
  .summary=={
    directories:7,files:5,go_files:2,gooo_files:2,other_files:1,
    go_lines:6,gooo_lines:8,other_lines:2,total_lines:16,
    root_readme_present:false,root_readme_required:false,root_readme_excluded:true
  } and
  (.files|length)==5 and
  ([.files[]|select(.language=="GO")]|length)==2 and
  ([.files[]|select(.language=="GOOO")]|length)==2 and
  any(.files[];.path=="cmd/app/main.go" and .language=="GO" and .lines==3) and
  any(.files[];.path=="internal/model/model.go" and .language=="GO" and .lines==3) and
  any(.files[];.path=="spec/workspace.gooo" and .language=="GOOO" and .lines==5) and
  any(.files[];.path=="spec/rules/readiness.gooo" and .language=="GOOO" and .lines==3) and
  .authority.source=="examples/workspace-inventory/main.gooo" and
  .authority.repository_writes==0 and
  .authority.root_readme_readiness=="EXCLUDED"
' "$complete" >/dev/null

jq -e '
  .schema=="gooo/workgraph-workspace-inventory/v1" and
  .decision=="WORKSPACE_INVENTORY_UNKNOWN" and
  .subject.root_kind=="MISSING" and
  .claim.state=="UNKNOWN" and .claim.stage=="INPUT" and
  .claim.step=="OBSERVE_WORKSPACE_ROOT" and
  .claim.reason=="WORKSPACE_ROOT_NOT_FOUND" and
  .claim.unknown_class=="DIRECT_MISSING" and
  .claim.next_operation=="PROVIDE_WORKSPACE_ROOT"
' "$unknown" >/dev/null

jq -e '
  .schema=="gooo/workgraph-workspace-inventory/v1" and
  .decision=="FAIL_CLOSED" and .subject.root_kind=="FILE" and
  .claim.state=="REFUTED" and .claim.stage=="INPUT" and
  .claim.step=="VALIDATE_WORKSPACE_ROOT" and
  .claim.reason=="WORKSPACE_ROOT_NOT_DIRECTORY" and
  .claim.unknown_class==null and
  .claim.next_operation=="SELECT_WORKSPACE_DIRECTORY"
' "$refuted" >/dev/null

jq -e '
  .schema=="gooo/workgraph-workspace-inventory-runtime/v1" and
  .go_version=="go1.27.0" and
  .peak_rss_kib>0 and .wall_ms>=0 and
  .repository_writes==0 and .go_fix_writes==0 and
  .ci_test_cases==3 and .local_tests_run==0 and
  .cross_project_required_gates==0
' "$runtime" >/dev/null

digest() {
  printf 'sha256:%s' "$(sha256sum "$1" | awk '{print $1}')"
}

graph_digest=$(digest "$graph")
denominator_digest=$(digest "$denominator")
complete_digest=$(digest "$complete")
runtime_digest=$(digest "$runtime")

jq -S -n \
  --slurpfile denominator "$denominator" \
  --slurpfile complete "$complete" \
  --slurpfile runtime "$runtime" \
  --arg subject_sha "$subject_sha" \
  --arg graph_digest "$graph_digest" \
  --arg denominator_digest "$denominator_digest" \
  --arg complete_digest "$complete_digest" \
  --arg runtime_digest "$runtime_digest" '
  $denominator[0] as $d |
  $complete[0] as $complete |
  $runtime[0] as $runtime |
  [$d.cells[]|{
    id,activity,proof_choice,indicator_class,metric_path,
    state:"CLOSED",reason:.closed_reason,unknown_class:null,next_operation:"NONE"
  }] as $cells |
  {
    schema:"gooo/workgraph-workspace-inventory-report/v1",
    subject_sha:$subject_sha,
    decision:"WORKSPACE_INVENTORY_VERTICAL_SLICE_OBSERVED",
    candidate:{id:$d.candidate_id,state:"IMPLEMENTED",implementation_status:"INDEPENDENT_VERTICAL_SLICE_OBSERVED"},
    claim:{state:"CLOSED",stage:null,step:null,reason:"WORKSPACE_INVENTORY_VERTICAL_SLICE_CLOSED",
      unknown_class:null,next_operation:"PUBLISH_IMMUTABLE_WORKGRAPH_RELEASE",blocked_by:[]},
    summary:{
      total_cells:12,closed_cells:12,unknown_cells:0,refuted_cells:0,
      directories:$complete.summary.directories,files:$complete.summary.files,
      go_files:$complete.summary.go_files,go_lines:$complete.summary.go_lines,
      gooo_files:$complete.summary.gooo_files,gooo_lines:$complete.summary.gooo_lines,
      other_files:$complete.summary.other_files,other_lines:$complete.summary.other_lines,
      root_readme_present:$complete.summary.root_readme_present,
      root_readme_required:$complete.summary.root_readme_required,
      repository_writes:$runtime.repository_writes,ci_test_cases:$runtime.ci_test_cases,
      local_tests_run:$runtime.local_tests_run,cross_project_required_gates:$runtime.cross_project_required_gates
    },
    scenarios:{closed:1,unknown:1,refuted:1,deterministic_replay:1,total:4},
    cells:$cells,
    proofs:([$d.proofs[] as $proof|{
      choice:$proof.choice,
      closed:([$cells[]|select(.proof_choice==$proof.choice)]|length),
      total:$proof.total
    }]),
    indicator_classes:([$d.indicator_classes[] as $class|{
      class:$class.class,
      closed:([$cells[]|select(.indicator_class==$class.class)]|length),
      total:$class.total
    }]),
    indicators:[
      {id:"gooo.metric.workgraph.workspace-directories.v1",class:"OUTCOME",value:$complete.summary.directories,unit:"directories",state:"OBSERVED",activity:"CountNestedDirectories"},
      {id:"gooo.metric.workgraph.workspace-files.v1",class:"OUTCOME",value:$complete.summary.files,unit:"files",state:"OBSERVED",activity:"CountRegularFiles"},
      {id:"gooo.metric.workgraph.go-files.v1",class:"DRIVER",value:$complete.summary.go_files,unit:"files",state:"OBSERVED",activity:"ClassifyGoFiles"},
      {id:"gooo.metric.workgraph.gooo-files.v1",class:"DRIVER",value:$complete.summary.gooo_files,unit:"files",state:"OBSERVED",activity:"ClassifyGoooFiles"},
      {id:"gooo.metric.workgraph.go-lines.v1",class:"OUTCOME",value:$complete.summary.go_lines,unit:"physical_lines",state:"OBSERVED",activity:"CountGoLines"},
      {id:"gooo.metric.workgraph.gooo-lines.v1",class:"OUTCOME",value:$complete.summary.gooo_lines,unit:"physical_lines",state:"OBSERVED",activity:"CountGoooLines"},
      {id:"gooo.metric.workgraph.meta-bindings.v1",class:"DRIVER",value:12,total:12,unit:"activities",state:"SATISFIED",activity:"ObserveWorkspaceRoot"},
      {id:"gooo.metric.workgraph.scenario-coverage.v1",class:"GUARDRAIL",value:4,total:4,unit:"scenarios",state:"SATISFIED",activity:"TraceUnknownWorkspacePath"},
      {id:"gooo.metric.workgraph.repository-writes.v1",class:"GUARDRAIL",value:$runtime.repository_writes,target:0,unit:"writes",state:"SATISFIED",activity:"ObserveWorkspaceResources"},
      {id:"gooo.metric.workgraph.peak-rss.v1",class:"GUARDRAIL",value:$runtime.peak_rss_kib,unit:"KiB",state:"OBSERVED",activity:"ObserveWorkspaceResources"},
      {id:"gooo.metric.workgraph.wall-time.v1",class:"GUARDRAIL",value:$runtime.wall_ms,unit:"ms",state:"OBSERVED",activity:"ObserveWorkspaceResources"}
    ],
    authority:{
      meta_source:"examples/workspace-inventory/main.gooo",
      core_release:"kimjooyoon/meta-ontology-go@v0.3.0-dev",
      root_readme_readiness:"EXCLUDED",
      source_repository_writes:$runtime.repository_writes,
      local_tests_run:$runtime.local_tests_run,
      cross_project_required_gates:$runtime.cross_project_required_gates
    },
    evidence:{graph_digest:$graph_digest,denominator_digest:$denominator_digest,
      complete_digest:$complete_digest,runtime_digest:$runtime_digest}
  }
' > "$output"

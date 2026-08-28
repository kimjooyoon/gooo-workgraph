#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 9; then
  echo "usage: claim-resolution-adoption-report.sh ROOT RECEIPTS ACTIONS REPORT COMPLETE RUNTIME OUTPUT HEAD_SHA PHASE" >&2
  exit 64
fi

root=$(cd "$1" && pwd)
receipts=$2
actions=$3
report=$4
complete=$5
runtime=$6
output=$7
head_sha=$8
phase=$9
denominator="$root/contracts/claim-resolution-adoption-denominator-v1.json"
lock="$root/contracts/claim-resolution-adoption-release-lock-v1.json"
source="$root/examples/claim-resolution-adoption/main.gooo"
toolchain="$actions/toolchain.json"

for required in "$denominator" "$lock" "$source" "$report" "$complete" "$runtime" "$toolchain"; do
  test -f "$required" || { echo "missing required input: $required" >&2; exit 66; }
done

jq -e '.target_cells==12 and (.cells|length)==12 and ([.cells[].activity]|unique|length)==12 and
  ([.proof_totals[].total]|add)==12 and ([.indicator_totals[].total]|add)==12' "$denominator" >/dev/null
jq -e '.schema=="gooo/workgraph/claim-resolution-adoption-release-lock/v1" and .core.tag=="v0.3.0-dev" and .workgraph.tag=="v0.2.0-dev"' "$lock" >/dev/null
test "$(grep -c '^activity ' "$source")" -eq 12
grep -Fq 'gooo.primitive.claim-resolution-tuple.v1' "$source"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
json_or_null() {
  if test -f "$1" && jq -e . "$1" >/dev/null 2>&1; then cp "$1" "$2"; else printf 'null\n' > "$2"; fi
}

: > "$work/receipt-map.ndjson"
while IFS= read -r activity; do
  json_or_null "$receipts/$activity.json" "$work/$activity.json"
  jq -cn --arg key "$activity" --slurpfile value "$work/$activity.json" '{key:$key,value:$value[0]}' >> "$work/receipt-map.ndjson"
done < <(jq -r '.cells[].activity' "$denominator")
jq -s 'from_entries' "$work/receipt-map.ndjson" > "$work/receipts.json"

json_or_null "$receipts/ReplayWorkspaceClaimResolution.replay.json" "$work/replay-receipt.json"
json_or_null "$actions/workspace-unknown.json" "$work/unknown.json"
json_or_null "$actions/workspace-refuted.json" "$work/refuted.json"
json_or_null "$actions/workspace-replay.json" "$work/product-replay.json"

: > "$work/source-lines.ndjson"
while IFS= read -r -d '' file; do
  relative=${file#"$root/"}
  lines=$(wc -l < "$file" | tr -d ' ')
  case "$file" in *.go) language=Go ;; *.gooo) language=Gooo ;; *) continue ;; esac
  jq -cn --arg path "$relative" --arg language "$language" --argjson lines "$lines" '{path:$path,language:$language,lines:$lines}' >> "$work/source-lines.ndjson"
done < <(find "$root" -type f -not -path "$root/.git/*" \( -name '*.go' -o -name '*.gooo' \) -print0 | sort -z)
repository_files=$(find "$root" -type f -not -path "$root/.git/*" | wc -l | tr -d ' ')
descendant_directories=$(find "$root" -mindepth 1 -type d -not -path "$root/.git" -not -path "$root/.git/*" | wc -l | tr -d ' ')
jq -s --argjson repository_files "$repository_files" --argjson descendant_directories "$descendant_directories" '
  . as $files | {repository_files:$repository_files,descendant_directories:$descendant_directories,root_readme_readiness:"EXCLUDED",
    go:{files:([$files[]|select(.language=="Go")]|length),lines:([$files[]|select(.language=="Go")|.lines]|add//0)},
    gooo:{files:([$files[]|select(.language=="Gooo")]|length),lines:([$files[]|select(.language=="Gooo")|.lines]|add//0)},per_file:$files}' \
  "$work/source-lines.ndjson" > "$work/inventory.json"

jq -S -n \
  --slurpfile denominator "$denominator" --slurpfile lock "$lock" --slurpfile receipts "$work/receipts.json" \
  --slurpfile report "$report" --slurpfile complete "$complete" --slurpfile unknown "$work/unknown.json" \
  --slurpfile refuted "$work/refuted.json" --slurpfile product_replay "$work/product-replay.json" \
  --slurpfile replay_receipt "$work/replay-receipt.json" --slurpfile toolchain "$toolchain" \
  --slurpfile runtime "$runtime" --slurpfile inventory "$work/inventory.json" --rawfile source "$source" \
  --arg head_sha "$head_sha" --arg phase "$phase" '
  def has_six($claim):
    ($claim|type)=="object" and ($claim|has("state")) and ($claim|has("stage")) and ($claim|has("step")) and
    ($claim|has("reason")) and ($claim|has("unknown_class")) and ($claim|has("next_operation"));
  def field_count($claim):
    if ($claim|type)!="object" then 0 else
      [($claim|has("state")),($claim|has("stage")),($claim|has("step")),($claim|has("reason")),
       ($claim|has("unknown_class")),($claim|has("next_operation"))]|map(select(.==true))|length
    end;
  def normalize($claim):
    {state:$claim.state,stage:($claim.stage//"NONE"),step:($claim.step//"NONE"),reason:$claim.reason,
     unknown_class:(if (($claim.unknown_class//"")=="") then "NONE" else $claim.unknown_class end),next_operation:$claim.next_operation};
  def receipt($activity): $receipts[0][$activity];
  def bound($activity):
    (receipt($activity)) as $r | $r!=null and $r.schema=="gooo/claim-resolution/v1" and
    $r.candidate_id=="gooo.primitive.claim-resolution-tuple.v1" and $r.subject.activity==$activity and
    $r.subject.activity_occurrences==1 and $r.summary.fields_observed==6 and $r.summary.fields_total==6;
  def observed($activity): bound($activity) and receipt($activity).decision=="CLAIM_RESOLUTION_OBSERVED";
  def rejected($activity;$reason): bound($activity) and receipt($activity).decision=="FAIL_CLOSED" and receipt($activity).claim.reason==$reason;
  def same_claim($activity;$claim): observed($activity) and has_six($claim) and normalize(receipt($activity).claim)==normalize($claim);
  ($complete[0].claim//null) as $closed_claim |
  ($unknown[0].claim//null) as $unknown_claim |
  ($refuted[0].claim//null) as $refuted_claim |
  ([
    $complete[0].summary.directories==7,$complete[0].summary.files==5,$complete[0].summary.go_files==2,
    $complete[0].summary.go_lines==6,$complete[0].summary.gooo_files==2,$complete[0].summary.gooo_lines==8,
    $complete[0].summary.root_readme_present==false,$complete[0].summary.root_readme_required==false,
    $complete[0].summary.root_readme_excluded==true
  ]|map(select(.==true))|length) as $workspace_facts |
  ($report[0].schema=="gooo/workgraph-workspace-inventory-report/v1" and
    $report[0].subject_sha==$lock[0].workgraph.target_commit_sha and $report[0].decision=="WORKSPACE_INVENTORY_VERTICAL_SLICE_OBSERVED" and
    $report[0].summary.closed_cells==12 and $report[0].summary.total_cells==12 and $report[0].scenarios=={closed:1,deterministic_replay:1,refuted:1,total:4,unknown:1}) as $report_ok |
  ((field_count($closed_claim))+(field_count($unknown_claim))+(field_count($refuted_claim))) as $released_fields |
  ((field_count(receipt("ResolveReleasedClosedWorkspaceClaim").claim))+
    (field_count(receipt("PreserveReleasedUnknownWorkspaceClaim").claim))+
    (field_count(receipt("PreserveReleasedRefutedWorkspaceClaim").claim))) as $core_fields |
  ([same_claim("ResolveReleasedClosedWorkspaceClaim";$closed_claim),same_claim("PreserveReleasedUnknownWorkspaceClaim";$unknown_claim),
    same_claim("PreserveReleasedRefutedWorkspaceClaim";$refuted_claim)]|map(select(.==true))|length) as $scenario_matches |
  ([rejected("RejectIncompleteUnknownTuple";"UNKNOWN_TUPLE_INCOMPLETE"),rejected("RejectUnknownParentDecision";"CLAIM_STATE_UNKNOWN")]|map(select(.==true))|length) as $invalid_rejections |
  ([$denominator[0].cells[].activity|select(bound(.))]|length) as $activities_bound |
  {
    ObserveReleasedWorkgraph:(observed("ObserveReleasedWorkgraph") and $runtime[0].workgraph_release_observed==true and $report_ok),
    ObserveReleasedClaimPrimitive:(observed("ObserveReleasedClaimPrimitive") and $runtime[0].core_release_observed==true),
    BindReleasedClosedWorkspaceClaim:(same_claim("BindReleasedClosedWorkspaceClaim";$closed_claim) and $workspace_facts==9),
    ResolveReleasedClosedWorkspaceClaim:(same_claim("ResolveReleasedClosedWorkspaceClaim";$closed_claim) and $workspace_facts==9),
    BindReleasedUnknownWorkspaceClaim:same_claim("BindReleasedUnknownWorkspaceClaim";$unknown_claim),
    PreserveReleasedUnknownWorkspaceClaim:same_claim("PreserveReleasedUnknownWorkspaceClaim";$unknown_claim),
    BindReleasedRefutedWorkspaceClaim:same_claim("BindReleasedRefutedWorkspaceClaim";$refuted_claim),
    PreserveReleasedRefutedWorkspaceClaim:same_claim("PreserveReleasedRefutedWorkspaceClaim";$refuted_claim),
    RejectIncompleteUnknownTuple:rejected("RejectIncompleteUnknownTuple";"UNKNOWN_TUPLE_INCOMPLETE"),
    RejectUnknownParentDecision:rejected("RejectUnknownParentDecision";"CLAIM_STATE_UNKNOWN"),
    ReplayWorkspaceClaimResolution:(observed("ReplayWorkspaceClaimResolution") and $replay_receipt[0]==receipt("ReplayWorkspaceClaimResolution") and $product_replay[0]==$complete[0]),
    ObserveReadOnlyEffect:(observed("ObserveReadOnlyEffect") and $runtime[0].repository.writes==0 and
      $runtime[0].authority.generator_authority==false and $runtime[0].authority.cross_project_required_gates==0 and
      $runtime[0].authority.local_test_executions==0 and $runtime[0].authority.current_go_module_roots==1 and
      $runtime[0].authority.adoption_go_fix_executions==0 and $toolchain[0].go_version=="go1.27.0" and
      $toolchain[0].ci_test_cases==3 and $toolchain[0].go_fix_writes==0 and $toolchain[0].local_tests_run==0)
  } as $facts |
  def upstream_missing($activity):
    (($activity=="BindReleasedClosedWorkspaceClaim" or $activity=="ResolveReleasedClosedWorkspaceClaim") and $closed_claim==null) or
    (($activity=="BindReleasedUnknownWorkspaceClaim" or $activity=="PreserveReleasedUnknownWorkspaceClaim") and $unknown_claim==null) or
    (($activity=="BindReleasedRefutedWorkspaceClaim" or $activity=="PreserveReleasedRefutedWorkspaceClaim") and $refuted_claim==null);
  def evaluate($cell):
    ($cell.activity) as $activity |
    if receipt($activity)==null then
      $cell+{state:"UNKNOWN",stage:"CORE_RECEIPT",step:"OBSERVE_CLAIM_RESOLUTION_RECEIPT",reason:"CORE_CLAIM_RESOLUTION_RECEIPT_UNAVAILABLE",unknown_class:"DIRECT_MISSING",next_operation:"PROVIDE_CORE_CLAIM_RESOLUTION_RECEIPT"}
    elif upstream_missing($activity) then
      $cell+{state:"UNKNOWN",reason:$cell.unknown_reason,unknown_class:"DIRECT_MISSING"}
    elif $facts[$activity]==true then
      $cell+{state:"CLOSED",reason:$cell.closed_reason,unknown_class:null,next_operation:"NONE"}
    else
      $cell+{state:"REFUTED",reason:$cell.refuted_reason,unknown_class:null}
    end;
  ($denominator[0].cells|map(evaluate(.))) as $cells |
  ([$cells[]|select(.state=="CLOSED")]|length) as $closed_count |
  ([$cells[]|select(.state=="UNKNOWN")]|length) as $unknown_count |
  ([$cells[]|select(.state=="REFUTED")]|length) as $refuted_count |
  (([$cells[]|select(.state=="REFUTED")]|first)//([$cells[]|select(.state=="UNKNOWN")]|first)) as $first_nonclosed |
  {
    schema:"gooo/workgraph/claim-resolution-adoption-report/v1",phase:$phase,subject_sha:$head_sha,
    decision:(if $refuted_count>0 then "FAIL_CLOSED" elif $unknown_count>0 then "ADOPTION_EVIDENCE_UNKNOWN" else "WORKGRAPH_CLAIM_RESOLUTION_ADOPTED" end),
    claim:{state:(if $refuted_count>0 then "REFUTED" elif $unknown_count>0 then "UNKNOWN" else "CLOSED" end),
      stage:($first_nonclosed.stage//null),step:($first_nonclosed.step//null),reason:($first_nonclosed.reason//"WORKGRAPH_CLAIM_RESOLUTION_ADOPTION_CLOSED"),
      unknown_class:($first_nonclosed.unknown_class//null),next_operation:($first_nonclosed.next_operation//"PUBLISH_WORKGRAPH_CLAIM_RESOLUTION_ADOPTION")},
    summary:{total:12,closed:$closed_count,unknown:$unknown_count,refuted:$refuted_count,
      direct_missing:([$cells[]|select(.unknown_class=="DIRECT_MISSING")]|length),dependency_blocked:0},
    adoption:{candidate_id:"gooo.primitive.claim-resolution-tuple.v1",direct_mappings:1,direct_mapping_total:1,independent_consumers:1,
      released_scenarios:$scenario_matches,released_scenario_total:3,released_claim_fields:$released_fields,released_claim_field_total:18,
      core_claim_fields:$core_fields,core_claim_field_total:18,workspace_inventory_facts:$workspace_facts,workspace_inventory_fact_total:9,
      invalid_tuples_rejected:$invalid_rejections,invalid_tuple_total:2,activities_bound:$activities_bound,activity_total:12,
      release_locks_observed:([$runtime[0].core_release_observed,$runtime[0].workgraph_release_observed]|map(select(.==true))|length),release_lock_total:2},
    authority:{evidence:"PINNED_IMMUTABLE_RELEASE_ASSETS",core_mutation_authorized:false,generator_authority:$runtime[0].authority.generator_authority,
      cross_project_required_gates:$runtime[0].authority.cross_project_required_gates,local_test_executions:$runtime[0].authority.local_test_executions,
      current_go_module_roots:$runtime[0].authority.current_go_module_roots,adoption_go_fix_executions:$runtime[0].authority.adoption_go_fix_executions,
      released_ci_test_cases:$toolchain[0].ci_test_cases,released_go_fix_writes:$toolchain[0].go_fix_writes,
      root_readme_readiness:"EXCLUDED",repository_writes:$runtime[0].repository.writes,build_execution:"NOT_CLAIMED",task_execution:"NOT_CLAIMED"},
    performance:$runtime[0].performance,toolchain:$toolchain[0],inventory:$inventory[0],cells:$cells,
    proofs:(["FOUNDATION","COHERENCE","REGRESSION"]|map(. as $choice|{choice:$choice,closed:([$cells[]|select(.proof_choice==$choice and .state=="CLOSED")]|length),total:([$cells[]|select(.proof_choice==$choice)]|length)})),
    indicator_classes:(["DRIVER","OUTCOME","GUARDRAIL"]|map(. as $class|{class:$class,closed:([$cells[]|select(.indicator_class==$class and .state=="CLOSED")]|length),total:([$cells[]|select(.indicator_class==$class)]|length)})),
    indicators:[
      {id:"gooo.metric.workgraph-claim-adoption.direct-mappings.v1",class:"OUTCOME",activity:"ResolveReleasedClosedWorkspaceClaim",value:1,total:1,unit:"mappings"},
      {id:"gooo.metric.workgraph-claim-adoption.scenario-equivalence.v1",class:"OUTCOME",activity:"ReplayWorkspaceClaimResolution",value:$scenario_matches,total:3,unit:"scenarios"},
      {id:"gooo.metric.workgraph-claim-adoption.released-fields.v1",class:"DRIVER",activity:"BindReleasedUnknownWorkspaceClaim",value:$released_fields,total:18,unit:"fields"},
      {id:"gooo.metric.workgraph-claim-adoption.core-fields.v1",class:"DRIVER",activity:"PreserveReleasedUnknownWorkspaceClaim",value:$core_fields,total:18,unit:"fields"},
      {id:"gooo.metric.workgraph-claim-adoption.workspace-facts.v1",class:"DRIVER",activity:"BindReleasedClosedWorkspaceClaim",value:$workspace_facts,total:9,unit:"facts"},
      {id:"gooo.metric.workgraph-claim-adoption.invalid-tuples.v1",class:"GUARDRAIL",activity:"RejectUnknownParentDecision",value:$invalid_rejections,total:2,unit:"tuples"},
      {id:"gooo.metric.workgraph-claim-adoption.meta-activities.v1",class:"DRIVER",activity:"ObserveReleasedClaimPrimitive",value:$activities_bound,total:12,unit:"activities"},
      {id:"gooo.metric.workgraph-claim-adoption.peak-rss.v1",class:"DRIVER",activity:"ResolveReleasedClosedWorkspaceClaim",value:$runtime[0].performance.claim_resolve_peak_rss_kib,unit:"KiB"},
      {id:"gooo.metric.workgraph-claim-adoption.wall-time.v1",class:"DRIVER",activity:"ResolveReleasedClosedWorkspaceClaim",value:$runtime[0].performance.claim_resolve_wall_ms,unit:"ms"},
      {id:"gooo.metric.workgraph-claim-adoption.repository-writes.v1",class:"GUARDRAIL",activity:"ObserveReadOnlyEffect",value:$runtime[0].repository.writes,total:0,unit:"writes"},
      {id:"gooo.metric.workgraph-claim-adoption.go-lines.v1",class:"DRIVER",activity:"ObserveReleasedWorkgraph",value:$inventory[0].go.lines,unit:"lines"},
      {id:"gooo.metric.workgraph-claim-adoption.gooo-lines.v1",class:"DRIVER",activity:"ObserveReleasedClaimPrimitive",value:$inventory[0].gooo.lines,unit:"lines"}
    ]
  }' > "$output"

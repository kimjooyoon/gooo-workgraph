#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 12; then
  echo "usage: selective-ci-work-selection-report.sh ROOT INPUT LOCK RECEIPT RESULT DENOMINATOR GRAPH RESOLUTION RUNTIME OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

root=$(cd "$1" && pwd)
input=$2
lock=$3
receipt=$4
result=$5
denominator=$6
graph=$7
resolution=$8
runtime=$9
output=${10}
subject_sha=${11}
scenario=${12}

for required in "$input" "$lock" "$denominator" "$graph" "$resolution" "$runtime"; do
  test -f "$required" || { echo "missing required input: $required" >&2; exit 66; }
done

if test -e "$output"; then
  test -d "$output" || { echo "output must be an empty directory" >&2; exit 65; }
  test -z "$(find "$output" -mindepth 1 -print -quit)" || { echo "output directory must be empty" >&2; exit 65; }
else
  mkdir -p "$output"
fi
output_real=$(cd "$output" && pwd)
case "$output_real/" in
  "$root/"*) echo "output directory must be outside the source repository" >&2; exit 65 ;;
esac

digest_or_missing() {
  local file=$1
  if test -f "$file"; then sha256sum "$file" | awk '{print $1}'; else echo MISSING; fi
}

json_value() {
  local expression=$1 file=$2 fallback=$3
  jq -r "$expression" "$file" 2>/dev/null || echo "$fallback"
}

denominator_ok=false
if jq -e '
  .schema=="gooo/workgraph/selective-ci-work-selection-denominator/v1" and
  .target_cells==12 and (.cells|length)==12 and
  ([.cells[].id]|unique|length)==12 and ([.cells[].activity]|unique|length)==12 and
  ([.proof_totals[].total]|add)==12 and all(.proof_totals[];.total==4) and
  ([.indicator_totals[].total]|add)==12 and all(.indicator_totals[];.total==4)
' "$denominator" >/dev/null 2>&1; then
  denominator_ok=true
fi

activities='[]'
if test "$denominator_ok" = true; then
  activities=$(jq -c '[.cells[].activity]' "$denominator")
fi

lock_ok=false
if jq -e '
  .schema=="gooo/workgraph/test-receipt-reuse-release-lock/v1" and
  .producer.repository=="kimjooyoon/gooo-evidence-generator" and
  .producer.tag=="v0.5.0-dev" and .producer.bundle.expected_files==44 and
  .gooo.repository=="kimjooyoon/meta-ontology-go" and .gooo.tag=="v0.2.0-dev" and
  .subject.path=="examples/test-receipt-reuse/main.gooo" and
  (.baseline.result_sha256|type)=="string" and (.baseline.semantic_hash|type)=="string" and
  .baseline.decision=="PASS"
' "$lock" >/dev/null 2>&1; then
  lock_ok=true
fi
expected_result_digest=$(json_value '.baseline.result_sha256 // "MISSING"' "$lock" MISSING)
expected_semantic_hash=$(json_value '.baseline.semantic_hash // "MISSING"' "$lock" MISSING)

input_schema_ok=false
input_plan_ok=false
if jq -e '.schema=="gooo/workgraph/selective-ci-work-selection-input/v1"' "$input" >/dev/null 2>&1; then
  input_schema_ok=true
fi
if jq -e '
  (.subject_sha|type)=="string" and
  (.current_scope|type)=="object" and
  (.tests|type)=="array" and (.tests|length)==1 and
  .tests[0].id=="released-gooo-semantic-test" and .tests[0].required==true and
  (.tests[0].scope|type)=="object" and
  (.tests[0].scope == .current_scope)
' "$input" >/dev/null 2>&1; then
  input_plan_ok=true
fi
input_ok=false
test "$input_schema_ok" = true && test "$input_plan_ok" = true && input_ok=true

receipt_present=false
receipt_schema_ok=false
receipt_scope_present=false
receipt_decision=MISSING
receipt_semantic_hash=MISSING
receipt_result_digest=MISSING
receipt_test_executions=UNKNOWN
receipt_repository_writes=UNKNOWN
receipt_source_mutations=UNKNOWN
receipt_local_test_executions=UNKNOWN
if test -f "$receipt"; then
  receipt_present=true
  if jq -e '.schema=="gooo/evidence-generator/test-receipt/v1"' "$receipt" >/dev/null 2>&1; then receipt_schema_ok=true; fi
  if jq -e '.scope|type=="object"' "$receipt" >/dev/null 2>&1; then receipt_scope_present=true; fi
  receipt_decision=$(json_value '.result.decision // "MISSING"' "$receipt" MISSING)
  receipt_semantic_hash=$(json_value '.result.semantic_hash // "MISSING"' "$receipt" MISSING)
  receipt_result_digest=$(json_value '.result.output_sha256 // "MISSING"' "$receipt" MISSING)
  receipt_test_executions=$(json_value 'if (.execution.test_executions|type)=="number" then .execution.test_executions else "UNKNOWN" end' "$receipt" UNKNOWN)
  receipt_repository_writes=$(json_value 'if (.authority.repository_writes|type)=="number" then .authority.repository_writes else "UNKNOWN" end' "$receipt" UNKNOWN)
  receipt_source_mutations=$(json_value 'if (.authority.source_mutations|type)=="number" then .authority.source_mutations else "UNKNOWN" end' "$receipt" UNKNOWN)
  receipt_local_test_executions=$(json_value 'if (.authority.local_test_executions|type)=="number" then .authority.local_test_executions else "UNKNOWN" end' "$receipt" UNKNOWN)
fi

result_present=false
result_status=MISSING
result_semantic_hash=MISSING
result_diagnostics=MISSING
result_digest=$(digest_or_missing "$result")
if test -f "$result"; then
  result_present=true
  result_status=$(json_value '.status // "MISSING"' "$result" MISSING)
  result_semantic_hash=$(json_value '.semantic_hash // "MISSING"' "$result" MISSING)
  result_diagnostics=$(json_value 'if (.diagnostics|type)=="array" then (.diagnostics|length|tostring) else "MISSING" end' "$result" MISSING)
fi

current_scope_digest=MISSING
if test "$input_ok" = true; then current_scope_digest=$(jq -S -c '.current_scope' "$input" | sha256sum | awk '{print $1}'); fi
receipt_scope_digest=MISSING
if test "$receipt_scope_present" = true; then receipt_scope_digest=$(jq -S -c '.scope' "$receipt" | sha256sum | awk '{print $1}'); fi
scope_match=false
if test "$input_ok" = true && test "$receipt_scope_present" = true; then
  if test "$(jq -S -c '.current_scope' "$input")" = "$(jq -S -c '.scope' "$receipt")"; then scope_match=true; fi
fi

receipt_result_ok=false
result_digest_ok=false
if test "$receipt_present" = true && test "$receipt_schema_ok" = true && test "$result_present" = true; then
  if jq -e --arg expected_digest "$expected_result_digest" --arg expected_semantic "$expected_semantic_hash" '
    .schema_version=="gooo/diagnostics/v1" and .command=="check" and .status=="ok" and
    (.diagnostics|type)=="array" and (.diagnostics|length)==0 and
    .semantic_hash==$expected_semantic
  ' "$result" >/dev/null 2>&1 &&
     test "$result_digest" = "$expected_result_digest" &&
     test "$receipt_result_digest" = "$expected_result_digest"; then
    result_digest_ok=true
  fi
  if test "$result_digest_ok" = true && test "$receipt_semantic_hash" = "$expected_semantic_hash" && test "$receipt_decision" = PASS; then receipt_result_ok=true; fi
fi

authority_clean=false
if test "$receipt_present" = true && test "$receipt_schema_ok" = true; then
  if jq -e '
    (.authority.repository_writes|type)=="number" and .authority.repository_writes==0 and
    (.authority.source_mutations|type)=="number" and .authority.source_mutations==0 and
    (.authority.local_test_executions|type)=="number" and .authority.local_test_executions==0 and
    (.execution.test_executions|type)=="number" and .execution.test_executions==1
  ' "$receipt" >/dev/null 2>&1; then authority_clean=true; fi
fi

graph_ok=false
if test "$denominator_ok" = true; then
  if jq -e --argjson activities "$activities" '
    .schema_version=="gooo-graph/v1" and .ir.status=="available" and
    ([.nodes[]|select(.kind=="Activity")|.name]|sort)==($activities|sort) and
    ([.nodes[]|select(.kind=="Activity")]|length)==12
  ' "$graph" >/dev/null 2>&1; then graph_ok=true; fi
fi
resolution_ok=false
if test "$denominator_ok" = true; then
  if jq -e --argjson activities "$activities" '
    .schema=="gooo/workgraph/selective-ci-activity-resolution/v1" and
    .summary=={expected:12,observed:12,closed:12,unknown:0,refuted:0,unique_selectors:12} and
    ([.entries[]|.activity]|sort)==($activities|sort) and ([.entries[]]|length)==12 and
    all(.entries[]; .selector.name==.activity and .receipt.decision=="CLOSED" and .receipt.occurrences==1)
  ' "$resolution" >/dev/null 2>&1; then resolution_ok=true; fi
fi
meta_binding_ok=false
test "$graph_ok" = true && test "$resolution_ok" = true && meta_binding_ok=true

scope_state=REFUTED
test "$input_ok" = true && scope_state=CLOSED
receipt_state=UNKNOWN
if test "$receipt_present" = true; then
  if test "$receipt_schema_ok" = true; then receipt_state=CLOSED; else receipt_state=REFUTED; fi
fi
meta_state=REFUTED
test "$meta_binding_ok" = true && meta_state=CLOSED
plan_state=UNKNOWN
test "$input_ok" = true && plan_state=CLOSED
schema_state=UNKNOWN
if test "$receipt_present" = true; then
  if test "$receipt_schema_ok" = true; then schema_state=CLOSED; else schema_state=REFUTED; fi
fi
result_state=UNKNOWN
if test "$receipt_present" = true; then
  if test "$result_present" = false; then result_state=UNKNOWN
  elif test "$result_digest_ok" = true; then result_state=CLOSED
  else result_state=REFUTED
  fi
fi
semantic_state=UNKNOWN
if test "$receipt_present" = true; then
  if test "$receipt_semantic_hash" = MISSING || test "$result_semantic_hash" = MISSING; then semantic_state=UNKNOWN
  elif test "$receipt_semantic_hash" = "$expected_semantic_hash" && test "$result_semantic_hash" = "$expected_semantic_hash"; then semantic_state=CLOSED
  else semantic_state=REFUTED
  fi
fi
scope_equivalence_state=UNKNOWN
if test "$receipt_present" = true; then
  if test "$receipt_scope_present" = false; then scope_equivalence_state=UNKNOWN
  elif test "$scope_match" = true; then scope_equivalence_state=CLOSED
  else scope_equivalence_state=REFUTED
  fi
fi

known_contradiction=false
authority_escalated=false
if test "$authority_clean" = false && test "$receipt_present" = true; then authority_escalated=true; fi
decision_contradiction=false
if test "$receipt_present" = true && test "$receipt_decision" != PASS; then decision_contradiction=true; fi
for state in "$receipt_state" "$result_state" "$semantic_state" "$scope_equivalence_state"; do
  test "$state" = REFUTED && known_contradiction=true
done
test "$authority_escalated" = true && known_contradiction=true
test "$decision_contradiction" = true && known_contradiction=true
selection_state=UNKNOWN
if test "$input_ok" = true && test "$receipt_result_ok" = true && test "$scope_match" = true && test "$authority_clean" = true; then
  selection_state=CLOSED
elif test "$known_contradiction" = true; then
  selection_state=REFUTED
fi

selection_action=RERUN_REQUIRED
selection_reason=TEST_RECEIPT_MISSING
if test "$selection_state" = CLOSED; then
  selection_action=REUSE
  selection_reason=EXACT_INPUT_TOOLCHAIN_COMMAND_AND_RESULT_MATCH
elif test "$scope_equivalence_state" = REFUTED; then
  selection_reason=INPUT_TOOLCHAIN_OR_SCOPE_CHANGED
elif test "$semantic_state" = REFUTED; then
  selection_reason=DIGEST_VALID_SEMANTIC_IDENTITY_MISMATCH
elif test "$result_state" = REFUTED; then
  selection_reason=TEST_RECEIPT_RESULT_DIGEST_OR_STATUS_MISMATCH
elif test "$authority_escalated" = true; then
  selection_reason=TEST_RECEIPT_AUTHORITY_ESCALATED
fi

unknown_fields_ok=true
refuted_fields_ok=true
precedence_ok=true
facts='{}'
set_fact() {
  local activity=$1 state=$2 reason=${3:-}
  facts=$(jq -c --arg activity "$activity" --arg state "$state" --arg reason "$reason" \
    '. + {($activity):({state:$state} + (if $reason=="" then {} else {reason:$reason} end))}' <<<"$facts")
}
set_fact ObserveCurrentTestScope "$scope_state"
set_fact ObserveReleasedExactTestReceipt "$receipt_state"
set_fact BindSelectiveCIActivities "$meta_state"
set_fact PlanCIWork "$plan_state"
set_fact VerifyReceiptSchema "$schema_state"
set_fact VerifyReceiptResultDigest "$result_state"
if test "$semantic_state" = REFUTED; then
  set_fact VerifyReceiptSemanticIdentity "$semantic_state" DIGEST_VALID_SEMANTIC_IDENTITY_MISMATCH
else
  set_fact VerifyReceiptSemanticIdentity "$semantic_state"
fi
if test "$scope_equivalence_state" = REFUTED; then
  set_fact CompareInputToolchainAndScope "$scope_equivalence_state" INPUT_TOOLCHAIN_OR_SCOPE_CHANGED
else
  set_fact CompareInputToolchainAndScope "$scope_equivalence_state"
fi
set_fact SelectReuseOrRerun "$selection_state" "$selection_reason"
if test "$meta_binding_ok" = true; then set_fact PreserveSelectionUnknown CLOSED; else set_fact PreserveSelectionUnknown REFUTED; fi
set_fact EnforceRefutationPrecedence CLOSED

tests_planned=UNKNOWN
if test "$input_ok" = true; then tests_planned=$(jq -r '.tests|length' "$input"); fi
tests_reused=UNKNOWN
tests_required=UNKNOWN
if test "$input_ok" = true; then
  if test "$selection_state" = CLOSED; then tests_reused=1; tests_required=0; else tests_reused=0; tests_required=1; fi
fi
producer_observed=UNKNOWN
if test "$receipt_test_executions" != UNKNOWN; then producer_observed=$receipt_test_executions; fi
consumer_tests=$(json_value 'if (.executions.consumer_test_executions|type)=="number" then .executions.consumer_test_executions elif (.consumer_test_executions|type)=="number" then .consumer_test_executions else "UNKNOWN" end' "$runtime" UNKNOWN)
runtime_writes=$(json_value 'if (.authority.repository_writes|type)=="number" then .authority.repository_writes elif (.repository.writes|type)=="number" then .repository.writes else "UNKNOWN" end' "$runtime" UNKNOWN)
runtime_local_tests=$(json_value 'if (.authority.local_test_executions|type)=="number" then .authority.local_test_executions elif (.executions.local_test|type)=="number" then .executions.local_test else "UNKNOWN" end' "$runtime" UNKNOWN)

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

jq -S -n \
  --slurpfile denominator "$denominator" \
  --slurpfile lock "$lock" \
  --slurpfile input "$input" \
  --slurpfile runtime "$runtime" \
  --argjson facts "$facts" \
  --argjson activities "$activities" \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" \
  --arg selection_action "$selection_action" \
  --arg selection_state "$selection_state" \
  --arg selection_reason "$selection_reason" \
  --arg current_scope_digest "$current_scope_digest" \
  --arg receipt_scope_digest "$receipt_scope_digest" \
  --arg receipt_decision "$receipt_decision" \
  --arg receipt_semantic_hash "$receipt_semantic_hash" \
  --arg receipt_result_digest "$receipt_result_digest" \
  --arg result_digest "$result_digest" \
  --arg result_semantic_hash "$result_semantic_hash" \
  --arg expected_result_digest "$expected_result_digest" \
  --arg expected_semantic_hash "$expected_semantic_hash" \
  --arg receipt_test_executions "$receipt_test_executions" \
  --arg receipt_repository_writes "$receipt_repository_writes" \
  --arg receipt_source_mutations "$receipt_source_mutations" \
  --arg receipt_local_test_executions "$receipt_local_test_executions" \
  --arg result_status "$result_status" \
  --arg result_diagnostics "$result_diagnostics" \
  --argjson denominator_ok "$denominator_ok" \
  --argjson lock_ok "$lock_ok" \
  --argjson input_ok "$input_ok" \
  --argjson receipt_present "$receipt_present" \
  --argjson receipt_schema_ok "$receipt_schema_ok" \
  --argjson result_present "$result_present" \
  --argjson scope_match "$scope_match" \
  --argjson receipt_result_ok "$receipt_result_ok" \
  --argjson authority_clean "$authority_clean" \
  --argjson graph_ok "$graph_ok" \
  --argjson resolution_ok "$resolution_ok" \
  --argjson unknown_fields_ok "$unknown_fields_ok" \
  --argjson refuted_fields_ok "$refuted_fields_ok" \
  --argjson precedence_ok "$precedence_ok" \
  --arg tests_planned "$tests_planned" \
  --arg tests_reused "$tests_reused" \
  --arg tests_required "$tests_required" \
  --arg producer_observed "$producer_observed" \
  --arg consumer_tests "$consumer_tests" \
  --arg runtime_writes "$runtime_writes" \
  --arg runtime_local_tests "$runtime_local_tests" \
  '
  def typed($value): if $value=="UNKNOWN" then "UNKNOWN" else ($value|tonumber) end;
  (reduce $denominator[0].cells[] as $cell
    ({cells:[],decisions:{}};
      . as $acc |
      ($facts[$cell.activity] // {state:"UNSET"}) as $direct |
      ([$cell.depends_on[]? as $dependency | $acc.decisions[$dependency]]) as $dependencies |
      (if $direct.state=="REFUTED" then
        {state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:($direct.reason // $cell.refuted_reason),unknown_class:null,next_operation:$cell.next_operation,blocked_by:[]}
       elif $direct.state=="UNKNOWN" then
        {state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:($direct.reason // $cell.unknown_reason),unknown_class:"DIRECT_MISSING",next_operation:$cell.next_operation,blocked_by:[]}
       elif any($dependencies[];.state=="REFUTED") then
        {state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_REFUTED",unknown_class:null,next_operation:"RESOLVE_REFUTED_PREDECESSORS",blocked_by:[$dependencies[]|select(.state=="REFUTED")|.cell_id]}
       elif any($dependencies[];.state=="UNKNOWN") then
        {state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_BLOCKED",unknown_class:"DEPENDENCY_BLOCKED",next_operation:"RESOLVE_UNKNOWN_PREDECESSORS",blocked_by:[$dependencies[]|select(.state=="UNKNOWN")|.cell_id]}
       else
        {state:"CLOSED",stage:null,step:null,reason:$cell.closed_reason,unknown_class:null,next_operation:"NONE",blocked_by:[]}
       end) as $decision |
      .cells += [$cell + $decision + {cell_id:$cell.id}] |
      .decisions[$cell.id] = ($decision + {cell_id:$cell.id})
    )) as $evaluation |
  ([$evaluation.cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$evaluation.cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$evaluation.cells[]|select(.unknown_class=="DIRECT_MISSING")]|length) as $direct_missing |
  ([$evaluation.cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length) as $dependency_blocked |
  ([$evaluation.cells[]|select(.state=="REFUTED")][0] // null) as $first_refuted |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")][0] // null) as $first_unknown |
  {
    schema:"gooo/workgraph/selective-ci-work-selection-report/v1",
    scenario:$scenario,
    subject_sha:$subject_sha,
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "SELECTION_EVIDENCE_UNKNOWN" else "SELECTIVE_CI_WORK_SELECTION_READY" end),
    summary:{total:12,closed:$closed,unknown:$unknown,refuted:$refuted,direct_missing:$direct_missing,dependency_blocked:$dependency_blocked},
    selection:{state:(if $selection_action=="REUSE" then "CLOSED" elif $selection_state=="UNKNOWN" then "UNKNOWN" else "REFUTED" end),action:$selection_action,reason:$selection_reason,tests:[{id:"released-gooo-semantic-test",action:$selection_action,scope_match:$scope_match}]},
    metrics:{tests_planned:typed($tests_planned),tests_reused:typed($tests_reused),tests_required_to_execute:typed($tests_required),producer_test_executions_observed:typed($producer_observed),consumer_test_executions:typed($consumer_tests),saved_test_ms:"UNKNOWN"},
    release:{producer:$lock[0].producer,gooo:$lock[0].gooo,lock_verified:$lock_ok},
    receipt:{present:$receipt_present,schema_verified:$receipt_schema_ok,decision:$receipt_decision,semantic_hash:$receipt_semantic_hash,result_digest:$receipt_result_digest,expected_result_digest:$expected_result_digest,expected_semantic_hash:$expected_semantic_hash,result_verified:$receipt_result_ok,authority:{test_executions:typed($receipt_test_executions),repository_writes:typed($receipt_repository_writes),source_mutations:typed($receipt_source_mutations),local_test_executions:typed($receipt_local_test_executions)}},
    scopes:{current_digest:$current_scope_digest,receipt_digest:$receipt_scope_digest,exact_match:$scope_match},
    result:{present:$result_present,digest:$result_digest,semantic_hash:$result_semantic_hash,status:$result_status,diagnostics:typed($result_diagnostics)},
    meta_binding:{activities:$activities,graph_verified:$graph_ok,resolution_verified:$resolution_ok,activity_total:12},
    performance:($runtime[0].performance // {evaluator_wall_ms:"UNKNOWN",evaluator_peak_rss_kib:"UNKNOWN"}),
    inventory:($runtime[0].inventory // {root_readme_policy:"EXCLUDED",regular_files:"UNKNOWN",descendant_directories:"UNKNOWN",physical_lines:"UNKNOWN",go:{files:"UNKNOWN",lines:"UNKNOWN"},gooo:{files:"UNKNOWN",lines:"UNKNOWN"}}),
    artifact_links:{manifest:"manifest.json",human_dossier:"human-dossier.md"},
    authority:{application_root:"CALLER_OWNED_TEMP_ONLY",repository_writes:typed($runtime_writes),local_test_executions:typed($runtime_local_tests),consumer_test_executions:typed($consumer_tests),producer_source_checkout:0,sibling_checkout_reads:0},
    checks:{denominator:$denominator_ok,lock:$lock_ok,input:$input_ok,receipt_schema:$receipt_schema_ok,result:$receipt_result_ok,scope:$scope_match,authority:$authority_clean,graph:$graph_ok,resolution:$resolution_ok,unknown_fields:$unknown_fields_ok,refuted_fields:$refuted_fields_ok,refutation_precedence:$precedence_ok},
    cells:$evaluation.cells,
    claim:(if $first_refuted!=null then {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by}
      elif $first_unknown!=null then {state:"UNKNOWN",stage:$first_unknown.stage,step:$first_unknown.step,reason:$first_unknown.reason,unknown_class:$first_unknown.unknown_class,next_operation:$first_unknown.next_operation,blocked_by:$first_unknown.blocked_by}
      else {state:"CLOSED",stage:null,step:null,reason:"SELECTIVE_CI_WORK_SELECTION_CLOSED",unknown_class:null,next_operation:"EXECUTE_SELECTED_TEST_WORK",blocked_by:[]} end)
  }
' > "$output_real/report.json"

jq -e '
  .summary.total==12 and
  all(.cells[];
    has("stage") and has("step") and has("reason") and has("unknown_class") and has("next_operation") and has("blocked_by") and
    (if .state=="UNKNOWN" then .stage!=null and .step!=null and .reason!=null and .unknown_class!=null and .next_operation!=null and .blocked_by!=null
     elif .state=="REFUTED" then .stage!=null and .step!=null and .reason!=null and .unknown_class==null and .next_operation!=null and .blocked_by!=null
     else true end)) and
  all([.metrics.tests_planned,.metrics.tests_reused,.metrics.tests_required_to_execute,
       .metrics.producer_test_executions_observed,.metrics.consumer_test_executions,.metrics.saved_test_ms][];
    (type=="number" or .=="UNKNOWN")) and
  (.summary.refuted==0 or .claim.state=="REFUTED")
' "$output_real/report.json" >/dev/null

jq -S --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  '{schema:"gooo/workgraph/selective-ci-work-selection/v1",subject_sha:$subject_sha,scenario:$scenario,action:.selection.action,reason:.selection.reason,tests:.selection.tests,metrics:.metrics,performance:.performance,inventory:.inventory,artifact_links:.artifact_links,claim:.claim}' \
  "$output_real/report.json" > "$output_real/ci-work-selection.json"

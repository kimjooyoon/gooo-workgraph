#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 13; then
  echo "usage: selective-ci-work-selection-report.sh ROOT INPUT LOCK PRIOR_RECEIPT EXECUTION_RECEIPT RESULT DENOMINATOR GRAPH RESOLUTION RUNTIME OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

root=$(cd "$1" && pwd)
input=$2
lock=$3
prior_receipt=$4
execution_receipt=$5
result=$6
denominator=$7
graph=$8
resolution=$9
shift 9
runtime=$1
output=$2
subject_sha=$3
scenario=$4

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

json_value() {
  local expression=$1 file=$2 fallback=$3
  jq -r "$expression" "$file" 2>/dev/null || echo "$fallback"
}

digest_or_missing() {
  local file=$1
  if test -f "$file"; then sha256sum "$file" | awk '{print $1}'; else echo MISSING; fi
}

source_file="$root/examples/test-receipt-reuse/main.gooo"
meta_source_file="$root/examples/selective-ci-work-selection/main.gooo"
source_digest=$(digest_or_missing "$source_file")
meta_source_digest=$(digest_or_missing "$meta_source_file")

denominator_ok=false
if jq -e '
  .schema=="gooo/workgraph/selective-ci-work-selection-denominator/v1" and
  .target_cells==12 and (.cells|length)==12 and
  ([.cells[].id]|unique|length)==12 and ([.cells[].activity]|unique|length)==12 and
  ([.proof_totals[].total]|add)==12 and all(.proof_totals[];.total==4) and
  ([.indicator_totals[].total]|add)==12 and all(.indicator_totals[];.total==4)
' "$denominator" >/dev/null 2>&1; then denominator_ok=true; fi
activities='[]'
if test "$denominator_ok" = true; then activities=$(jq -c '[.cells[].activity] | sort' "$denominator"); fi

lock_ok=false
if jq -e '
  .schema=="gooo/workgraph/test-receipt-reuse-release-lock/v1" and
  .producer.repository=="kimjooyoon/gooo-evidence-generator" and .producer.tag=="v0.5.0-dev" and
  .producer.bundle.expected_files==44 and .gooo.repository=="kimjooyoon/meta-ontology-go" and
  .gooo.tag=="v0.2.0-dev" and .subject.path=="examples/test-receipt-reuse/main.gooo" and
  (.baseline.result_sha256|type)=="string" and (.baseline.semantic_hash|type)=="string" and
  .baseline.decision=="PASS"
' "$lock" >/dev/null 2>&1; then lock_ok=true; fi
expected_result_digest=$(json_value '.baseline.result_sha256 // "MISSING"' "$lock" MISSING)
expected_semantic_hash=$(json_value '.baseline.semantic_hash // "MISSING"' "$lock" MISSING)
expected_toolchain_digest=$(json_value '.gooo.observed_binary_sha256 // "MISSING"' "$lock" MISSING)

input_schema_ok=false
input_plan_ok=false
if jq -e --arg subject "$subject_sha" '
  .schema=="gooo/workgraph/selective-ci-work-selection-input/v1" and .subject_sha==$subject and
  (.current_scope|type)=="object" and (.tests|type)=="array" and (.tests|length)==1 and
  .tests[0].id=="released-gooo-semantic-test" and .tests[0].required==true and
  (.tests[0].scope|type)=="object" and .tests[0].scope==.current_scope
' "$input" >/dev/null 2>&1; then input_schema_ok=true; fi
if jq -e '
  (.current_scope.input_digest|type)=="string" and (.current_scope.toolchain_digest|type)=="string" and
  (.current_scope.scenario_digest|type)=="string" and (.current_scope.files|type)=="array" and
  (.current_scope.toolchain|type)=="object" and (.current_scope.command|type)=="array"
' "$input" >/dev/null 2>&1; then input_plan_ok=true; fi
input_ok=false
test "$input_schema_ok" = true && test "$input_plan_ok" = true && input_ok=true

current_input_digest=$(json_value '.current_scope.input_digest // "MISSING"' "$input" MISSING)
current_toolchain_digest=$(json_value '.current_scope.toolchain_digest // "MISSING"' "$input" MISSING)
current_scenario_digest=$(json_value '.current_scope.scenario_digest // "MISSING"' "$input" MISSING)
runtime_scenario_digest=$(json_value '.scenario.digest // "MISSING"' "$runtime" MISSING)

prior_present=false
prior_schema_ok=false
prior_decision=MISSING
prior_semantic_hash=MISSING
prior_result_digest=MISSING
prior_test_executions=UNKNOWN
prior_digest=MISSING
if test -f "$prior_receipt"; then
  prior_present=true
  prior_digest=$(digest_or_missing "$prior_receipt")
  if jq -e '.schema=="gooo/evidence-generator/test-receipt/v1"' "$prior_receipt" >/dev/null 2>&1; then prior_schema_ok=true; fi
  prior_decision=$(json_value '.result.decision // "MISSING"' "$prior_receipt" MISSING)
  prior_semantic_hash=$(json_value '.result.semantic_hash // "MISSING"' "$prior_receipt" MISSING)
  prior_result_digest=$(json_value '.result.output_sha256 // "MISSING"' "$prior_receipt" MISSING)
  prior_test_executions=$(json_value 'if (.execution.test_executions|type)=="number" then .execution.test_executions else "UNKNOWN" end' "$prior_receipt" UNKNOWN)
fi

execution_present=false
execution_schema_ok=false
execution_scope_present=false
execution_prior_digest=MISSING
execution_decision=MISSING
execution_semantic_hash=MISSING
execution_result_digest=MISSING
execution_tests=UNKNOWN
execution_authority_writes=UNKNOWN
execution_authority_local_tests=UNKNOWN
execution_authority_consumer_tests=UNKNOWN
execution_authority_cross_project_gates=UNKNOWN
if test -f "$execution_receipt"; then
  execution_present=true
  if jq -e '.schema=="gooo/workgraph/actual-test-execution-receipt/v1"' "$execution_receipt" >/dev/null 2>&1; then execution_schema_ok=true; fi
  if jq -e '
    (.scope|type)=="object" and (.scope.input_digest|type)=="string" and
    (.scope.toolchain_digest|type)=="string" and (.scope.scenario_digest|type)=="string" and
    (.scope.files|type)=="array" and (.scope.toolchain|type)=="object" and (.scope.command|type)=="array"
  ' "$execution_receipt" >/dev/null 2>&1; then execution_scope_present=true; fi
  execution_prior_digest=$(json_value '.prior_receipt.sha256 // "MISSING"' "$execution_receipt" MISSING)
  execution_decision=$(json_value '.result.decision // "MISSING"' "$execution_receipt" MISSING)
  execution_semantic_hash=$(json_value '.result.semantic_hash // "MISSING"' "$execution_receipt" MISSING)
  execution_result_digest=$(json_value '.result.output_sha256 // "MISSING"' "$execution_receipt" MISSING)
  execution_tests=$(json_value 'if (.execution.test_executions|type)=="number" then .execution.test_executions else "UNKNOWN" end' "$execution_receipt" UNKNOWN)
  execution_authority_writes=$(json_value 'if (.authority.repository_writes|type)=="number" then .authority.repository_writes else "UNKNOWN" end' "$execution_receipt" UNKNOWN)
  execution_authority_local_tests=$(json_value 'if (.authority.local_test_executions|type)=="number" then .authority.local_test_executions else "UNKNOWN" end' "$execution_receipt" UNKNOWN)
  execution_authority_consumer_tests=$(json_value 'if (.authority.consumer_test_executions|type)=="number" then .authority.consumer_test_executions else "UNKNOWN" end' "$execution_receipt" UNKNOWN)
  execution_authority_cross_project_gates=$(json_value 'if (.authority.cross_project_required_gates|type)=="number" then .authority.cross_project_required_gates else "UNKNOWN" end' "$execution_receipt" UNKNOWN)
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

actual_result_ok=false
if test "$result_present" = true; then
  if jq -e --arg semantic "$expected_semantic_hash" --arg source "$source_file" '
    .schema_version=="gooo/diagnostics/v1" and .command=="check" and .status=="ok" and
    .diagnostics==[] and .semantic_hash==$semantic and (.file==$source or .file=="examples/test-receipt-reuse/main.gooo")
  ' "$result" >/dev/null 2>&1 && test "$result_digest" = "$expected_result_digest"; then actual_result_ok=true; fi
fi

prior_receipt_ok=false
if test "$prior_present" = true && test "$prior_schema_ok" = true; then
  if jq -e --arg digest "$expected_result_digest" --arg semantic "$expected_semantic_hash" \
    --arg source "$source_digest" --arg toolchain "$expected_toolchain_digest" '
    .execution.test_executions==1 and .authority.repository_writes==0 and
    .authority.source_mutations==0 and .authority.local_test_executions==0 and
    .result.decision=="PASS" and .result.status=="ok" and .result.exit_code==0 and
    .result.output_sha256==$digest and .result.semantic_hash==$semantic and
    .scope.files==[{path:"examples/test-receipt-reuse/main.gooo",sha256:$source}] and
    .scope.toolchain.binary_sha256==$toolchain
  ' "$prior_receipt" >/dev/null 2>&1; then prior_receipt_ok=true; fi
fi

execution_result_binding_ok=false
if test "$execution_present" = true && test "$execution_schema_ok" = true && test "$result_present" = true; then
  if jq -e --arg digest "$result_digest" --arg semantic "$result_semantic_hash" '
    .result.status=="ok" and .result.exit_code==0 and .result.output_sha256==$digest and
    .result.semantic_hash==$semantic and .execution.test_executions==1
  ' "$execution_receipt" >/dev/null 2>&1; then execution_result_binding_ok=true; fi
fi

runtime_writes=$(json_value 'if (.authority.repository_writes|type)=="number" then .authority.repository_writes elif (.repository.writes|type)=="number" then .repository.writes else "UNKNOWN" end' "$runtime" UNKNOWN)
runtime_local_tests=$(json_value 'if (.authority.local_test_executions|type)=="number" then .authority.local_test_executions elif (.executions.local_test|type)=="number" then .executions.local_test else "UNKNOWN" end' "$runtime" UNKNOWN)
consumer_tests=$(json_value 'if (.authority.consumer_test_executions|type)=="number" then .authority.consumer_test_executions elif (.executions.consumer_test_executions|type)=="number" then .executions.consumer_test_executions else "UNKNOWN" end' "$runtime" UNKNOWN)
runtime_cross_project_gates=$(json_value 'if (.authority.cross_project_required_gates|type)=="number" then .authority.cross_project_required_gates else "UNKNOWN" end' "$runtime" UNKNOWN)
test_wall_ms=$(json_value '.performance.test_wall_ms // "UNKNOWN"' "$runtime" UNKNOWN)
test_peak_rss_kib=$(json_value '.performance.test_peak_rss_kib // "UNKNOWN"' "$runtime" UNKNOWN)
evaluator_wall_ms=$(json_value '.performance.evaluator_wall_ms // "UNKNOWN"' "$runtime" UNKNOWN)
evaluator_peak_rss_kib=$(json_value '.performance.evaluator_peak_rss_kib // "UNKNOWN"' "$runtime" UNKNOWN)
go_required=$(json_value '.toolchain.go_required // "UNKNOWN"' "$runtime" UNKNOWN)
reported_cross_project_gates=$runtime_cross_project_gates
if test "$execution_authority_cross_project_gates" != UNKNOWN && { test "$reported_cross_project_gates" = UNKNOWN || test "$execution_authority_cross_project_gates" -gt "$reported_cross_project_gates"; }; then
  reported_cross_project_gates=$execution_authority_cross_project_gates
fi

input_digest_match=false
toolchain_digest_match=false
scenario_digest_match=false
scope_match=false
if test "$input_ok" = true && test "$execution_scope_present" = true; then
  if jq -e --slurpfile receipt "$execution_receipt" '
    .current_scope.input_digest==$receipt[0].scope.input_digest and .current_scope.files==$receipt[0].scope.files
  ' "$input" >/dev/null 2>&1; then input_digest_match=true; fi
  if jq -e --slurpfile receipt "$execution_receipt" '
    .current_scope.toolchain_digest==$receipt[0].scope.toolchain_digest and .current_scope.toolchain==$receipt[0].scope.toolchain
  ' "$input" >/dev/null 2>&1; then toolchain_digest_match=true; fi
  if jq -e --slurpfile receipt "$execution_receipt" '
    .current_scope.scenario_digest==$receipt[0].scope.scenario_digest
  ' "$input" >/dev/null 2>&1; then scenario_digest_match=true; fi
  if jq -e --slurpfile receipt "$execution_receipt" '.current_scope==$receipt[0].scope' "$input" >/dev/null 2>&1; then scope_match=true; fi
fi

input_digest_valid=false
if test "$input_ok" = true; then
  if jq -e --arg source "$source_digest" '.current_scope.input_digest==$source and .current_scope.files==[{path:"examples/test-receipt-reuse/main.gooo",sha256:$source}]' "$input" >/dev/null 2>&1; then input_digest_valid=true; fi
fi
toolchain_digest_valid=false
if test "$input_ok" = true && test "$lock_ok" = true; then
  if jq -e --arg digest "$expected_toolchain_digest" '.current_scope.toolchain_digest==$digest and .current_scope.toolchain.binary_sha256==$digest' "$input" >/dev/null 2>&1; then toolchain_digest_valid=true; fi
fi
scenario_digest_valid=false
if test "$input_ok" = true && test "$runtime_scenario_digest" != MISSING && test "$current_scenario_digest" = "$runtime_scenario_digest"; then scenario_digest_valid=true; fi

authority_clean=false
if test "$runtime_writes" = 0 && test "$runtime_local_tests" = 0 && test "$consumer_tests" = 0 && test "$runtime_cross_project_gates" = 0; then authority_clean=true; fi
if test "$execution_present" = true && { test "$execution_authority_writes" != 0 || test "$execution_authority_local_tests" != 0 || test "$execution_authority_consumer_tests" != 0 || test "$execution_authority_cross_project_gates" != 0; }; then authority_clean=false; fi

known_contradiction=false
unknown_evidence=false
if test "$prior_present" = true && test "$prior_receipt_ok" = false; then known_contradiction=true; fi
if test "$execution_present" = true && test "$execution_schema_ok" = false; then known_contradiction=true; fi
if test "$execution_present" = true && test "$result_present" = true && test "$actual_result_ok" = false; then known_contradiction=true; fi
if test "$execution_present" = true && test "$execution_result_binding_ok" = false && test "$result_present" = true; then known_contradiction=true; fi
if test "$execution_present" = true && test "$execution_decision" != PASS && test "$execution_decision" != UNKNOWN && test "$execution_decision" != MISSING; then known_contradiction=true; fi
if test "$execution_present" = true && test "$execution_semantic_hash" != MISSING && test "$execution_semantic_hash" != "$expected_semantic_hash"; then known_contradiction=true; fi
if test "$execution_present" = true && test "$prior_present" = true && test "$execution_prior_digest" != "$prior_digest"; then known_contradiction=true; fi
if test "$execution_present" = true && test "$execution_scope_present" = true && { test "$input_digest_match" = false || test "$toolchain_digest_match" = false || test "$scenario_digest_match" = false; }; then known_contradiction=true; fi
if test "$execution_present" = true && { test "$execution_authority_writes" != 0 && test "$execution_authority_writes" != UNKNOWN || test "$execution_authority_local_tests" != 0 && test "$execution_authority_local_tests" != UNKNOWN || test "$execution_authority_consumer_tests" != 0 && test "$execution_authority_consumer_tests" != UNKNOWN || test "$execution_authority_cross_project_gates" != 0 && test "$execution_authority_cross_project_gates" != UNKNOWN; }; then known_contradiction=true; fi
if test "$authority_clean" = false && test "$runtime_writes" != UNKNOWN; then known_contradiction=true; fi
if test "$execution_present" = false; then unknown_evidence=true; fi
if test "$execution_present" = true && test "$execution_schema_ok" = true && test "$execution_scope_present" = false; then unknown_evidence=true; fi
if test "$execution_present" = true && { test "$execution_decision" = UNKNOWN || test "$execution_decision" = MISSING; }; then unknown_evidence=true; fi
if test "$execution_present" = true && test "$result_present" = false; then unknown_evidence=true; fi
if test "$execution_present" = true && test "$execution_semantic_hash" = MISSING; then unknown_evidence=true; fi
if test "$runtime_scenario_digest" = MISSING; then unknown_evidence=true; fi

selection_state=UNKNOWN
if test "$input_ok" = true && test "$input_digest_valid" = true && test "$toolchain_digest_valid" = true &&
   test "$scenario_digest_valid" = true && test "$input_digest_match" = true &&
   test "$toolchain_digest_match" = true && test "$scenario_digest_match" = true &&
   test "$scope_match" = true && test "$prior_receipt_ok" = true &&
   test "$execution_prior_digest" = "$prior_digest" &&
   test "$execution_present" = true && test "$execution_schema_ok" = true &&
   test "$execution_result_binding_ok" = true && test "$actual_result_ok" = true &&
   test "$execution_decision" = PASS && test "$execution_semantic_hash" = "$expected_semantic_hash" &&
   test "$authority_clean" = true; then
  selection_state=CLOSED
elif test "$known_contradiction" = true || test "$input_digest_valid" = false && test "$input_ok" = true || test "$toolchain_digest_valid" = false && test "$input_ok" = true; then
  selection_state=REFUTED
fi

selection_action=RERUN_REQUIRED
selection_reason=ACTUAL_EXECUTION_RECEIPT_MISSING
if test "$selection_state" = CLOSED; then
  selection_action=REUSE
  selection_reason=ALREADY_TESTED_INPUT_TOOLCHAIN_AND_SCENARIO_EXACT
elif test "$authority_clean" = false && test "$runtime_writes" != UNKNOWN; then
  selection_reason=EXECUTION_RECEIPT_AUTHORITY_ESCALATED
elif test "$execution_semantic_hash" != MISSING && test "$execution_semantic_hash" != "$expected_semantic_hash"; then
  selection_reason=DIGEST_VALID_SEMANTIC_LAUNDERING
elif test "$input_digest_valid" = false && test "$input_ok" = true || test "$input_digest_match" = false && test "$execution_scope_present" = true; then
  selection_reason=IMMUTABLE_INPUT_DIGEST_MISMATCH
elif test "$toolchain_digest_valid" = false && test "$input_ok" = true || test "$toolchain_digest_match" = false && test "$execution_scope_present" = true; then
  selection_reason=TOOLCHAIN_DIGEST_MISMATCH
elif test "$scenario_digest_match" = false && test "$execution_scope_present" = true; then
  selection_reason=SCENARIO_DIGEST_MISMATCH
elif test "$execution_decision" = UNKNOWN || test "$execution_decision" = MISSING; then
  selection_reason=UNKNOWN_RECEIPT_DECISION
elif test "$execution_present" = true && test "$actual_result_ok" = false; then
  selection_reason=ACTUAL_TEST_RESULT_CONTRADICTION
fi

input_state=UNKNOWN
if test "$input_schema_ok" = false; then input_state=REFUTED
elif test "$current_input_digest" != MISSING && test "$input_digest_valid" = false; then input_state=REFUTED
elif test "$input_digest_valid" = true; then input_state=CLOSED
fi
toolchain_state=UNKNOWN
if test "$lock_ok" = false; then toolchain_state=REFUTED
elif test "$current_toolchain_digest" != MISSING && test "$toolchain_digest_valid" = false; then toolchain_state=REFUTED
elif test "$toolchain_digest_valid" = true; then toolchain_state=CLOSED
fi
scenario_state=UNKNOWN
if test "$scenario_digest_valid" = true; then scenario_state=CLOSED; fi
if test "$input_ok" = true && test "$current_scenario_digest" != MISSING && test "$runtime_scenario_digest" != MISSING && test "$current_scenario_digest" != "$runtime_scenario_digest"; then scenario_state=REFUTED; fi
planned_state=UNKNOWN
if test "$input_state" = REFUTED || test "$toolchain_state" = REFUTED; then planned_state=REFUTED
elif test "$input_state" = CLOSED && test "$toolchain_state" = CLOSED && test "$scenario_state" = CLOSED; then planned_state=CLOSED
fi
executed_state=UNKNOWN
if test "$execution_present" = true; then
  if test "$execution_schema_ok" = false || test "$execution_result_binding_ok" = false && test "$result_present" = true; then executed_state=REFUTED
  elif test "$execution_tests" = 1 && test "$execution_result_binding_ok" = true; then executed_state=CLOSED
  fi
fi
reuse_state=UNKNOWN
if test "$selection_state" = CLOSED; then reuse_state=CLOSED
elif test "$selection_state" = REFUTED; then reuse_state=REFUTED
fi
invalidated_state=UNKNOWN
if test "$selection_state" = CLOSED; then invalidated_state=CLOSED
elif test "$known_contradiction" = true; then invalidated_state=CLOSED
fi
required_state=UNKNOWN
if test "$input_ok" = true && { test "$selection_state" = CLOSED || test "$selection_state" = REFUTED; }; then required_state=CLOSED; fi
unknown_frontier_state=CLOSED
{ test "$selection_state" = UNKNOWN || test "$unknown_evidence" = true; } && unknown_frontier_state=UNKNOWN
meta_state=REFUTED
if test "$denominator_ok" = true && jq -e --argjson activities "$activities" '
  .schema_version=="gooo-graph/v1" and .source_digest!=null and .ir.status=="available" and
  ([.nodes[]|select(.kind=="Activity")|.name]|sort)==($activities|sort) and
  ([.nodes[]|select(.kind=="Activity")]|length)==12
' "$graph" >/dev/null 2>&1 && jq -e --argjson activities "$activities" '
  .schema=="gooo/workgraph/selective-ci-activity-resolution/v1" and
  ([.entries[].activity]|sort)==($activities|sort) and ([.entries[]]|length)==12 and
  all(.entries[];.selector.name==.activity and .receipt.decision=="CLOSED" and .receipt.occurrences==1)
' "$resolution" >/dev/null 2>&1; then meta_state=CLOSED; fi
authority_state=UNKNOWN
if test "$runtime_writes" != UNKNOWN && test "$runtime_local_tests" != UNKNOWN && test "$consumer_tests" != UNKNOWN && test "$runtime_cross_project_gates" != UNKNOWN; then
  if test "$authority_clean" = true; then authority_state=CLOSED; else authority_state=REFUTED; fi
fi

facts='{}'
set_fact() {
  local activity=$1 state=$2
  local reason=
  if test "$#" -ge 3; then reason=$3; fi
  facts=$(jq -c --arg activity "$activity" --arg state "$state" --arg reason "$reason" \
    '. + {($activity):({state:$state} + (if $reason=="" then {} else {reason:$reason} end))}' <<<"$facts")
}
set_fact VerifyImmutableInputDigest "$input_state" "$(test "$input_state" = CLOSED && echo || echo IMMUTABLE_INPUT_DIGEST_MISMATCH)"
set_fact VerifyToolchainDigest "$toolchain_state" "$(test "$toolchain_state" = CLOSED && echo || echo TOOLCHAIN_DIGEST_MISMATCH)"
set_fact VerifyScenarioDigest "$scenario_state" "$(test "$scenario_state" = CLOSED && echo || echo SCENARIO_DIGEST_NOT_OBSERVED)"
set_fact PlannedTest "$planned_state" "$(test "$planned_state" = CLOSED && echo || echo TEST_PLAN_NOT_OBSERVED)"
if test "$executed_state" = UNKNOWN && test "$execution_present" = false; then
  set_fact ExecutedTest UNKNOWN ACTUAL_TEST_EXECUTION_NOT_OBSERVED
else
  set_fact ExecutedTest "$executed_state" "$(test "$executed_state" = CLOSED && echo || echo ACTUAL_TEST_EXECUTION_CONTRADICTED)"
fi
set_fact ReusedPriorReceipt "$reuse_state" "$selection_reason"
set_fact InvalidatedReceipt "$invalidated_state" "$(test "$invalidated_state" = CLOSED && echo || echo RECEIPT_INVALIDATION_NOT_DECIDABLE)"
set_fact RequiredWork "$required_state" "$(test "$required_state" = CLOSED && echo || echo REQUIRED_WORK_BOUNDARY_UNKNOWN)"
if test "$unknown_frontier_state" = UNKNOWN; then set_fact UnknownCausalFrontier UNKNOWN UNKNOWN_CAUSAL_FRONTIER_REQUIRED; else set_fact UnknownCausalFrontier CLOSED; fi
set_fact BindActualReceiptActivities "$meta_state" "$(test "$meta_state" = CLOSED && echo || echo ACTUAL_RECEIPT_ACTIVITY_BINDING_MISMATCH)"
set_fact VerifyExecutionReceiptAuthority "$authority_state" "$(test "$authority_state" = CLOSED && echo || echo EXECUTION_RECEIPT_AUTHORITY_ESCALATED)"
set_fact PublishAlreadyTestedReport CLOSED

tests_planned=UNKNOWN
if test "$input_ok" = true; then tests_planned=$(jq -r '.tests|length' "$input"); fi
tests_executed=$execution_tests
tests_reused=UNKNOWN
tests_invalidated=UNKNOWN
tests_required=UNKNOWN
if test "$input_ok" = true; then
  if test "$selection_state" = CLOSED; then tests_reused=1; tests_invalidated=0; tests_required=0
  elif test "$selection_state" = REFUTED; then tests_reused=0; tests_invalidated=1; tests_required=1
  else tests_reused=0; tests_required=1
  fi
fi
producer_observed=$prior_test_executions

graph_source_digest=$(json_value '.source_digest // "MISSING"' "$graph" MISSING)
graph_semantic_digest=$(json_value '.ir.semantic_digest // "MISSING"' "$graph" MISSING)
resolution_source_digest=$(json_value '.source.source_digest // "MISSING"' "$resolution" MISSING)
resolution_semantic_digest=$(json_value '.source.semantic_digest // "MISSING"' "$resolution" MISSING)
graph_activities=$(json_value '[.nodes[]|select(.kind=="Activity")|.name] | sort' "$graph" '[]')
resolution_activities=$(json_value '[.entries[].activity] | sort' "$resolution" '[]')

jq -S -n \
  --slurpfile denominator "$denominator" --slurpfile lock "$lock" --slurpfile input "$input" --slurpfile runtime "$runtime" \
  --argjson facts "$facts" --argjson activities "$activities" --argjson graph_activities "$graph_activities" --argjson resolution_activities "$resolution_activities" \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" --arg source_digest "$source_digest" --arg meta_source_digest "$meta_source_digest" \
  --arg graph_source_digest "$graph_source_digest" --arg graph_semantic_digest "$graph_semantic_digest" --arg resolution_source_digest "$resolution_source_digest" --arg resolution_semantic_digest "$resolution_semantic_digest" \
  --arg selection_action "$selection_action" --arg selection_state "$selection_state" --arg selection_reason "$selection_reason" \
  --arg current_input_digest "$current_input_digest" --arg receipt_input_digest "$(json_value '.scope.input_digest // "MISSING"' "$execution_receipt" MISSING)" \
  --arg current_toolchain_digest "$current_toolchain_digest" --arg receipt_toolchain_digest "$(json_value '.scope.toolchain_digest // "MISSING"' "$execution_receipt" MISSING)" \
  --arg current_scenario_digest "$current_scenario_digest" --arg receipt_scenario_digest "$(json_value '.scope.scenario_digest // "MISSING"' "$execution_receipt" MISSING)" \
  --arg prior_digest "$prior_digest" --arg execution_prior_digest "$execution_prior_digest" --arg prior_decision "$prior_decision" \
  --arg prior_semantic_hash "$prior_semantic_hash" --arg prior_result_digest "$prior_result_digest" --arg execution_decision "$execution_decision" \
  --arg execution_semantic_hash "$execution_semantic_hash" --arg execution_result_digest "$execution_result_digest" --arg result_digest "$result_digest" \
  --arg result_semantic_hash "$result_semantic_hash" --arg result_status "$result_status" --arg result_diagnostics "$result_diagnostics" \
  --arg prior_test_executions "$prior_test_executions" --arg tests_executed "$tests_executed" --arg tests_planned "$tests_planned" \
  --arg tests_reused "$tests_reused" --arg tests_invalidated "$tests_invalidated" --arg tests_required "$tests_required" --arg producer_observed "$producer_observed" \
  --arg runtime_writes "$runtime_writes" --arg runtime_local_tests "$runtime_local_tests" --arg consumer_tests "$consumer_tests" --arg runtime_cross_project_gates "$runtime_cross_project_gates" \
  --arg reported_cross_project_gates "$reported_cross_project_gates" \
  --arg execution_authority_writes "$execution_authority_writes" --arg execution_authority_local_tests "$execution_authority_local_tests" --arg execution_authority_consumer_tests "$execution_authority_consumer_tests" --arg execution_authority_cross_project_gates "$execution_authority_cross_project_gates" \
  --arg test_wall_ms "$test_wall_ms" --arg test_peak_rss_kib "$test_peak_rss_kib" --arg evaluator_wall_ms "$evaluator_wall_ms" --arg evaluator_peak_rss_kib "$evaluator_peak_rss_kib" --arg go_required "$go_required" \
  --argjson denominator_ok "$denominator_ok" --argjson lock_ok "$lock_ok" --argjson input_ok "$input_ok" --argjson prior_present "$prior_present" \
  --argjson prior_schema_ok "$prior_schema_ok" --argjson prior_receipt_ok "$prior_receipt_ok" --argjson execution_present "$execution_present" --argjson execution_schema_ok "$execution_schema_ok" \
  --argjson execution_scope_present "$execution_scope_present" --argjson execution_result_binding_ok "$execution_result_binding_ok" --argjson result_present "$result_present" --argjson actual_result_ok "$actual_result_ok" \
  --argjson input_digest_valid "$input_digest_valid" --argjson toolchain_digest_valid "$toolchain_digest_valid" --argjson scenario_digest_valid "$scenario_digest_valid" \
  --argjson input_digest_match "$input_digest_match" --argjson toolchain_digest_match "$toolchain_digest_match" --argjson scenario_digest_match "$scenario_digest_match" --argjson scope_match "$scope_match" \
  --argjson authority_clean "$authority_clean" --argjson known_contradiction "$known_contradiction" --argjson unknown_evidence "$unknown_evidence" \
  '
  def typed($value): if $value=="UNKNOWN" or $value=="MISSING" then "UNKNOWN" else ($value|tonumber) end;
  def field($cell; $direct; $decisions):
    ([$cell.depends_on[]? as $dependency | $decisions[$dependency]]) as $dependencies |
    if $direct.state=="REFUTED" then
      {state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:($direct.reason // $cell.refuted_reason),unknown_class:null,next_operation:$cell.next_operation,blocked_by:[]}
    elif $direct.state=="UNKNOWN" then
      {state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:($direct.reason // $cell.unknown_reason),unknown_class:"DIRECT_MISSING",next_operation:$cell.next_operation,blocked_by:[]}
    elif any($dependencies[];.state=="REFUTED") then
      {state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_REFUTED",unknown_class:null,next_operation:"RESOLVE_REFUTED_PREDECESSORS",blocked_by:[$dependencies[]|select(.state=="REFUTED")|.cell_id]}
    elif any($dependencies[];.state=="UNKNOWN") then
      {state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_BLOCKED",unknown_class:"DEPENDENCY_BLOCKED",next_operation:"RESOLVE_UNKNOWN_PREDECESSORS",blocked_by:[$dependencies[]|select(.state=="UNKNOWN")|.cell_id]}
    else
      {state:"CLOSED",stage:null,step:null,reason:$cell.closed_reason,unknown_class:null,next_operation:"NONE",blocked_by:[]}
    end;
  (reduce $denominator[0].cells[] as $cell ({cells:[],decisions:{}};
    . as $acc | field($cell; ($facts[$cell.activity] // {state:"UNSET"}); $acc.decisions) as $decision |
    .cells += [$cell + $decision + {cell_id:$cell.id}] | .decisions[$cell.id]=($decision + {cell_id:$cell.id})
  )) as $evaluation |
  ([$evaluation.cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$evaluation.cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$evaluation.cells[]|select(.unknown_class=="DIRECT_MISSING")]|length) as $direct_missing |
  ([$evaluation.cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length) as $dependency_blocked |
  ([$evaluation.cells[]|select(.state=="REFUTED")][0] // null) as $first_refuted |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")][0] // null) as $first_unknown |
  {
    schema:"gooo/workgraph/selective-ci-work-selection-report/v2",
    scenario:$scenario, subject_sha:$subject_sha,
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "SELECTION_EVIDENCE_UNKNOWN" else "ALREADY_TESTED_REUSE_READY" end),
    summary:{total:12,closed:$closed,unknown:$unknown,refuted:$refuted,direct_missing:$direct_missing,dependency_blocked:$dependency_blocked},
    selection:{state:(if $selection_state=="CLOSED" then "CLOSED" elif $selection_state=="REFUTED" then "REFUTED" else "UNKNOWN" end),action:$selection_action,reason:$selection_reason,tests:[{id:"released-gooo-semantic-test",action:$selection_action,scope_match:$scope_match}]},
    metrics:{tests_planned:typed($tests_planned),tests_executed:typed($tests_executed),tests_reused:typed($tests_reused),tests_invalidated:typed($tests_invalidated),tests_required_to_execute:typed($tests_required),producer_test_executions_observed:typed($producer_observed),consumer_test_executions:typed($consumer_tests),saved_test_ms:"UNKNOWN"},
    performance:{test_wall_ms:typed($test_wall_ms),test_peak_rss_kib:typed($test_peak_rss_kib),evaluator_wall_ms:typed($evaluator_wall_ms),evaluator_peak_rss_kib:typed($evaluator_peak_rss_kib)},
    release:{producer:$lock[0].producer,gooo:$lock[0].gooo,lock_verified:$lock_ok},
    receipt:{prior:{present:$prior_present,schema_verified:$prior_schema_ok,sha256:$prior_digest,decision:$prior_decision,semantic_hash:$prior_semantic_hash,result_digest:$prior_result_digest,executions:typed($prior_test_executions),verified:$prior_receipt_ok},actual:{present:$execution_present,schema_verified:$execution_schema_ok,prior_receipt_sha256:$execution_prior_digest,decision:$execution_decision,semantic_hash:$execution_semantic_hash,result_digest:$execution_result_digest,executions:typed($tests_executed),result_binding_verified:$execution_result_binding_ok}},
    digests:{immutable_input:{current:$current_input_digest,receipt:$receipt_input_digest,match:$input_digest_match,verified:$input_digest_valid},toolchain:{current:$current_toolchain_digest,receipt:$receipt_toolchain_digest,match:$toolchain_digest_match,verified:$toolchain_digest_valid},scenario:{current:$current_scenario_digest,receipt:$receipt_scenario_digest,match:$scenario_digest_match,verified:$scenario_digest_valid},scope_exact_match:$scope_match},
    result:{present:$result_present,digest:$result_digest,semantic_hash:$result_semantic_hash,status:$result_status,diagnostics:typed($result_diagnostics),verified:$actual_result_ok},
    meta_binding:{source_file:"examples/selective-ci-work-selection/main.gooo",source_digest:$meta_source_digest,semantic_digest:$graph_semantic_digest,activities:$activities,graph:{source_digest:$graph_source_digest,semantic_digest:$graph_semantic_digest,activity_names:$graph_activities},resolution:{source_digest:$resolution_source_digest,semantic_digest:$resolution_semantic_digest,activity_names:$resolution_activities},activity_links:([$denominator[0].cells|to_entries[]|{cell_id:.value.id,activity:.value.activity,stage:.value.stage,step:.value.step,ci_report_pointer:("/cells/"+(.key|tostring)+"/state")}]),verified:($denominator_ok and $graph_source_digest==$meta_source_digest and $graph_activities==$activities and $resolution_activities==$activities)},
    authority:{application_root:"CALLER_OWNED_TEMP_ONLY",repository_writes:typed($runtime_writes),local_test_executions:typed($runtime_local_tests),consumer_test_executions:typed($consumer_tests),cross_project_required_gates:typed($reported_cross_project_gates),execution_receipt:{repository_writes:typed($execution_authority_writes),local_test_executions:typed($execution_authority_local_tests),consumer_test_executions:typed($execution_authority_consumer_tests),cross_project_required_gates:typed($execution_authority_cross_project_gates)}},
    toolchain:{go_required:$go_required},
    checks:{denominator:$denominator_ok,lock:$lock_ok,input:$input_ok,prior_receipt:$prior_receipt_ok,actual_receipt:($execution_present and $execution_schema_ok and $execution_result_binding_ok),actual_result:$actual_result_ok,immutable_input_digest:$input_digest_valid,toolchain_digest:$toolchain_digest_valid,scenario_digest:$scenario_digest_valid,scope_exact_match:$scope_match,authority:$authority_clean,unknown_decision:($execution_present and ($execution_decision=="UNKNOWN" or $execution_decision=="MISSING")),unknown_fields:true,refutation_precedence:true},
    decision_basis:{known_contradiction:$known_contradiction,unknown_evidence:$unknown_evidence},
    causal_frontier:{state:(if $first_refuted!=null then "REFUTED" elif $first_unknown!=null then "UNKNOWN" else "CLOSED" end),minimum:[$evaluation.cells[]|select(.state=="REFUTED" or .state=="UNKNOWN")|{cell_id,stage,step,reason,unknown_class,next_operation,blocked_by}],unknown:[$evaluation.cells[]|select(.state=="UNKNOWN")|{cell_id,stage,step,reason,unknown_class,next_operation,blocked_by}],refuted:[$evaluation.cells[]|select(.state=="REFUTED")|{cell_id,stage,step,reason,unknown_class,next_operation,blocked_by}]},
    inventory:($runtime[0].inventory // {root_readme_policy:"EXCLUDED",regular_files:"UNKNOWN",descendant_directories:"UNKNOWN",physical_lines:"UNKNOWN",go:{files:"UNKNOWN",lines:"UNKNOWN"},gooo:{files:"UNKNOWN",lines:"UNKNOWN"}}),
    artifact_links:{manifest:"manifest.json",human_dossier:"human-dossier.md",artifact_metadata:"artifact-metadata.json"},
    cells:$evaluation.cells,
    claim:(if $first_refuted!=null then {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by} elif $first_unknown!=null then {state:"UNKNOWN",stage:$first_unknown.stage,step:$first_unknown.step,reason:$first_unknown.reason,unknown_class:$first_unknown.unknown_class,next_operation:$first_unknown.next_operation,blocked_by:$first_unknown.blocked_by} else {state:"CLOSED",stage:null,step:null,reason:"ALREADY_TESTED_REUSE_BOUNDARY_CLOSED",unknown_class:null,next_operation:"EXECUTE_REQUIRED_TEST_WORK",blocked_by:[]} end)
  }
' > "$output_real/report.json"

jq -e '
  .summary.total==12 and (.summary.closed+.summary.unknown+.summary.refuted)==12 and
  ([.cells[]]|length)==12 and
  all(.cells[]; has("stage") and has("step") and has("reason") and has("unknown_class") and has("next_operation") and has("blocked_by") and
    (if .state=="UNKNOWN" then .stage!=null and .step!=null and .reason!=null and .unknown_class!=null and .next_operation!=null and .blocked_by!=null
     elif .state=="REFUTED" then .stage!=null and .step!=null and .reason!=null and .unknown_class==null and .next_operation!=null and .blocked_by!=null else true end)) and
  all([.metrics.tests_planned,.metrics.tests_executed,.metrics.tests_reused,.metrics.tests_invalidated,.metrics.tests_required_to_execute,.metrics.producer_test_executions_observed,.metrics.consumer_test_executions,.metrics.saved_test_ms][]; type=="number" or .=="UNKNOWN") and
  (.claim.state!="UNKNOWN" or (.claim.stage!=null and .claim.step!=null and .claim.reason!=null and .claim.unknown_class!=null and .claim.next_operation!=null and .claim.blocked_by!=null)) and
  (.summary.refuted==0 or .claim.state=="REFUTED")
' "$output_real/report.json" >/dev/null

jq -S --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  '{schema:"gooo/workgraph/selective-ci-work-selection/v2",subject_sha:$subject_sha,scenario:$scenario,decision:.decision,action:.selection.action,reason:.selection.reason,tests:.selection.tests,metrics:.metrics,performance:.performance,inventory:.inventory,authority:.authority,causal_frontier:.causal_frontier,artifact_links:.artifact_links,claim:.claim}' \
  "$output_real/report.json" > "$output_real/ci-work-selection.json"

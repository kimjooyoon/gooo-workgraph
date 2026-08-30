#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 9; then
  echo "usage: test-receipt-reuse-report.sh ROOT CORPUS ACQUISITION GRAPH DENOMINATOR RUNTIME OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

root=$(cd "$1" && pwd)
corpus=$2
acquisition=$3
graph=$4
denominator=$5
runtime=$6
output=$7
subject_sha=$8
scenario=$9
lock="$root/contracts/test-receipt-reuse-release-lock-v1.json"
source="$root/examples/test-receipt-reuse/main.gooo"

for required in "$acquisition" "$graph" "$denominator" "$runtime" "$lock" "$source"; do
  test -f "$required" || { echo "missing required input: $required" >&2; exit 66; }
done

jq -e '
  .schema=="gooo/workgraph/test-receipt-reuse-denominator/v1" and .target_cells==12 and
  (.cells|length)==12 and ([.cells[].id]|unique|length)==12 and
  ([.cells[].activity]|unique|length)==12 and ([.proof_totals[].total]|add)==12 and
  all(.proof_totals[];.total==4) and ([.indicator_totals[].total]|add)==12 and
  all(.indicator_totals[];.total==4)
' "$denominator" >/dev/null
jq -e '
  .schema=="gooo/workgraph/test-receipt-reuse-release-lock/v1" and
  .producer.tag=="v0.5.0-dev" and .producer.target_commit_sha=="12cd8e454c0884e05a73afd4265ec1d5ddfac102" and
  .producer.bundle.expected_files==44 and .gooo.tag=="v0.2.0-dev" and
  .subject.path=="examples/test-receipt-reuse/main.gooo"
' "$lock" >/dev/null

activities=$(jq -c '[.cells[].activity]' "$denominator")
source_digest=$(sha256sum "$source" | awk '{print $1}')
expected_source_digest=$(jq -r '.subject.sha256' "$lock")
expected_semantic_hash=$(jq -r '.baseline.semantic_hash' "$lock")
expected_result_digest=$(jq -r '.baseline.result_sha256' "$lock")
source_local_ok=false
test "$source_digest" = "$expected_source_digest" && source_local_ok=true

release_present=$(jq -r '.release.present // false' "$acquisition")
release_verified=$(jq -r '.release.verified // false' "$acquisition")
core_verified=$(jq -r '.gooo.verified // false' "$acquisition")
source_blob_verified=$(jq -r '.source_blob.verified // false' "$acquisition")
baseline_result_verified=$(jq -r '.baseline.result_verified // false' "$acquisition")
corpus_verified=$(jq -r '.corpus.verified // false' "$acquisition")

baseline_result_file="$corpus/baseline-test-result.json"
baseline_receipt_file="$corpus/baseline-test-receipt.json"
current_scope_file="$corpus/current-scope.json"
semantic_file="$corpus/semantic.json"
syntax_file="$corpus/syntax.json"
version_file="$corpus/version.json"
resolved_file="$corpus/resolved-activities.json"

baseline_result_digest=MISSING
test -f "$baseline_result_file" && baseline_result_digest=$(sha256sum "$baseline_result_file" | awk '{print $1}')
baseline_result_ok=false
if test -f "$baseline_result_file"; then
  if jq -e --arg semantic "$expected_semantic_hash" '
    .schema_version=="gooo/diagnostics/v1" and .command=="check" and .status=="ok" and
    .file=="examples/test-receipt-reuse/main.gooo" and .semantic_hash==$semantic and .diagnostics==[]
  ' "$baseline_result_file" >/dev/null 2>&1; then
    baseline_result_ok=true
  fi
fi
# The digest check is deliberately outside jq so the evaluator never trusts a receipt field as a digest.
if test "$baseline_result_digest" != "$expected_result_digest"; then baseline_result_ok=false; fi
if test "$baseline_result_verified" != true; then baseline_result_ok=false; fi

baseline_receipt_ok=false
if test -f "$baseline_receipt_file" && test "$baseline_result_ok" = true; then
  if jq -e --arg subject "$subject_sha" --arg source "$source_digest" --arg semantic "$expected_semantic_hash" --arg digest "$expected_result_digest" \
    --arg core_repo "$(jq -r '.gooo.repository' "$lock")" --arg core_tag "$(jq -r '.gooo.tag' "$lock")" \
    --arg core_commit "$(jq -r '.gooo.target_commit_sha' "$lock")" --arg observed_binary "$(jq -r '.gooo.observed_binary_sha256' "$lock")" '
    .schema=="gooo/evidence-generator/test-receipt/v1" and .producer_subject_sha==$subject and
    .execution.test_executions==1 and .authority.local_test_executions==0 and
    .authority.repository_writes==0 and .authority.source_mutations==0 and
    .result.decision=="PASS" and .result.status=="ok" and .result.exit_code==0 and
    .result.diagnostics_schema=="gooo/diagnostics/v1" and .result.output_sha256==$digest and
    .result.semantic_hash==$semantic and
    .scope.id=="gooo://test-scope/test-receipt-reuse-meta/v1" and
    .scope.command==["gooo","check","--semantic","--json","examples/test-receipt-reuse/main.gooo"] and
    .scope.files==[{path:"examples/test-receipt-reuse/main.gooo",sha256:$source}] and
    .scope.toolchain.repository==$core_repo and .scope.toolchain.tag==$core_tag and
    .scope.toolchain.target_commit_sha==$core_commit and .scope.toolchain.binary_sha256==$observed_binary
  ' "$baseline_receipt_file" >/dev/null; then baseline_receipt_ok=true; fi
fi

current_scope_ok=false
if test -f "$current_scope_file"; then
  if jq -e --arg subject "$subject_sha" --arg source "$source_digest" \
    --arg core_repo "$(jq -r '.gooo.repository' "$lock")" --arg core_tag "$(jq -r '.gooo.tag' "$lock")" \
    --arg core_commit "$(jq -r '.gooo.target_commit_sha' "$lock")" --arg observed_binary "$(jq -r '.gooo.observed_binary_sha256' "$lock")" '
    .schema=="gooo/evidence-generator/test-scope/v1" and .observer_subject_sha==$subject and
    .scope.id=="gooo://test-scope/test-receipt-reuse-meta/v1" and
    .scope.command==["gooo","check","--semantic","--json","examples/test-receipt-reuse/main.gooo"] and
    .scope.files==[{path:"examples/test-receipt-reuse/main.gooo",sha256:$source}] and
    .scope.toolchain.repository==$core_repo and .scope.toolchain.tag==$core_tag and
    .scope.toolchain.target_commit_sha==$core_commit and .scope.toolchain.binary_sha256==$observed_binary
  ' "$current_scope_file" >/dev/null; then current_scope_ok=true; fi
fi

graph_ok=false
if test -f "$graph" && test -f "$version_file" && test -f "$syntax_file" && test -f "$semantic_file" && test -f "$resolved_file"; then
  if jq -e --arg source "$source_digest" --arg semantic "$expected_semantic_hash" --argjson activities "$activities" '
    .schema_version=="gooo-graph/v1" and .source_digest==$source and
    .ir.status=="available" and .ir.semantic_digest==$semantic and
    ([.nodes[]|select(.kind=="Activity")|.name]|sort)==($activities|sort) and
    ([.nodes[]|select(.kind=="Activity")]|length)==12
  ' "$graph" >/dev/null &&
    jq -e '
      .schema_version=="gooo-version/v1" and .language=="gooo" and .version=="0.2.0-dev" and
      .semantic_ir=="semantic-ir/v1" and .semantic_check=="gooo-semantic-check/v1" and .graph=="gooo-graph/v1"
    ' "$version_file" >/dev/null &&
    jq -e '
      .schema_version=="gooo/diagnostics/v1" and .command=="check" and .status=="ok" and
      .file=="examples/test-receipt-reuse/main.gooo" and .diagnostics==[] and (has("semantic_hash")|not)
    ' "$syntax_file" >/dev/null &&
    jq -e --arg semantic "$expected_semantic_hash" '
      .schema_version=="gooo/diagnostics/v1" and .command=="check" and .status=="ok" and
      .file=="examples/test-receipt-reuse/main.gooo" and .semantic_hash==$semantic and .diagnostics==[]
    ' "$semantic_file" >/dev/null &&
    jq -e --arg source "$source_digest" --arg semantic "$expected_semantic_hash" --argjson activities "$activities" \
      --arg core_repo "$(jq -r '.gooo.repository' "$lock")" --arg core_tag "$(jq -r '.gooo.tag' "$lock")" \
      --arg core_commit "$(jq -r '.gooo.target_commit_sha' "$lock")" --arg core_binary "$(jq -r '.gooo.asset.digest' "$lock" | sed 's/^sha256://')" '
      .schema_version=="gooo-graph/v1" and .source_digest==$source and .ir.semantic_digest==$semantic and
      .activity_resolution_observation.schema=="gooo/evidence-generator/activity-resolution-observation/v1" and
      .activity_resolution_observation.summary=={closed:12,expected:12,observed:12,refuted:0,unique_selectors:12,unknown:0} and
      .activity_resolution_observation.source.file=="examples/test-receipt-reuse/main.gooo" and
      .activity_resolution_observation.source.source_digest==$source and
      .activity_resolution_observation.source.semantic_digest==$semantic and
      .activity_resolution_observation.core_release.repository==$core_repo and
      .activity_resolution_observation.core_release.tag==$core_tag and
      .activity_resolution_observation.core_release.target_commit_sha==$core_commit and
      .activity_resolution_observation.core_release.binary_sha256==$core_binary and
      ([.activity_resolution_observation.entries[].activity]|sort)==($activities|sort) and
      ([.activity_resolution_observation.entries[]]|length)==12 and
      all(.activity_resolution_observation.entries[];
        .selector.name==.activity and .receipt.decision=="CLOSED" and .receipt.occurrences==1 and
        (.receipt.matches|length)==1 and .receipt.matches[0].name==.activity and
        .receipt.subject.source_digest==$source and .receipt.subject.semantic_digest==$semantic)
    ' "$resolved_file" >/dev/null; then
    graph_ok=true
  fi
fi

expected_files=(
  authority-escalation/input-observation.json authority-escalation/manifest.json authority-escalation/report.md authority-escalation/reuse-report.json
  missing-receipt/input-observation.json missing-receipt/manifest.json missing-receipt/report.md missing-receipt/reuse-report.json
  normal-a/input-observation.json normal-a/manifest.json normal-a/report.md normal-a/reuse-report.json
  normal-b/input-observation.json normal-b/manifest.json normal-b/report.md normal-b/reuse-report.json
  refuted-over-unknown/input-observation.json refuted-over-unknown/manifest.json refuted-over-unknown/report.md refuted-over-unknown/reuse-report.json
  stale-scope/input-observation.json stale-scope/manifest.json stale-scope/report.md stale-scope/reuse-report.json
  unrecognized-decision/input-observation.json unrecognized-decision/manifest.json unrecognized-decision/report.md unrecognized-decision/reuse-report.json
  conform-authority-escalation.json conform-missing-receipt.json conform-normal-a.json conform-normal-b.json
  conform-refuted-over-unknown.json conform-stale-scope.json conform-unrecognized-decision.json
  baseline-test-receipt.json baseline-test-result.json current-scope.json graph.json resolved-activities.json runtime.json semantic.json syntax.json version.json
)
corpus_files=0
corpus_present=false
if test -d "$corpus"; then corpus_files=$(find "$corpus" -type f | wc -l | tr -d ' '); corpus_present=true; fi
corpus_names_ok=false
if test "$corpus_present" = true && test "$corpus_files" -eq 44; then
  corpus_names_ok=true
  for relative in "${expected_files[@]}"; do
    if test ! -f "$corpus/$relative"; then corpus_names_ok=false; fi
  done
fi

manifest_entries_verified=0
manifest_entries_missing=0
manifest_entries_refuted=0
verify_manifest() {
  local directory=$1
  local expected_scenario=$2
  local manifest="$corpus/$directory/manifest.json"
  if test ! -f "$manifest"; then
    manifest_entries_missing=$((manifest_entries_missing+3))
    return
  fi
  if ! jq -e --arg scenario "$expected_scenario" --arg subject "$subject_sha" '
    .schema=="gooo/evidence-generator/test-receipt-reuse-manifest/v1" and .scenario==$scenario and
    .subject_sha==$subject and .tracked_file_count==3 and
    ([.files[].path]|sort)==["input-observation.json","report.md","reuse-report.json"]
  ' "$manifest" >/dev/null 2>&1; then
    manifest_entries_refuted=$((manifest_entries_refuted+3))
    return
  fi
  while IFS=$'\t' read -r relative expected_digest expected_size; do
    local file="$corpus/$directory/$relative"
    if test ! -f "$file"; then
      manifest_entries_missing=$((manifest_entries_missing+1))
    elif test "$(sha256sum "$file"|awk '{print $1}')" != "$expected_digest" ||
         test "$(wc -c < "$file"|tr -d ' ')" -ne "$expected_size"; then
      manifest_entries_refuted=$((manifest_entries_refuted+1))
    else
      manifest_entries_verified=$((manifest_entries_verified+1))
    fi
  done < <(jq -r '.files[]|[.path,.sha256,.size_bytes]|@tsv' "$manifest")
}
if test "$corpus_present" = true; then
  verify_manifest normal-a normal
  verify_manifest normal-b normal
  verify_manifest missing-receipt missing-receipt
  verify_manifest stale-scope stale-scope
  verify_manifest refuted-over-unknown refuted-over-unknown
  verify_manifest authority-escalation authority-escalation
  verify_manifest unrecognized-decision unrecognized-decision
fi
manifest_ok=false
test "$manifest_entries_verified" -eq 21 && test "$manifest_entries_missing" -eq 0 && test "$manifest_entries_refuted" -eq 0 && manifest_ok=true

conformance_ok=false
if test "$corpus_present" = true; then
  if jq -s -e --arg subject "$subject_sha" '
    all(.[];
      .schema=="gooo/evidence-generator/test-receipt-reuse-conformance/v1" and
      .subject_sha==$subject and .decision=="CONFORMANT" and .manifest=={total:3,verified:3})
  ' "$corpus"/conform-*.json >/dev/null 2>&1; then conformance_ok=true; fi
fi

case "$scenario" in
  normal|missing-release|stale-blob|result-contradiction) scenario_directory=normal-a ; producer_scenario=normal ;;
  missing-receipt) scenario_directory=missing-receipt ; producer_scenario=missing-receipt ;;
  stale-scope) scenario_directory=stale-scope ; producer_scenario=stale-scope ;;
  refuted-over-unknown) scenario_directory=refuted-over-unknown ; producer_scenario=refuted-over-unknown ;;
  authority-escalation) scenario_directory=authority-escalation ; producer_scenario=authority-escalation ;;
  unrecognized-fixed-point) scenario_directory=unrecognized-decision ; producer_scenario=unrecognized-decision ;;
  *) echo "unknown scenario: $scenario" >&2; exit 64 ;;
esac
observation="$corpus/$scenario_directory/input-observation.json"
producer_report="$corpus/$scenario_directory/reuse-report.json"
observation_present=false
test -f "$observation" && observation_present=true

producer_report_ok=false
if test -f "$producer_report"; then
  if jq -e --arg subject "$subject_sha" --arg producer_scenario "$producer_scenario" '
    .schema=="gooo/evidence-generator/test-receipt-reuse-report/v1" and .subject_sha==$subject and
    .scenario==$producer_scenario and ([.cells[]]|length)==12 and
    all(.cells[]; has("stage") and has("step") and has("reason") and has("unknown_class") and has("next_operation") and has("blocked_by")) and
    .reuse.consumer_test_executions==0 and .authority.consumer_test_executions==0
  ' "$producer_report" >/dev/null; then producer_report_ok=true; fi
fi

obs_schema_ok=false
obs_receipt_present=false
obs_decision=MISSING
obs_scope_present=false
obs_scope_match=false
obs_semantic_hash=MISSING
obs_result_digest=MISSING
obs_producer_tests=0
obs_consumer_tests=0
obs_authority_writes=0
if test "$observation_present" = true; then
  obs_schema_ok=$(jq -r '.schema=="gooo/evidence-generator/test-receipt-observation/v1"' "$observation")
  obs_receipt_present=$(jq -r '.receipt.present // false' "$observation")
  obs_decision=$(jq -r '.receipt.decision // "MISSING"' "$observation")
  obs_scope_present=$(jq -r '.scope.present // false' "$observation")
  obs_scope_match=$(jq -r '.scope.match // false' "$observation")
  obs_semantic_hash=$(jq -r '.receipt.semantic_hash // "MISSING"' "$observation")
  obs_result_digest=$(jq -r '.result.digest // "MISSING"' "$observation")
  obs_producer_tests=$(jq -r '.producer_execution.test_executions // 0' "$observation")
  obs_consumer_tests=$(jq -r '.receipt_authority.consumer_test_executions // 0' "$observation")
  obs_authority_writes=$(jq -r '.receipt_authority.repository_writes // 0' "$observation")
fi

facts='{}'
set_fact() {
  local activity=$1 state=$2
  facts=$(jq -c --arg activity "$activity" --arg state "$state" '. + {($activity):{state:$state}}' <<<"$facts")
}
if test "$release_verified" = true && test "$core_verified" = true && test "$corpus_verified" = true; then
  set_fact ObserveReleasedTestCore CLOSED
elif test "$release_present" = false; then
  set_fact ObserveReleasedTestCore UNKNOWN
else
  set_fact ObserveReleasedTestCore REFUTED
fi
if test "$source_blob_verified" = false && test "$release_verified" = true; then
  set_fact BindTestReceiptReuseActivities REFUTED
elif test "$graph_ok" = true && test "$source_local_ok" = true; then
  set_fact BindTestReceiptReuseActivities CLOSED
else
  set_fact BindTestReceiptReuseActivities REFUTED
fi
if test "$current_scope_ok" = true; then set_fact PinTestSubjectScope CLOSED; else set_fact PinTestSubjectScope REFUTED; fi
if test "$obs_schema_ok" = true && test "$obs_receipt_present" = true && test "$obs_producer_tests" -eq 1; then
  set_fact RecordBaselineTestExecution CLOSED
else
  set_fact RecordBaselineTestExecution UNKNOWN
fi
if test "$obs_receipt_present" = true; then set_fact PublishExactTestReceipt CLOSED; fi
if test "$obs_receipt_present" = true; then
  if test "$obs_decision" = FIXED_POINT || test "$baseline_result_verified" != true || test "$obs_result_digest" != "$expected_result_digest"; then
    set_fact VerifyTestReceiptIdentity REFUTED
  elif test "$obs_semantic_hash" = MISSING; then
    set_fact VerifyTestReceiptIdentity UNKNOWN
  elif test "$obs_decision" = PASS && test "$obs_semantic_hash" = "$expected_semantic_hash" && test "$baseline_receipt_ok" = true; then
    set_fact VerifyTestReceiptIdentity CLOSED
  else
    set_fact VerifyTestReceiptIdentity REFUTED
  fi
fi
if test "$obs_scope_present" = true && test "$obs_scope_match" = false; then
  set_fact CompareTestScopeDigests REFUTED
elif test "$obs_scope_match" = true; then
  set_fact CompareTestScopeDigests CLOSED
fi
if test "$obs_authority_writes" -ne 0 || test "$obs_consumer_tests" -ne 0; then set_fact RecordReceiptReuseWithoutConsumerTest REFUTED; fi
if test "$graph_ok" = true && test "$corpus_names_ok" = true; then
  set_fact PreserveTestReceiptUnknown CLOSED
  set_fact RefuteStaleOrContradictoryReceipt CLOSED
fi

work=$(mktemp -d)
: > "$work/language-files.ndjson"
while IFS= read -r -d '' file; do
  relative=${file#"$root/"}
  lines=$(wc -l < "$file" | tr -d ' ')
  case "$file" in
    *.go) language=Go ;;
    *.gooo) language=Gooo ;;
    *) continue ;;
  esac
  jq -cn --arg path "$relative" --arg language "$language" --argjson lines "$lines" \
    '{path:$path,language:$language,physical_lines:$lines}' >> "$work/language-files.ndjson"
done < <(find "$root" -type f -not -path "$root/.git/*" \( -name '*.go' -o -name '*.gooo' \) -print0 | sort -z)
repository_files=$(find "$root" -type f -not -path "$root/.git/*" -not -path "$root/README.md" | wc -l | tr -d ' ')
descendant_directories=$(find "$root" -mindepth 1 -type d -not -path "$root/.git" -not -path "$root/.git/*" | wc -l | tr -d ' ')
physical_lines=$(find "$root" -type f -not -path "$root/.git/*" -not -path "$root/README.md" -print0 | sort -z | xargs -0 cat | wc -l | tr -d ' ')
jq -s --argjson repository_files "$repository_files" --argjson descendant_directories "$descendant_directories" --argjson physical_lines "$physical_lines" '
  . as $files | {root_readme_policy:"EXCLUDED",repository_files:$repository_files,descendant_directories:$descendant_directories,
    physical_lines:$physical_lines,
    go:{files:([$files[]|select(.language=="Go")]|length),lines:([$files[]|select(.language=="Go")|.physical_lines]|add//0)},
    gooo:{files:([$files[]|select(.language=="Gooo")]|length),lines:([$files[]|select(.language=="Gooo")|.physical_lines]|add//0)},language_files:$files}' \
  "$work/language-files.ndjson" > "$work/inventory.json"

jq -S -n \
  --slurpfile denominator "$denominator" --slurpfile lock "$lock" --slurpfile acquisition "$acquisition" \
  --slurpfile runtime "$runtime" --slurpfile observation <(if test -f "$observation"; then cat "$observation"; else echo null; fi) \
  --slurpfile inventory "$work/inventory.json" --argjson facts "$facts" --argjson activities "$activities" \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" --arg source_digest "$source_digest" \
  --argjson corpus_files "$corpus_files" --argjson manifest_entries_verified "$manifest_entries_verified" \
  --argjson manifest_entries_missing "$manifest_entries_missing" --argjson manifest_entries_refuted "$manifest_entries_refuted" \
  --argjson source_local_ok "$source_local_ok" --argjson graph_ok "$graph_ok" --argjson current_scope_ok "$current_scope_ok" \
  --argjson baseline_receipt_ok "$baseline_receipt_ok" --argjson baseline_result_ok "$baseline_result_ok" \
  --argjson corpus_names_ok "$corpus_names_ok" --argjson manifest_ok "$manifest_ok" --argjson conformance_ok "$conformance_ok" \
  --argjson producer_report_ok "$producer_report_ok" --argjson release_verified "$release_verified" --argjson core_verified "$core_verified" \
  --argjson source_blob_verified "$source_blob_verified" --argjson corpus_verified "$corpus_verified" \
  '
  (reduce $denominator[0].cells[] as $cell
    ({cells:[],decisions:{}};
      . as $acc |
      ($facts[$cell.activity] // {state:"UNSET"}) as $direct |
      ([$cell.depends_on[]? as $dependency | $acc.decisions[$dependency]]) as $dependencies |
      (if $direct.state=="REFUTED" then
        {state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:$cell.refuted_reason,unknown_class:null,next_operation:$cell.next_operation,blocked_by:[]}
       elif $direct.state=="UNKNOWN" then
        {state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:$cell.unknown_reason,unknown_class:"DIRECT_MISSING",next_operation:$cell.next_operation,blocked_by:[]}
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
  ([$evaluation.cells[]|select(.state=="REFUTED")][0] // null) as $first_refuted |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")][0] // null) as $first_unknown |
  {
    schema:"gooo/workgraph/test-receipt-reuse-report/v1",scenario:$scenario,subject_sha:$subject_sha,
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "ADOPTION_EVIDENCE_UNKNOWN" else "WORKGRAPH_TEST_RECEIPT_REUSE_ADOPTED" end),
    summary:{total:12,closed:$closed,unknown:$unknown,refuted:$refuted,direct_missing:([$evaluation.cells[]|select(.unknown_class=="DIRECT_MISSING")]|length),dependency_blocked:([$evaluation.cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length)},
    release:{producer:$lock[0].producer,gooo:$lock[0].gooo,verified:($release_verified and $core_verified),source_blob_verified:$source_blob_verified,corpus_verified:$corpus_verified},
    source:{path:$lock[0].subject.path,subject_sha:$subject_sha,local_sha256:$source_digest,locked_sha256:$lock[0].subject.sha256,immutable_api_reads:$acquisition[0].source_blob.api_reads,immutable_blob_sha:$acquisition[0].source_blob.git_blob_sha},
    receipt:{baseline_result_sha256:$lock[0].baseline.result_sha256,baseline_semantic_hash:$lock[0].baseline.semantic_hash,baseline_decision:$lock[0].baseline.decision,baseline_result_verified:$baseline_result_ok,baseline_receipt_verified:$baseline_receipt_ok,scenario_observation:($observation[0]//null)},
    artifact:{corpus_files:$corpus_files,corpus_file_total:44,manifest_entries_verified:$manifest_entries_verified,manifest_entry_total:21,manifest_entries_missing:$manifest_entries_missing,manifest_entries_refuted:$manifest_entries_refuted,manifests_verified:$manifest_ok,conformance_receipts_verified:$conformance_ok},
    adoption:{independent_released_receipt_consumers:(if $scenario=="normal" and $closed==12 then 1 else 0 end),independent_released_receipt_consumer_total:1,released_receipt_reuses:(if $scenario=="normal" and $closed==12 then 1 else 0 end),released_receipt_reuse_total:1,exact_scope_pairs:(if $scenario=="normal" and $closed==12 then 1 else 0 end),exact_scope_pair_total:1,producer_test_executions_observed:$runtime[0].executions.producer_test,consumer_producer_scope_test_executions:$runtime[0].executions.consumer_test,gooo_meta_activities:(if $graph_ok then 12 else 0 end),gooo_meta_activity_total:12},
    proofs:[$denominator[0].proof_totals[] as $proof|{choice:$proof.proof_choice,total:$proof.total,closed:([$evaluation.cells[]|select(.proof_choice==$proof.proof_choice and .state=="CLOSED")]|length)}],
    indicator_classes:[$denominator[0].indicator_totals[] as $indicator|{class:$indicator.indicator_class,total:$indicator.total,closed:([$evaluation.cells[]|select(.indicator_class==$indicator.indicator_class and .state=="CLOSED")]|length)}],
    indicators:[
      {id:"gooo.metric.workgraph-test-receipt-reuse.independent-consumers.v1",class:"OUTCOME",activity:"PublishTestReceiptReuseReport",value:(if $scenario=="normal" and $closed==12 then 1 else 0 end),total:1,unit:"consumers"},
      {id:"gooo.metric.workgraph-test-receipt-reuse.receipt-reuses.v1",class:"OUTCOME",activity:"RecordReceiptReuseWithoutConsumerTest",value:(if $scenario=="normal" and $closed==12 then 1 else 0 end),total:1,unit:"receipts"},
      {id:"gooo.metric.workgraph-test-receipt-reuse.meta-activities.v1",class:"DRIVER",activity:"BindTestReceiptReuseActivities",value:(if $graph_ok then 12 else 0 end),total:12,unit:"activities"},
      {id:"gooo.metric.workgraph-test-receipt-reuse.release-files.v1",class:"DRIVER",activity:"ObserveReleasedTestCore",value:(if $corpus_files==44 and $release_verified then 44 else 0 end),total:44,unit:"files"},
      {id:"gooo.metric.workgraph-test-receipt-reuse.consumer-tests.v1",class:"GUARDRAIL",activity:"RecordReceiptReuseWithoutConsumerTest",value:$runtime[0].executions.consumer_test,total:0,unit:"executions"}
    ],
    performance:$runtime[0].performance,inventory:$inventory[0],authority:$runtime[0].authority,
    execution:$runtime[0].executions,utility:{saved_test_ms:$runtime[0].improvement.saved_test_ms,external_utility:$runtime[0].improvement.external_user_utility,language_wide_generalization:$runtime[0].improvement.language_wide_generalization},
    checks:{source_local_sha256:$source_local_ok,graph_and_released_checks:$graph_ok,current_scope:$current_scope_ok,baseline_receipt:$baseline_receipt_ok,baseline_result:$baseline_result_ok,corpus_names:$corpus_names_ok,manifests:$manifest_ok,conformance:$conformance_ok,producer_report:$producer_report_ok},
    cells:$evaluation.cells,
    claim:(if $first_refuted!=null then {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by}
      elif $first_unknown!=null then {state:"UNKNOWN",stage:$first_unknown.stage,step:$first_unknown.step,reason:$first_unknown.reason,unknown_class:$first_unknown.unknown_class,next_operation:$first_unknown.next_operation,blocked_by:$first_unknown.blocked_by}
      else {state:"CLOSED",stage:null,step:null,reason:"WORKGRAPH_TEST_RECEIPT_REUSE_CLOSED",unknown_class:null,next_operation:"PUBLISH_WORKGRAPH_TEST_RECEIPT_REUSE_REPORT",blocked_by:[]} end)
  }
' > "$output"

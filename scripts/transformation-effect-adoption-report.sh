#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 8; then
  echo "usage: transformation-effect-adoption-report.sh ROOT PRODUCER ACQUISITION GRAPH DENOMINATOR OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

root=$(cd "$1" && pwd)
producer=$2
acquisition=$3
graph=$4
denominator=$5
output=$6
subject_sha=$7
scenario=$8
lock="$root/contracts/transformation-effect-adoption-release-lock-v1.json"
source="$root/examples/transformation-effect-adoption/main.gooo"

for required in "$acquisition" "$graph" "$denominator" "$lock" "$source"; do
  test -f "$required" || { echo "missing required input: $required" >&2; exit 66; }
done

jq -e '.schema=="gooo/workgraph/transformation-effect-adoption-denominator/v1" and .target_cells==12 and
  (.cells|length)==12 and ([.cells[].id]|unique|length)==12 and ([.cells[].activity]|unique|length)==12 and
  ([.proof_totals[].total]|add)==12 and all(.proof_totals[];.total==4) and
  ([.indicator_totals[].total]|add)==12 and all(.indicator_totals[];.total==4)' "$denominator" >/dev/null
jq -e '.schema=="gooo/workgraph/transformation-effect-adoption-release-lock/v1" and
  .producer.tag=="v0.4.0-dev" and .producer.bundle.expected_files==56 and .core_lock.tag=="v0.3.0-dev"' "$lock" >/dev/null
source_digest=$(sha256sum "$source" | awk '{print $1}')
meta_ok=false
if jq -e --arg digest "$source_digest" --slurpfile denominator "$denominator" '
  .schema_version=="gooo-graph/v1" and .source_digest==$digest and
  ([$denominator[0].cells[] as $cell |
    select(( [.nodes[]|select(.kind=="Activity" and .name==$cell.activity)] | length)==1)
  ]|length)==12 and ( [.nodes[]|select(.kind=="Activity")] | length)==12
' "$graph" >/dev/null; then meta_ok=true; fi

producer_release_ok=false
core_release_ok=false
release_artifact_ok=false
if jq -e --slurpfile lock "$lock" '
  .producer.release_verified==true and
  .producer.repository==$lock[0].producer.repository and .producer.tag==$lock[0].producer.tag and
  .producer.tag_object_sha==$lock[0].producer.tag_object_sha and
  .producer.target_commit_sha==$lock[0].producer.target_commit_sha and
  .producer.release_id==$lock[0].producer.release_id
' "$acquisition" >/dev/null; then producer_release_ok=true; fi
if jq -e --slurpfile lock "$lock" '
  .core.release_verified==true and .core.lock_path==$lock[0].core_lock.path and
  .core.schema==$lock[0].core_lock.schema and .core.tag==$lock[0].core_lock.tag
' "$acquisition" >/dev/null; then core_release_ok=true; fi
if jq -e --slurpfile lock "$lock" '
  .producer.bundle_verified==true and .producer.checksum_verified==true and
  .producer.bundle.id==$lock[0].producer.bundle.id and .producer.bundle.name==$lock[0].producer.bundle.name and
  .producer.bundle.size==$lock[0].producer.bundle.size and .producer.bundle.digest==$lock[0].producer.bundle.digest and
  .producer.checksums.id==$lock[0].producer.checksums.id and .producer.checksums.digest==$lock[0].producer.checksums.digest and
  .producer.extracted_files==$lock[0].producer.bundle.expected_files and .producer.conformance_receipts==5
' "$acquisition" >/dev/null; then release_artifact_ok=true; fi

assess_manifest() {
  local directory=$1
  local manifest="$directory/manifest.json"
  local verified=0 missing=0 refuted=0
  if test ! -f "$manifest"; then
    printf 'UNKNOWN\t0\t1\t0\n'
    return
  fi
  if ! jq -e '.schema=="gooo/evidence-generator/transformation-manifest/v1" and .tracked_file_count==8 and (.files|length)==8' "$manifest" >/dev/null 2>&1; then
    printf 'REFUTED\t0\t0\t1\n'
    return
  fi
  while IFS=$'\t' read -r relative expected_digest expected_size; do
    case "$relative" in
      /*|*..*) refuted=$((refuted+1)); continue ;;
    esac
    file="$directory/$relative"
    if test ! -f "$file"; then
      missing=$((missing+1))
    elif test "$(sha256sum "$file"|awk '{print $1}')" != "$expected_digest" ||
         test "$(wc -c < "$file"|tr -d ' ')" -ne "$expected_size"; then
      refuted=$((refuted+1))
    else
      verified=$((verified+1))
    fi
  done < <(jq -r '.files[]|[.path,.sha256,.size_bytes]|@tsv' "$manifest")
  actual=$(find "$directory" -maxdepth 1 -type f | wc -l | tr -d ' ')
  if test "$actual" -gt 9; then refuted=$((refuted+actual-9)); fi
  if test "$refuted" -gt 0; then state=REFUTED
  elif test "$missing" -gt 0; then state=UNKNOWN
  else state=CLOSED
  fi
  printf '%s\t%s\t%s\t%s\n' "$state" "$verified" "$missing" "$refuted"
}

combine_states() {
  if test "$1" = REFUTED || test "$2" = REFUTED; then echo REFUTED
  elif test "$1" = UNKNOWN || test "$2" = UNKNOWN; then echo UNKNOWN
  else echo CLOSED
  fi
}

IFS=$'\t' read -r normal_a_manifest normal_a_verified normal_a_missing normal_a_refuted < <(assess_manifest "$producer/normal-a")
IFS=$'\t' read -r normal_b_manifest normal_b_verified normal_b_missing normal_b_refuted < <(assess_manifest "$producer/normal-b")
IFS=$'\t' read -r unknown_manifest unknown_verified unknown_missing unknown_refuted < <(assess_manifest "$producer/missing-pattern")
IFS=$'\t' read -r unauthorized_manifest unauthorized_verified unauthorized_missing unauthorized_refuted < <(assess_manifest "$producer/unauthorized-operation")
IFS=$'\t' read -r mixed_manifest mixed_verified mixed_missing mixed_refuted < <(assess_manifest "$producer/refuted-over-unknown")
normal_manifest_state=$(combine_states "$normal_a_manifest" "$normal_b_manifest")
refuted_manifest_state=$(combine_states "$unauthorized_manifest" "$mixed_manifest")
manifest_verified=$((normal_a_verified+normal_b_verified+unknown_verified+unauthorized_verified+mixed_verified))
manifest_missing=$((normal_a_missing+normal_b_missing+unknown_missing+unauthorized_missing+mixed_missing))
manifest_refuted=$((normal_a_refuted+normal_b_refuted+unknown_refuted+unauthorized_refuted+mixed_refuted))

normal_replay_state=UNKNOWN
if test -d "$producer/normal-a" && test -d "$producer/normal-b"; then
  if diff -qr "$producer/normal-a" "$producer/normal-b" >/dev/null; then normal_replay_state=CLOSED; else normal_replay_state=REFUTED; fi
fi

normal_receipt="$producer/normal-a/effect-receipt.json"
unknown_receipt="$producer/missing-pattern/effect-receipt.json"
unauthorized_receipt="$producer/unauthorized-operation/effect-receipt.json"
mixed_receipt="$producer/refuted-over-unknown/effect-receipt.json"
producer_runtime="$producer/runtime.json"
target_commit=$(jq -r '.producer.target_commit_sha' "$lock")

normal_effect_state=UNKNOWN
if test -f "$normal_receipt"; then
  if jq -e --arg target "$target_commit" '
    .schema=="gooo/evidence-generator/transformation-effect-receipt/v1" and .subject_sha==$target and
    .decision=="TRANSFORMATION_EFFECT_CLOSED" and
    .process.summary=={closed:12,dependency_blocked:0,direct_missing:0,refuted:0,total:12,unknown:0} and
    .candidate_selection.state=="CLOSED" and .candidate_selection.support=={expected:4,minimum:3,observed:4,total:4} and
    .effect.before.total==12 and .effect.before.closed==11 and .effect.before.unknown==1 and .effect.before.refuted==0 and
    .effect.after.total==12 and .effect.after.closed==12 and .effect.after.unknown==0 and .effect.after.refuted==0 and
    .effect.delta=={closed:1,refuted:0,total:0,unknown:-1} and .effect.target_cell_transitions==1 and
    .effect.unrelated_cell_changes==0 and .effect.unrelated_before_digest==.effect.unrelated_after_digest and
    .effect.internal_replay_equal==true and .improvement.state=="CLOSED" and
    .improvement.exact_pairs=={observed:1,required:1} and
    .improvement.generalized_language_improvement.state=="UNKNOWN" and
    .external_utility.state=="UNKNOWN" and .external_utility.evidence==0 and
    .authority.repository_writes==0 and .authority.denominator_changes==0 and
    .authority.go_build_executions==0 and .authority.go_test_executions==0 and .authority.local_test_executions==0
  ' "$normal_receipt" >/dev/null; then normal_effect_state=CLOSED; else normal_effect_state=REFUTED; fi
fi

unknown_semantic_state=UNKNOWN
if test -f "$unknown_receipt"; then
  if jq -e '
    .decision=="INCOMPLETE" and
    .process.summary=={closed:5,dependency_blocked:6,direct_missing:1,refuted:0,total:12,unknown:7} and
    .claim.state=="UNKNOWN" and .claim.stage=="OBSERVATION" and
    .claim.step=="OBSERVE_CANDIDATE_PATTERN_SUPPORT" and
    .claim.reason=="CANDIDATE_PATTERN_OBSERVATION_MISSING" and
    .claim.unknown_class=="DIRECT_MISSING" and
    .claim.next_operation=="ADD_PINNED_PATTERN_OBSERVATION" and .claim.blocked_by==[]
  ' "$unknown_receipt" >/dev/null; then unknown_semantic_state=CLOSED; else unknown_semantic_state=REFUTED; fi
fi
unknown_evidence_state=$(combine_states "$unknown_manifest" "$unknown_semantic_state")

unauthorized_semantic=UNKNOWN
if test -f "$unauthorized_receipt"; then
  if jq -e '.decision=="FAIL_CLOSED" and .process.summary=={closed:6,dependency_blocked:0,direct_missing:0,refuted:6,total:12,unknown:0} and
    .claim.state=="REFUTED" and .claim.reason=="UNAUTHORIZED_TRANSFORMATION_OPERATION"' "$unauthorized_receipt" >/dev/null; then unauthorized_semantic=CLOSED; else unauthorized_semantic=REFUTED; fi
fi
mixed_semantic=UNKNOWN
if test -f "$mixed_receipt"; then
  if jq -e '.decision=="FAIL_CLOSED" and .process.summary=={closed:4,dependency_blocked:1,direct_missing:1,refuted:6,total:12,unknown:2} and
    .claim.state=="REFUTED" and .claim.reason=="BASELINE_COUNTEREXAMPLE_PRESENT" and
    ([.process.cells[]|select(.state=="UNKNOWN")]|length)==2' "$mixed_receipt" >/dev/null; then mixed_semantic=CLOSED; else mixed_semantic=REFUTED; fi
fi
refuted_evidence_state=$(combine_states "$refuted_manifest_state" "$(combine_states "$unauthorized_semantic" "$mixed_semantic")")

authority_state=UNKNOWN
if test -f "$producer_runtime" && test -f "$normal_receipt"; then
  if jq -e --arg target "$target_commit" '
    .subject_sha==$target and .toolchain.go=="go1.27.0" and .toolchain.released_gooo_reuse==1 and
    .executions.go_build==0 and .executions.go_test==0 and .executions.product_build==0 and
    .executions.product_test==0 and .executions.local_test==0 and .repository.writes==0 and
    .artifacts.total==56 and .inventory.root_readme_policy=="EXCLUDED"
  ' "$producer_runtime" >/dev/null && jq -e '.authority.repository_writes==0 and .authority.denominator_changes==0 and
    .authority.go_build_executions==0 and .authority.go_test_executions==0 and .authority.local_test_executions==0' "$normal_receipt" >/dev/null; then
    authority_state=CLOSED
  else
    authority_state=REFUTED
  fi
fi

facts='{}'
set_fact() {
  local activity=$1 state=$2
  facts=$(jq -c --arg activity "$activity" --arg state "$state" '. + {($activity):{state:$state}}' <<<"$facts")
}
if test "$producer_release_ok" = true; then set_fact ObserveReleasedTransformationProducer CLOSED; else set_fact ObserveReleasedTransformationProducer REFUTED; fi
if test "$core_release_ok" = true; then set_fact ObserveReleasedTransformationCore CLOSED; else set_fact ObserveReleasedTransformationCore REFUTED; fi
if test "$meta_ok" = true; then set_fact BindTransformationAdoptionActivities CLOSED; else set_fact BindTransformationAdoptionActivities REFUTED; fi
if test "$release_artifact_ok" = true; then set_fact VerifyTransformationReleaseArtifact CLOSED; else set_fact VerifyTransformationReleaseArtifact REFUTED; fi
set_fact VerifyTransformationManifestCorpus "$normal_manifest_state"
set_fact AdoptExactFixtureEffect "$normal_effect_state"
set_fact PreserveAdoptedUnknownCausality "$unknown_evidence_state"
set_fact PreserveAdoptedRefutationPrecedence "$refuted_evidence_state"
set_fact PreserveAdoptedAuthorityBoundary "$authority_state"
set_fact PublishWorkgraphTransformationDecision CLOSED
set_fact VerifyTransformationAdoptionReplay "$normal_replay_state"
set_fact RejectTransformationEvidenceContradiction "$refuted_evidence_state"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
json_or_null() { if test -f "$1" && jq -e . "$1" >/dev/null 2>&1; then cp "$1" "$2"; else printf 'null\n' > "$2"; fi; }
json_or_null "$normal_receipt" "$work/normal.json"
json_or_null "$producer_runtime" "$work/producer-runtime.json"

: > "$work/language-files.ndjson"
while IFS= read -r -d '' file; do
  relative=${file#"$root/"}
  lines=$(wc -l < "$file" | tr -d ' ')
  case "$file" in *.go) language=Go ;; *.gooo) language=Gooo ;; *) continue ;; esac
  jq -cn --arg path "$relative" --arg language "$language" --argjson lines "$lines" '{path:$path,language:$language,physical_lines:$lines}' >> "$work/language-files.ndjson"
done < <(find "$root" -type f -not -path "$root/.git/*" \( -name '*.go' -o -name '*.gooo' \) -print0 | sort -z)
repository_files=$(find "$root" -type f -not -path "$root/.git/*" -not -path "$root/README.md" | wc -l | tr -d ' ')
descendant_directories=$(find "$root" -mindepth 1 -type d -not -path "$root/.git" -not -path "$root/.git/*" | wc -l | tr -d ' ')
physical_lines=$(find "$root" -type f -not -path "$root/.git/*" -not -path "$root/README.md" -print0 | sort -z | xargs -0 cat | wc -l | tr -d ' ')
jq -s --argjson repository_files "$repository_files" --argjson descendant_directories "$descendant_directories" --argjson physical_lines "$physical_lines" '
  . as $files | {root_readme_policy:"EXCLUDED",repository_files:$repository_files,descendant_directories:$descendant_directories,
    physical_lines:$physical_lines,go:{files:([$files[]|select(.language=="Go")]|length),lines:([$files[]|select(.language=="Go")|.physical_lines]|add//0)},
    gooo:{files:([$files[]|select(.language=="Gooo")]|length),lines:([$files[]|select(.language=="Gooo")|.physical_lines]|add//0)},language_files:$files}' \
  "$work/language-files.ndjson" > "$work/inventory.json"

jq -S -n \
  --slurpfile denominator "$denominator" \
  --slurpfile lock "$lock" \
  --slurpfile acquisition "$acquisition" \
  --slurpfile normal "$work/normal.json" \
  --slurpfile producer_runtime "$work/producer-runtime.json" \
  --slurpfile inventory "$work/inventory.json" \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" \
  --argjson facts "$facts" \
  --argjson manifest_verified "$manifest_verified" \
  --argjson manifest_missing "$manifest_missing" \
  --argjson manifest_refuted "$manifest_refuted" '
  (reduce $denominator[0].cells[] as $cell
    ({cells:[],decisions:{}};
      . as $acc |
      ($facts[$cell.activity] // {state:"UNKNOWN"}) as $direct |
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
    schema:"gooo/workgraph/transformation-effect-adoption-report/v1",scenario:$scenario,subject_sha:$subject_sha,
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "ADOPTION_EVIDENCE_UNKNOWN" else "WORKGRAPH_TRANSFORMATION_EFFECT_ADOPTED" end),
    summary:{total:12,closed:$closed,unknown:$unknown,refuted:$refuted,direct_missing:([$evaluation.cells[]|select(.unknown_class=="DIRECT_MISSING")]|length),dependency_blocked:([$evaluation.cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length)},
    adoption:{producer_release_assets:2,producer_release_asset_total:2,release_artifact_files:$acquisition[0].producer.extracted_files,release_artifact_file_total:$lock[0].producer.bundle.expected_files,
      manifest_entries_verified:$manifest_verified,manifest_entry_total:40,manifest_entries_missing:$manifest_missing,manifest_entries_refuted:$manifest_refuted,
      exact_fixture_pairs:(if ($normal[0].improvement.exact_pairs.observed//0)==1 then 1 else 0 end),exact_fixture_pair_total:1,
      producer_normal_cases:1,producer_unknown_cases:(if ($facts.PreserveAdoptedUnknownCausality.state=="CLOSED") then 1 else 0 end),producer_refuted_cases:(if ($facts.PreserveAdoptedRefutationPrecedence.state=="CLOSED") then 2 else 0 end),producer_case_total:4,
      refutation_precedence:(if ($facts.PreserveAdoptedRefutationPrecedence.state=="CLOSED") then 1 else 0 end),refutation_precedence_total:1,
      gooo_meta_activities:(if ($facts.BindTransformationAdoptionActivities.state=="CLOSED") then 12 else 0 end),gooo_meta_activity_total:12,
      independent_public_consumers:(if $refuted==0 and $unknown==0 then 1 else 0 end),independent_public_consumer_total:1},
    utility:{producer_independent_adoption_unknown_resolved:(if $refuted==0 and $unknown==0 then {state:"CLOSED",observed:1,required:1} else {state:(if $refuted>0 then "REFUTED" else "UNKNOWN" end),observed:0,required:1} end),
      language_wide_generalization:{state:"UNKNOWN",observed:0,required:1,stage:"GENERALIZATION",step:"OBSERVE_SECOND_INDEPENDENT_DOMAIN",reason:"SECOND_INDEPENDENT_DOMAIN_EVIDENCE_ABSENT",unknown_class:"DIRECT_MISSING",next_operation:"OBSERVE_SECOND_INDEPENDENT_DOMAIN_CONSUMER",blocked_by:[]},
      external_user_utility:{state:"UNKNOWN",observed:0,required:1,stage:"UTILITY",step:"OBSERVE_EXTERNAL_USER_DECISION",reason:"EXTERNAL_USER_DECISION_EVIDENCE_ABSENT",unknown_class:"DIRECT_MISSING",next_operation:"OBSERVE_ONE_EXTERNAL_USER_DECISION",blocked_by:[]}},
    authority:{evidence:"PINNED_IMMUTABLE_RELEASE_ASSETS",producer_source_checkout:0,sibling_checkout_reads:0,repository_writes:0,go_build_executions:0,go_test_executions:0,local_test_executions:0,cross_project_required_gates:0,automatic_source_promotion:"FORBIDDEN",root_readme_readiness:"EXCLUDED"},
    producer:{release:$acquisition[0].producer,runtime:$producer_runtime[0],normal_effect:($normal[0].effect//null)},inventory:$inventory[0],cells:$evaluation.cells,
    proofs:[$denominator[0].proof_totals[] as $proof | {choice:$proof.proof_choice,total:$proof.total,closed:([$evaluation.cells[]|select(.proof_choice==$proof.proof_choice and .state=="CLOSED")]|length)}],
    indicator_classes:[$denominator[0].indicator_totals[] as $indicator | {class:$indicator.indicator_class,total:$indicator.total,closed:([$evaluation.cells[]|select(.indicator_class==$indicator.indicator_class and .state=="CLOSED")]|length)}],
    indicators:[
      {id:"gooo.metric.workgraph-transformation-adoption.release-files.v1",class:"DRIVER",activity:"VerifyTransformationReleaseArtifact",value:$acquisition[0].producer.extracted_files,total:56,unit:"files"},
      {id:"gooo.metric.workgraph-transformation-adoption.manifest-entries.v1",class:"DRIVER",activity:"VerifyTransformationManifestCorpus",value:$manifest_verified,total:40,unit:"files"},
      {id:"gooo.metric.workgraph-transformation-adoption.fixture-pairs.v1",class:"OUTCOME",activity:"AdoptExactFixtureEffect",value:(if ($normal[0].improvement.exact_pairs.observed//0)==1 then 1 else 0 end),total:1,unit:"pairs"},
      {id:"gooo.metric.workgraph-transformation-adoption.independent-consumers.v1",class:"OUTCOME",activity:"PublishWorkgraphTransformationDecision",value:(if $refuted==0 and $unknown==0 then 1 else 0 end),total:1,unit:"consumers"},
      {id:"gooo.metric.workgraph-transformation-adoption.repository-writes.v1",class:"GUARDRAIL",activity:"PreserveAdoptedAuthorityBoundary",value:0,total:0,unit:"writes"}],
    claim:(if $first_refuted!=null then {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by}
      elif $first_unknown!=null then {state:"UNKNOWN",stage:$first_unknown.stage,step:$first_unknown.step,reason:$first_unknown.reason,unknown_class:$first_unknown.unknown_class,next_operation:$first_unknown.next_operation,blocked_by:$first_unknown.blocked_by}
      else {state:"CLOSED",stage:null,step:null,reason:"WORKGRAPH_TRANSFORMATION_EFFECT_ADOPTION_CLOSED",unknown_class:null,next_operation:"PUBLISH_WORKGRAPH_TRANSFORMATION_ADOPTION",blocked_by:[]} end)
  }
' > "$output"

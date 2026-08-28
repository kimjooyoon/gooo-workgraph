#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 7; then
  echo "usage: readiness-report.sh ROOT REPOSITORY CORE_RELEASE RUNTIME PREDECESSOR OUTPUT HEAD_SHA" >&2
  exit 2
fi

root=$1
repository_observation=$2
core_observation=$3
runtime_observation=$4
predecessor=$5
output=$6
head_sha=$7
denominator="$root/contracts/release-readiness-denominator-v3.json"
contract="$root/contracts/workgraph-project-v1.json"
lock="$root/contracts/core-release-lock-v2.json"
authority="$root/examples/read-only-observer/main.gooo"
rfc="$root/docs/rfcs/workgraph-external-consumer-v1.md"

for file in "$denominator" "$contract" "$lock" "$authority" "$rfc" "$repository_observation" "$core_observation" "$runtime_observation" "$predecessor"; do
  test -f "$file" || { echo "missing required input: $file" >&2; exit 2; }
done

jq -e '.schema == "gooo/workgraph-release-readiness-denominator/v3" and .version == 3 and .target_tasks == 12 and (.tasks | length) == 12' "$denominator" >/dev/null
jq -e '.schema == "gooo/workgraph-project/v1" and (.gates | length) == 7' "$contract" >/dev/null
jq -e '.schema == "gooo/core-release-lock/v2" and (.assets | length) == 8' "$lock" >/dev/null
jq -e '.schema == "gooo/public-repository-observation/v1"' "$repository_observation" >/dev/null
jq -e '.schema == "gooo/core-release-observation/v2"' "$core_observation" >/dev/null
jq -e '.schema == "gooo/released-cli-observation/v2"' "$runtime_observation" >/dev/null
jq -e '.schema == "gooo/workgraph-readiness-predecessor/v1" or .schema == "gooo/workgraph-release-readiness-report/v3"' "$predecessor" >/dev/null

digest_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print "sha256:" $1}';
  else shasum -a 256 "$1" | awk '{print "sha256:" $1}'; fi
}

denominator_digest=$(digest_file "$denominator")
contract_digest=$(digest_file "$contract")
lock_digest=$(digest_file "$lock")
authority_digest=$(digest_file "$authority")
core_digest=$(digest_file "$core_observation")
runtime_digest=$(digest_file "$runtime_observation")
predecessor_digest=$(digest_file "$predecessor")
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

jq -n \
  --slurpfile d "$denominator" \
  --slurpfile repo "$repository_observation" \
  --slurpfile core "$core_observation" \
  --slurpfile runtime "$runtime_observation" \
  --slurpfile pred "$predecessor" \
  --slurpfile lock "$lock" \
  --arg head "$head_sha" \
  --arg dd "$denominator_digest" \
  --arg cd "$contract_digest" \
  --arg ld "$lock_digest" \
  --arg ad "$authority_digest" \
  --arg cod "$core_digest" \
  --arg rud "$runtime_digest" \
  --arg pd "$predecessor_digest" '
  def valid_digest: type == "string" and test("^sha256:[0-9a-f]{64}$");
  def valid_raw_digest: type == "string" and test("^[0-9a-f]{64}$");
  def closed($t; $reason): $t + {state:"CLOSED",resolution:"EXACT",reason:$reason,next_operation:"NONE"};
  def unknown($t): $t + {state:"UNKNOWN",resolution:"PREREQUISITE_CLASS",reason:$t.unknown_reason,next_operation:$t.next_operation};
  def refuted($t; $reason; $next): $t + {state:"REFUTED",resolution:"EXACT",reason:$reason,next_operation:$next};
  def asset_view($items): [$items[] | {name,digest,size}] | sort_by(.name);
  def core_identity_ok:
    $core[0].available == true and
    $core[0].release.tag_name == $lock[0].tag and
    $core[0].release.draft == $lock[0].draft and
    $core[0].release.prerelease == $lock[0].prerelease and
    $core[0].release.tag_object_type == "tag" and
    $core[0].release.tag_object_sha == $lock[0].annotated_tag.object_sha and
    $core[0].release.target_sha == $lock[0].annotated_tag.target_sha;
  def asset_lock_ok:
    core_identity_ok and
    asset_view($core[0].release.assets) == asset_view($lock[0].assets) and
    $runtime[0].available == true and
    $runtime[0].binary.asset_name == $lock[0].consumer.binary_asset and
    $runtime[0].binary.digest == ($lock[0].assets[] | select(.name == $lock[0].consumer.binary_asset) | .digest) and
    $runtime[0].binary.api_digest == $runtime[0].binary.digest and
    $runtime[0].binary.checksum_digest == $runtime[0].binary.digest and
    $runtime[0].binary.checksum_verified == true;
  def version_ok:
    $runtime[0].available == true and
    $runtime[0].version.schema_version == $lock[0].schemas.version and
    $runtime[0].version.language == "gooo" and
    $runtime[0].version.version == $lock[0].version and
    $runtime[0].version.status == $lock[0].status;
  def syntax_check_ok:
    $runtime[0].available == true and
    $runtime[0].syntax_check.schema_version == $lock[0].schemas.check and
    $runtime[0].syntax_check.command == "check" and
    $runtime[0].syntax_check.status == "ok" and
    $runtime[0].syntax_check.file == "examples/read-only-observer/main.gooo" and
    ($runtime[0].syntax_check.diagnostics | length) == 0;
  def semantic_check_ok:
    $runtime[0].available == true and
    $runtime[0].semantic_check.schema_version == $lock[0].schemas.check and
    $runtime[0].semantic_check.command == "check" and
    $runtime[0].semantic_check.status == "ok" and
    $runtime[0].semantic_check.file == "examples/read-only-observer/main.gooo" and
    ($runtime[0].semantic_check.diagnostics | length) == 0 and
    ($runtime[0].semantic_check.semantic_hash | type) == "string" and
    ($runtime[0].semantic_check.semantic_hash | length) > 0;
  def denominator_activity_names: [$d[0].tasks[].activity] | sort;
  def graph_activity_names: [$runtime[0].graph.nodes[]? | select(.kind == "Activity") | .name] | sort;
  def meta_binding_count: (denominator_activity_names - (denominator_activity_names - graph_activity_names)) | length;
  def graph_ok:
    $runtime[0].available == true and
    $runtime[0].graph.schema_version == $lock[0].schemas.graph and
    ($runtime[0].graph.source_digest | valid_raw_digest) and
    $runtime[0].graph.ir.status == "available" and
    ($runtime[0].graph.ir.semantic_digest | valid_raw_digest) and
    ($runtime[0].graph.graph_hash | valid_raw_digest) and
    graph_activity_names == denominator_activity_names;
  def semantic_receipts_ok: syntax_check_ok and semantic_check_ok and graph_ok;
  def source_head_ok:
    $runtime[0].available == true and
    $runtime[0].subject_sha == $head and
    $runtime[0].source.path == "examples/read-only-observer/main.gooo" and
    ($runtime[0].source.digest | valid_digest) and
    $runtime[0].source.digest == ("sha256:" + $runtime[0].graph.source_digest);
  def repository_zero_write:
    $runtime[0].available == true and
    $runtime[0].repository.writes == 0 and
    ($runtime[0].repository.before_digest | valid_digest) and
    $runtime[0].repository.before_digest == $runtime[0].repository.after_digest;
  def predecessor_ok:
    $pred[0].schema == "gooo/workgraph-release-readiness-report/v3" and
    $pred[0].head_sha == $head and
    ($pred[0].report_digest | valid_digest) and
    $pred[0].decision == "PROGRESS_OBSERVED" and
    $pred[0].summary.total_tasks == 12 and
    $pred[0].summary.closed_tasks == 10 and
    $pred[0].summary.unknown_tasks == 2 and
    $pred[0].summary.refuted_tasks == 0 and
    $pred[0].claim.state == "UNKNOWN" and
    $pred[0].claim.stage == "EVALUATOR" and
    $pred[0].claim.step == "OBSERVE_INITIAL_REPORT" and
    $pred[0].claim.reason == "INITIAL_REPORT_NOT_OBSERVED" and
    $pred[0].claim.next_operation == "EVALUATE_READ_ONLY_OBSERVATION";

  ($d[0].tasks | map(
    if .id == "PUBLIC_REPOSITORY" then
      if ($repo[0].visibility == "public" and $repo[0].private == false) then closed(.; .closed_reason)
      else refuted(.; "PUBLIC_REPOSITORY_NOT_PUBLIC"; "MAKE_REPOSITORY_PUBLIC") end
    elif .bootstrap_closed == true then closed(.; .closed_reason)
    elif .id == "CORE_RELEASE_AVAILABLE" then
      if $core[0].available != true then unknown(.)
      elif core_identity_ok then closed(.; .closed_reason)
      else refuted(.; "CORE_RELEASE_IDENTITY_MISMATCH"; "RESTORE_PINNED_RELEASE_IDENTITY") end
    elif .id == "CORE_BINARY_DIGEST_LOCKED" then
      if $core[0].available != true then unknown(.)
      elif asset_lock_ok then closed(.; .closed_reason)
      else refuted(.; "CORE_RELEASE_ASSET_SET_MISMATCH"; "RESTORE_PINNED_RELEASE_ASSET_SET") end
    elif .id == "CORE_VERSION_SCHEMA_ADVERTISED" then
      if $runtime[0].available != true then unknown(.)
      elif version_ok then closed(.; .closed_reason)
      else refuted(.; "RELEASED_VERSION_RECEIPT_MISMATCH"; "RESTORE_RELEASED_VERSION_CONTRACT") end
    elif .id == "CORE_SEMANTIC_RECEIPTS_OBSERVED" then
      if $runtime[0].available != true then unknown(.)
      elif semantic_receipts_ok then closed(.; .closed_reason)
      else refuted(.; "RELEASED_SEMANTIC_RECEIPTS_MISMATCH"; "RESTORE_RELEASED_SEMANTIC_RECEIPTS") end
    elif .id == "SOURCE_HEAD_BOUND" then
      if $runtime[0].available != true then unknown(.)
      elif source_head_ok then closed(.; .closed_reason)
      else refuted(.; "SOURCE_HEAD_BINDING_MISMATCH"; "RESTORE_EXACT_SOURCE_HEAD_BINDING") end
    elif .id == "REPOSITORY_ZERO_WRITE_OBSERVED" then
      if $runtime[0].available != true then unknown(.)
      elif repository_zero_write then closed(.; .closed_reason)
      else refuted(.; "REPOSITORY_WRITE_EFFECT_OBSERVED"; "REMOVE_INPUT_REPOSITORY_WRITES") end
    elif .id == "INITIAL_REPORT_OBSERVED" then
      if $pred[0].schema == "gooo/workgraph-readiness-predecessor/v1" then unknown(.)
      elif predecessor_ok then closed(.; .closed_reason)
      else refuted(.; "INITIAL_REPORT_PREDECESSOR_MISMATCH"; "RESTORE_INITIAL_REPORT_PREDECESSOR") end
    elif .id == "UNKNOWN_TRACE_PRESERVED" then
      if $pred[0].schema == "gooo/workgraph-readiness-predecessor/v1" then unknown(.)
      elif predecessor_ok then closed(.; .closed_reason)
      else refuted(.; "UNKNOWN_TRACE_NOT_PRESERVED"; "RESTORE_UNKNOWN_TRACE_COORDINATES") end
    else unknown(.) end
    | del(.closed_reason,.unknown_reason,.bootstrap_closed)
  )) as $cells |
  ([$cells[]|select(.state=="REFUTED")][0] // null) as $first_refuted |
  ([$cells[]|select(.state=="UNKNOWN")][0] // null) as $first_unknown |
  ([$cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$cells[]|select(.state=="REFUTED")]|length) as $refuted |
  (if $runtime[0].available == true and ($runtime[0].repository.writes|type) == "number" then $runtime[0].repository.writes else null end) as $writes |
  {schema:"gooo/workgraph-release-readiness-report/v3",head_sha:$head,
   repository:$repo[0].full_name,
   decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "PROGRESS_OBSERVED" else "READ_ONLY_OBSERVER_READY" end),
   resolution:(if $refuted>0 or $unknown==0 then "EXACT" else "PREREQUISITE_CLASS" end),
   reason:(if $refuted>0 then $first_refuted.reason elif $unknown>0 then $first_unknown.reason else "READ_ONLY_OBSERVER_PREREQUISITES_CLOSED" end),
   next_operation:(if $refuted>0 then $first_refuted.next_operation elif $unknown>0 then $first_unknown.next_operation else "NONE" end),
   promotion_authorized:false,
   source:{denominator_digest:$dd,contract_digest:$cd,core_lock_digest:$ld,authority_digest:$ad,
     core_observation_digest:$cod,runtime_observation_digest:$rud},
   released_cli:{
     version_schema:$runtime[0].version.schema_version,
     syntax_check_schema:$runtime[0].syntax_check.schema_version,
     syntax_check_status:$runtime[0].syntax_check.status,
     semantic_check_schema:$runtime[0].semantic_check.schema_version,
     semantic_check_status:$runtime[0].semantic_check.status,
     semantic_hash:$runtime[0].semantic_check.semantic_hash,
     graph_schema:$runtime[0].graph.schema_version,
     graph_source_digest:$runtime[0].graph.source_digest,
     semantic_ir_digest:$runtime[0].graph.ir.semantic_digest,
     graph_hash:$runtime[0].graph.graph_hash,
     activity_bindings:meta_binding_count,
     activity_total:12},
   predecessor:(if predecessor_ok then {artifact_digest:$pd,report_digest:$pred[0].report_digest,claim:$pred[0].claim,summary:$pred[0].summary} else null end),
   cells:$cells,
   claim:{id:"workgraph://claim/read-only-observer-release-readiness",status:(if $refuted>0 then "CONTESTED" elif $unknown>0 then "ACTIVE" else "DISCHARGED" end),
     state:(if $refuted>0 then "REFUTED" elif $unknown>0 then "UNKNOWN" else "CLOSED" end),
     resolution:(if $refuted>0 or $unknown==0 then "EXACT" else "PREREQUISITE_CLASS" end),
     stage:(if $refuted>0 then $first_refuted.stage elif $unknown>0 then $first_unknown.stage else null end),
     step:(if $refuted>0 then $first_refuted.step elif $unknown>0 then $first_unknown.step else null end),
     reason:(if $refuted>0 then $first_refuted.reason elif $unknown>0 then $first_unknown.reason else "READ_ONLY_OBSERVER_PREREQUISITES_CLOSED" end),
     next_operation:(if $refuted>0 then $first_refuted.next_operation elif $unknown>0 then $first_unknown.next_operation else "NONE" end)},
   summary:{total_tasks:12,closed_tasks:$closed,unknown_tasks:$unknown,refuted_tasks:$refuted,repository_writes:$writes},
   indicators:[
     {id:"gooo.metric.workgraph.release-readiness.v3",class:"OUTCOME",value:$closed,total:12,target:12,unit:"tasks",proof_choice:"COHERENCE",state:(if $closed==12 then "SATISFIED" else "GAP" end),activity:"PreserveUnknownTrace"},
     {id:"gooo.metric.workgraph.core-release-available.v3",class:"DRIVER",value:(if core_identity_ok then 1 else 0 end),total:1,target:1,unit:"releases",proof_choice:"FOUNDATION",state:(if core_identity_ok then "SATISFIED" else "GAP" end),activity:"ObserveCoreRelease"},
     {id:"gooo.metric.workgraph.released-cli-receipts.v3",class:"DRIVER",value:([version_ok,syntax_check_ok,semantic_check_ok,graph_ok]|map(select(. == true))|length),total:4,target:4,unit:"receipts",proof_choice:"COHERENCE",state:(if version_ok and semantic_receipts_ok then "SATISFIED" else "GAP" end),activity:"ObserveReleasedSemanticReceipts"},
     {id:"gooo.metric.workgraph.predecessor-bindings.v1",class:"DRIVER",value:([$cells[]|select((.id=="INITIAL_REPORT_OBSERVED" or .id=="UNKNOWN_TRACE_PRESERVED") and .state=="CLOSED")]|length),total:2,target:2,unit:"bindings",proof_choice:"REGRESSION",state:(if predecessor_ok then "SATISFIED" else "GAP" end),activity:"PreserveUnknownTrace"},
     {id:"gooo.metric.workgraph.unknown-prerequisites.v3",class:"GUARDRAIL",value:$unknown,total:12,target:0,unit:"tasks",proof_choice:"FOUNDATION",state:(if $unknown==0 then "SATISFIED" else "GAP" end),activity:"DeclareGoooAuthority"},
     {id:"gooo.metric.workgraph.refuted-prerequisites.v3",class:"GUARDRAIL",value:$refuted,total:12,target:0,unit:"tasks",proof_choice:"COHERENCE",state:(if $refuted==0 then "SATISFIED" else "GAP" end),activity:"VersionWorkgraphContract"},
     {id:"gooo.metric.workgraph.meta-binding.v3",class:"DRIVER",value:meta_binding_count,total:12,target:12,unit:"activities",proof_choice:"COHERENCE",state:(if meta_binding_count==12 then "SATISFIED" else "GAP" end),activity:"PublishContractRFC"},
     {id:"gooo.metric.workgraph.repository-writes.v3",class:"GUARDRAIL",value:$writes,total:1,target:0,unit:"writes",proof_choice:"REGRESSION",state:(if $writes==null then "UNKNOWN" elif $writes==0 then "SATISFIED" else "REFUTED" end),activity:"ObserveRepositoryWrites"}
   ]} as $report |
   $report + {proofs:(["FOUNDATION","COHERENCE","REGRESSION"] | map(. as $p | {choice:$p,closed:([$cells[]|select(.proof_choice==$p and .state=="CLOSED")]|length),total:([$cells[]|select(.proof_choice==$p)]|length)}))}
  ' > "$tmp"

report_digest=$(digest_file "$tmp")
jq --arg digest "$report_digest" '. + {report_digest:$digest}' "$tmp" > "$output"

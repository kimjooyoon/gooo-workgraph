#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 5; then
  echo "usage: readiness-report.sh ROOT REPOSITORY_OBSERVATION CORE_RELEASE_OBSERVATION OUTPUT HEAD_SHA" >&2
  exit 2
fi

root=$1
repository_observation=$2
core_observation=$3
output=$4
head_sha=$5
denominator="$root/contracts/release-readiness-denominator-v1.json"
contract="$root/contracts/workgraph-project-v1.json"
authority="$root/examples/read-only-observer/main.gooo"
rfc="$root/docs/rfcs/workgraph-external-consumer-v1.md"

for file in "$denominator" "$contract" "$authority" "$rfc" "$repository_observation" "$core_observation"; do
  test -f "$file" || { echo "missing required input: $file" >&2; exit 2; }
done

jq -e '.schema == "gooo/workgraph-release-readiness-denominator/v1" and .target_tasks == 12 and (.tasks | length) == 12' "$denominator" >/dev/null
jq -e '.schema == "gooo/workgraph-project/v1" and (.gates | length) == 7' "$contract" >/dev/null
jq -e '.schema == "gooo/public-repository-observation/v1"' "$repository_observation" >/dev/null
jq -e '.schema == "gooo/core-release-observation/v1"' "$core_observation" >/dev/null

while IFS= read -r activity; do
  grep -Fq "activity $activity(" "$authority" || { echo "unbound Gooo activity: $activity" >&2; exit 3; }
done < <(jq -r '.tasks[].activity' "$denominator")

digest_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print "sha256:" $1}';
  else shasum -a 256 "$1" | awk '{print "sha256:" $1}'; fi
}

denominator_digest=$(digest_file "$denominator")
contract_digest=$(digest_file "$contract")
authority_digest=$(digest_file "$authority")
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

jq -n --slurpfile d "$denominator" --slurpfile repo "$repository_observation" --slurpfile core "$core_observation" \
  --arg head "$head_sha" --arg dd "$denominator_digest" --arg cd "$contract_digest" --arg ad "$authority_digest" '
  def closed($t; $reason): $t + {state:"CLOSED",resolution:"EXACT",reason:$reason,next_operation:"NONE"};
  def unknown($t): $t + {state:"UNKNOWN",resolution:"PREREQUISITE_CLASS",reason:$t.unknown_reason,next_operation:$t.next_operation};
  def refuted($t; $reason; $next): $t + {state:"REFUTED",resolution:"EXACT",reason:$reason,next_operation:$next};
  def locked_assets: (($core[0].release.assets // []) as $a | ($a|length)>0 and all($a[]; (.digest // "") | startswith("sha256:")));
  ($d[0].tasks | map(
    if .id == "PUBLIC_REPOSITORY" then
      if ($repo[0].visibility == "public" and $repo[0].private == false) then closed(.; .closed_reason)
      else refuted(.; "PUBLIC_REPOSITORY_NOT_PUBLIC"; "MAKE_REPOSITORY_PUBLIC") end
    elif .bootstrap_closed == true then closed(.; .closed_reason)
    elif .id == "CORE_RELEASE_AVAILABLE" and $core[0].available == true then closed(.; .closed_reason)
    elif .id == "CORE_BINARY_DIGEST_LOCKED" and $core[0].available == true and locked_assets then closed(.; .closed_reason)
    else unknown(.) end
    | del(.closed_reason,.unknown_reason,.bootstrap_closed)
  )) as $cells |
  ([$cells[]|select(.state=="REFUTED")][0] // null) as $first_refuted |
  ([$cells[]|select(.state=="UNKNOWN")][0] // null) as $first_unknown |
  ([$cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$cells[]|select(.state=="REFUTED")]|length) as $refuted |
  {schema:"gooo/workgraph-release-readiness-report/v1",head_sha:$head,
   repository:$repo[0].full_name,decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "PROGRESS_OBSERVED" else "READ_ONLY_OBSERVER_READY" end),
   resolution:(if $refuted>0 or $unknown==0 then "EXACT" else "PREREQUISITE_CLASS" end),
   reason:(if $refuted>0 then $first_refuted.reason elif $unknown>0 then $first_unknown.reason else "READ_ONLY_OBSERVER_PREREQUISITES_CLOSED" end),
   next_operation:(if $refuted>0 then $first_refuted.next_operation elif $unknown>0 then $first_unknown.next_operation else "NONE" end),
   promotion_authorized:false,denominator_digest:$dd,contract_digest:$cd,authority_digest:$ad,cells:$cells,
   claim:{id:"workgraph://claim/read-only-observer-release-readiness",status:(if $refuted>0 then "CONTESTED" elif $unknown>0 then "ACTIVE" else "DISCHARGED" end),
     state:(if $refuted>0 then "REFUTED" elif $unknown>0 then "UNKNOWN" else "CLOSED" end),
     resolution:(if $refuted>0 or $unknown==0 then "EXACT" else "PREREQUISITE_CLASS" end),
     stage:(if $refuted>0 then $first_refuted.stage elif $unknown>0 then $first_unknown.stage else null end),
     step:(if $refuted>0 then $first_refuted.step elif $unknown>0 then $first_unknown.step else null end),
     reason:(if $refuted>0 then $first_refuted.reason elif $unknown>0 then $first_unknown.reason else "READ_ONLY_OBSERVER_PREREQUISITES_CLOSED" end),
     next_operation:(if $refuted>0 then $first_refuted.next_operation elif $unknown>0 then $first_unknown.next_operation else "NONE" end)},
   summary:{total_tasks:12,closed_tasks:$closed,unknown_tasks:$unknown,refuted_tasks:$refuted,repository_writes:null},
   indicators:[
     {id:"gooo.metric.workgraph.release-readiness.v1",class:"OUTCOME",value:$closed,total:12,target:12,unit:"tasks",proof_choice:"COHERENCE",state:(if $closed==12 then "SATISFIED" else "GAP" end),activity:"PreserveUnknownTrace"},
     {id:"gooo.metric.workgraph.core-release-available.v1",class:"DRIVER",value:(if $core[0].available then 1 else 0 end),total:1,target:1,unit:"releases",proof_choice:"FOUNDATION",state:(if $core[0].available then "SATISFIED" else "GAP" end),activity:"ObserveCoreRelease"},
     {id:"gooo.metric.workgraph.unknown-prerequisites.v1",class:"GUARDRAIL",value:$unknown,total:12,target:0,unit:"tasks",proof_choice:"FOUNDATION",state:(if $unknown==0 then "SATISFIED" else "GAP" end),activity:"DeclareGoooAuthority"},
     {id:"gooo.metric.workgraph.refuted-prerequisites.v1",class:"GUARDRAIL",value:$refuted,total:12,target:0,unit:"tasks",proof_choice:"COHERENCE",state:(if $refuted==0 then "SATISFIED" else "GAP" end),activity:"VersionWorkgraphContract"},
     {id:"gooo.metric.workgraph.meta-binding.v1",class:"DRIVER",value:12,total:12,target:12,unit:"activities",proof_choice:"COHERENCE",state:"SATISFIED",activity:"PublishContractRFC"},
     {id:"gooo.metric.workgraph.repository-writes.v1",class:"GUARDRAIL",value:null,total:1,target:0,unit:"writes",proof_choice:"REGRESSION",state:"UNKNOWN",activity:"ObserveRepositoryWrites"}
   ],
   proofs:["FOUNDATION","COHERENCE","REGRESSION"] | . as $report |
   $report + {proofs:(["FOUNDATION","COHERENCE","REGRESSION"] | map(. as $p | {choice:$p,closed:([$cells[]|select(.proof_choice==$p and .state=="CLOSED")]|length),total:([$cells[]|select(.proof_choice==$p)]|length)}))}
  ' > "$tmp"

report_digest=$(digest_file "$tmp")
jq --arg digest "$report_digest" '. + {report_digest:$digest}' "$tmp" > "$output"

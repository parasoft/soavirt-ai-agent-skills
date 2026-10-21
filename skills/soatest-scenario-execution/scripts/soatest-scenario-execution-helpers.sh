#!/usr/bin/env bash

# Shared SOAtest REST API v6 operations for the bash runner.

set -o pipefail

SOA_BASE="http://localhost:9080/soavirt/api/v6"
SOA_CURL_ARGS=()
SOA_DEADLINE_EPOCH=""

json_field() {
  local field="$1"
  python3 -c 'import json,sys
value=json.load(sys.stdin)
for part in sys.argv[1].split("."):
    value=value.get(part) if isinstance(value, dict) else None
print("" if value is None else str(value).lower() if isinstance(value, bool) else value)' "$field"
}

execution_body() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
config, tst_file_id = sys.argv[1:]
print(json.dumps({'general': {'config': config, 'localSettings': [{'name': 'report.archive', 'value': 'true'}]}, 'scopeOptions': {'workspace': {'resources': [tst_file_id]}}}, separators=(',', ':')))
PY
}

initialize_soa_config() {
  local host="${1:-localhost}" port="${2:-9080}" protocol="${3:-http}"
  local username="${4:-}" password="${5:-}" bearer_token="${6:-}" deadline_minutes="${7:-0}"
  SOA_BASE="${protocol}://${host}:${port}/soavirt/api/v6"
  SOA_CURL_ARGS=(--header "Content-Type: application/json" --header "Accept: application/json")
  if [[ -n "$bearer_token" ]]; then SOA_CURL_ARGS+=(--header "Authorization: Bearer ${bearer_token}"); elif [[ -n "$username" ]]; then SOA_CURL_ARGS+=(--user "${username}:${password}"); fi
  if [[ "$deadline_minutes" -gt 0 ]]; then SOA_DEADLINE_EPOCH=$(( $(date +%s) + deadline_minutes * 60 )); else SOA_DEADLINE_EPOCH=""; fi
  echo "[SOA] Configured: ${SOA_BASE}" >&2
}

assert_soa_deadline() {
  if [[ -n "$SOA_DEADLINE_EPOCH" && $(date +%s) -gt "$SOA_DEADLINE_EPOCH" ]]; then echo "[DEADLINE] Script deadline exceeded at: ${1:-unknown}" >&2; return 1; fi
}

invoke_soa_execution() {
  local tst_file_id="$1" config="$2" response body
  assert_soa_deadline "invoke_soa_execution" || return 1
  body="$(execution_body "$config" "$tst_file_id")"
  response="$(curl --silent --show-error --fail-with-body "${SOA_CURL_ARGS[@]}" --request POST --data "$body" "${SOA_BASE}/testExecutions")" || {
    echo "[ERR] Could not start execution: ${response}" >&2
    printf '__SOA_EXECUTION_ERROR__%s\n' "$response"
    return 1
  }
  json_field id <<<"$response"
}

invoke_soa_execution_with_json() {
  local body="$1" response
  assert_soa_deadline "invoke_soa_execution_with_json" || return 1
  response="$(curl --silent --show-error --fail-with-body "${SOA_CURL_ARGS[@]}" --request POST --data "$body" "${SOA_BASE}/testExecutions")" || {
    echo "[ERR] Could not start execution: ${response}" >&2
    printf '__SOA_EXECUTION_ERROR__%s\n' "$response"
    return 1
  }
  json_field id <<<"$response"
}

wait_soa_execution() {
  local job_id="$1" poll_interval_seconds="${2:-2}" max_wait_minutes="${3:-15}" deadline iteration=0 status
  deadline=$(( $(date +%s) + max_wait_minutes * 60 ))
  echo "[INFO] Polling execution '${job_id}' (max ${max_wait_minutes}m, interval ${poll_interval_seconds}s)..." >&2
  while [[ $(date +%s) -lt "$deadline" ]]; do
    iteration=$((iteration + 1))
    status="$(curl --silent --show-error --fail-with-body "${SOA_CURL_ARGS[@]}" --request GET "${SOA_BASE}/testExecutions/${job_id}/status")" || true
    if [[ -n "$status" ]] && python3 -c 'import json,sys; json.load(sys.stdin)' <<<"$status" >/dev/null 2>&1; then
      echo "  [Poll ${iteration}] isRunning=$(json_field isRunning <<<"$status") percent=$(json_field percent <<<"$status")" >&2
      if [[ "$(json_field isRunning <<<"$status")" != "true" ]]; then return 0; fi
    else echo "  [Poll ${iteration}] Status check failed" >&2; fi
    sleep "$poll_interval_seconds"
  done
  echo "[DEADLINE] Execution did not finish within ${max_wait_minutes} minutes" >&2
  return 1
}

get_soa_execution_results() {
  curl --silent --show-error --fail-with-body "${SOA_CURL_ARGS[@]}" --request GET "${SOA_BASE}/testExecutions/$1/results?includeReportArchive=true"
}

remove_soa_execution() {
  curl --silent --show-error --fail "${SOA_CURL_ARGS[@]}" --request DELETE "${SOA_BASE}/testExecutions/$1" >/dev/null
}
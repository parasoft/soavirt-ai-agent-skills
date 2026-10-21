#!/usr/bin/env bash

set -o pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/upload_virtualize_files.sh --host HOST --port PORT --source PATH [options]

Required:
  --host HOST                 Virtualize server host (e.g. localhost)
  --port PORT                 Virtualize server port (e.g. 9080)
  --source PATH               File path or directory path to upload

Optional:
  --protocol PROTOCOL         http or https (default: http)
  --id ID                     Required upload id when source is a single file.
                              If omitted for single file, basename(source) is used.
  --id-prefix PREFIX          Prefix used for directory uploads.
                              Final id for each file is PREFIX/relative/path.
  --deploy true|false         Query parameter deploy (default: true)
  --replace true|false        Query parameter replace (default: false)
  --username USER             Virtualize API username (or use VIRT_USERNAME env var)
  --password PASS             Virtualize API password (or use VIRT_PASSWORD env var)
  --bearer-token TOKEN        Virtualize API bearer token (or use VIRT_BEARER_TOKEN env var)
                              When set, bearer auth is used instead of basic auth.
  --quiet-success true|false  Suppress per-file success lines (default: false)
  --progress-every N          Emit PROGRESS every N files (default: 25, 0 disables)
  --log-format FORMAT         text or jsonl (default: text)
  --summary-file PATH         Write final JSON summary to file
  --failures-file PATH        Write failure records as JSONL to file
  --timeout-seconds N         Per-file HTTP timeout seconds (default: 120)
  --max-retries N             Retries per file after first attempt (default: 2)
  --retry-backoff-ms N        Delay between retries in ms (default: 500)
  --continue-on-error true|false
                              Continue processing after a failed file (default: true)
  --dry-run true|false        Resolve files and IDs without uploading (default: false)
  --help                      Show this help text

Examples:
  ./scripts/upload_virtualize_files.sh --host localhost --port 9080 --source ./asset.pva --id "VirtualAssets/asset.pva"
  ./scripts/upload_virtualize_files.sh --host localhost --port 9080 --source ./assets --id-prefix "VirtualAssets"
  ./scripts/upload_virtualize_files.sh --host localhost --port 9080 --source ./assets --id-prefix "VirtualAssets" --quiet-success true --progress-every 25 --summary-file /tmp/upload-summary.json
EOF
}

HOST=""
PORT=""
PROTOCOL="http"
SOURCE=""
SINGLE_ID=""
ID_PREFIX=""
DEPLOY="true"
REPLACE="false"
USERNAME="${VIRT_USERNAME:-}"
PASSWORD="${VIRT_PASSWORD:-}"
BEARER_TOKEN="${VIRT_BEARER_TOKEN:-}"
QUIET_SUCCESS="false"
PROGRESS_EVERY="25"
LOG_FORMAT="text"
SUMMARY_FILE=""
FAILURES_FILE=""
TIMEOUT_SECONDS="120"
MAX_RETRIES="2"
RETRY_BACKOFF_MS="500"
CONTINUE_ON_ERROR="true"
DRY_RUN="false"
UPLOAD_LAST_STATUS=""
UPLOAD_LAST_ERROR=""
UPLOAD_LAST_BODY=""
UPLOAD_LAST_ATTEMPTS="0"

normalize_bool() {
  local raw="$1"
  local lowered
  lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    true|false)
      printf '%s' "$lowered"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_non_negative_integer() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

ensure_parent_dir() {
  local target="$1"
  local parent
  parent="$(dirname "$target")"
  if [[ ! -d "$parent" ]]; then
    mkdir -p "$parent" || return 1
  fi
  return 0
}

emit_json_event() {
  local event="$1"
  shift
  python3 - "$event" "$@" <<'PY'
import json
import sys
event = sys.argv[1]
parts = sys.argv[2:]
payload = {"event": event}
for i in range(0, len(parts), 2):
    key = parts[i]
    value = parts[i + 1] if i + 1 < len(parts) else ""
    lowered = value.lower()
    if lowered == "true":
        payload[key] = True
    elif lowered == "false":
        payload[key] = False
    else:
        try:
            payload[key] = int(value)
        except ValueError:
            payload[key] = value
print(json.dumps(payload, ensure_ascii=False))
PY
}

emit_text_event() {
  local event="$1"
  shift
  local line="$event"
  while [[ $# -ge 2 ]]; do
    local key="$1"
    local value="$2"
    value="${value//$'\n'/ }"
    line="$line $key=$(printf '%q' "$value")"
    shift 2
  done
  echo "$line"
}

emit_event() {
  local event="$1"
  shift
  if [[ "$LOG_FORMAT" == "jsonl" ]]; then
    emit_json_event "$event" "$@"
  else
    emit_text_event "$event" "$@"
  fi
}

append_failure_artifact() {
  if [[ -z "$FAILURES_FILE" ]]; then
    return 0
  fi
  ensure_parent_dir "$FAILURES_FILE" || return 1
  python3 - "$FAILURES_FILE" "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import json
import pathlib
import sys
file_path, source_file, upload_id, status, attempts, error, detail = sys.argv[1:8]
record = {
    "file": source_file,
    "id": upload_id,
    "status": status,
    "attempts": int(attempts) if attempts.isdigit() else attempts,
    "error": error,
    "detail": detail
}
path = pathlib.Path(file_path)
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, ensure_ascii=False) + "\n")
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --protocol)
      PROTOCOL="$2"
      shift 2
      ;;
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --id)
      SINGLE_ID="$2"
      shift 2
      ;;
    --id-prefix)
      ID_PREFIX="$2"
      shift 2
      ;;
    --deploy)
      DEPLOY="$2"
      shift 2
      ;;
    --replace)
      REPLACE="$2"
      shift 2
      ;;
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --bearer-token)
      BEARER_TOKEN="$2"
      shift 2
      ;;
    --quiet-success)
      QUIET_SUCCESS="$2"
      shift 2
      ;;
    --progress-every)
      PROGRESS_EVERY="$2"
      shift 2
      ;;
    --log-format)
      LOG_FORMAT="$2"
      shift 2
      ;;
    --summary-file)
      SUMMARY_FILE="$2"
      shift 2
      ;;
    --failures-file)
      FAILURES_FILE="$2"
      shift 2
      ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    --retry-backoff-ms)
      RETRY_BACKOFF_MS="$2"
      shift 2
      ;;
    --continue-on-error)
      CONTINUE_ON_ERROR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$HOST" || -z "$PORT" || -z "$SOURCE" ]]; then
  echo "Error: --host, --port, and --source are required." >&2
  usage
  exit 2
fi

if [[ "$PROTOCOL" != "http" && "$PROTOCOL" != "https" ]]; then
  echo "Error: --protocol must be 'http' or 'https'." >&2
  exit 2
fi

if [[ "$DEPLOY" != "true" && "$DEPLOY" != "false" ]]; then
  echo "Error: --deploy must be 'true' or 'false'." >&2
  exit 2
fi

if [[ "$REPLACE" != "true" && "$REPLACE" != "false" ]]; then
  echo "Error: --replace must be 'true' or 'false'." >&2
  exit 2
fi

QUIET_SUCCESS="$(normalize_bool "$QUIET_SUCCESS")" || { echo "Error: --quiet-success must be 'true' or 'false'." >&2; exit 2; }
CONTINUE_ON_ERROR="$(normalize_bool "$CONTINUE_ON_ERROR")" || { echo "Error: --continue-on-error must be 'true' or 'false'." >&2; exit 2; }
DRY_RUN="$(normalize_bool "$DRY_RUN")" || { echo "Error: --dry-run must be 'true' or 'false'." >&2; exit 2; }

if [[ "$LOG_FORMAT" != "text" && "$LOG_FORMAT" != "jsonl" ]]; then
  echo "Error: --log-format must be 'text' or 'jsonl'." >&2
  exit 2
fi

is_non_negative_integer "$PROGRESS_EVERY" || { echo "Error: --progress-every must be a non-negative integer." >&2; exit 2; }
is_non_negative_integer "$TIMEOUT_SECONDS" || { echo "Error: --timeout-seconds must be a non-negative integer." >&2; exit 2; }
is_non_negative_integer "$MAX_RETRIES" || { echo "Error: --max-retries must be a non-negative integer." >&2; exit 2; }
is_non_negative_integer "$RETRY_BACKOFF_MS" || { echo "Error: --retry-backoff-ms must be a non-negative integer." >&2; exit 2; }

if [[ ! -e "$SOURCE" ]]; then
  echo "Error: source path not found: $SOURCE" >&2
  exit 2
fi

UPLOAD_URL="${PROTOCOL}://${HOST}:${PORT}/soavirt/api/v6/files/upload"

url_encode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}


build_id_for_file() {
  local file_path="$1"
  local rel_path="$3"

  if [[ -n "$SINGLE_ID" ]]; then
    printf '%s' "$SINGLE_ID"
    return
  fi

  if [[ -n "$rel_path" ]]; then
    local prefix_no_trailing
    prefix_no_trailing="${ID_PREFIX%/}"
    if [[ -n "$prefix_no_trailing" ]]; then
      printf '%s/%s' "$prefix_no_trailing" "$rel_path"
    else
      printf '%s' "$rel_path"
    fi
    return
  fi
  if [[ -n "$ID_PREFIX" ]]; then
    printf '%s/%s' "${ID_PREFIX%/}" "$(basename "$file_path")"
    return
  fi

  printf '%s' "$(basename "$file_path")"
}

upload_one() {
  local file_path="$1"
  local upload_id="$2"
  local attempt=0
  local encoded_id
  local encoded_deploy
  local encoded_replace
  local response_file
  local error_file
  local curl_rc
  local http_code
  local body
  local err_body
  local auth_args=()

  encoded_id="$(url_encode "$upload_id")"
  encoded_deploy="$(url_encode "$DEPLOY")"
  encoded_replace="$(url_encode "$REPLACE")"

  if [[ -n "$BEARER_TOKEN" ]]; then
    auth_args=(-H "Authorization: Bearer ${BEARER_TOKEN}")
  elif [[ -n "$USERNAME" ]]; then
    auth_args=(-u "${USERNAME}:${PASSWORD}")
  fi

  while (( attempt <= MAX_RETRIES )); do
    attempt=$((attempt + 1))
    response_file="$(mktemp)"
    error_file="$(mktemp)"
    http_code="$(curl -sS \
      --max-time "$TIMEOUT_SECONDS" \
      "${auth_args[@]}" \
      -o "$response_file" \
      -w "%{http_code}" \
      -X POST \
      "${UPLOAD_URL}?id=${encoded_id}&deploy=${encoded_deploy}&replace=${encoded_replace}" \
      -F "file=@${file_path}" \
      2>"$error_file")"
    curl_rc=$?
    body="$(cat "$response_file")"
    err_body="$(cat "$error_file")"
    rm -f "$response_file" "$error_file"

    if [[ "$curl_rc" -eq 0 ]]; then
      if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        UPLOAD_LAST_STATUS="$http_code"
        UPLOAD_LAST_ERROR=""
        UPLOAD_LAST_BODY=""
        UPLOAD_LAST_ATTEMPTS="$attempt"
        return 0
      fi
      UPLOAD_LAST_STATUS="$http_code"
      UPLOAD_LAST_ERROR="http_status_${http_code}"
      UPLOAD_LAST_BODY="$body"
    else
      UPLOAD_LAST_STATUS=""
      UPLOAD_LAST_ERROR="curl_exit_${curl_rc}"
      UPLOAD_LAST_BODY="$err_body"
    fi

    if (( attempt <= MAX_RETRIES && RETRY_BACKOFF_MS > 0 )); then
      python3 - "$RETRY_BACKOFF_MS" <<'PY'
import sys
import time
time.sleep(float(sys.argv[1]) / 1000.0)
PY
    fi
  done

  UPLOAD_LAST_ATTEMPTS="$attempt"
  return 1
}

emit_progress() {
  local processed="$1"
  local total="$2"
  local failed="$3"
  local start_epoch="$4"
  local now
  local elapsed
  local percent
  local rate
  local eta

  now="$(date +%s)"
  elapsed=$((now - start_epoch))
  if (( total > 0 )); then
    percent=$((processed * 100 / total))
  else
    percent=100
  fi
  if (( elapsed > 0 )); then
    rate=$((processed / elapsed))
  else
    rate=0
  fi
  if (( rate > 0 )); then
    eta=$(((total - processed) / rate))
  else
    eta=-1
  fi

  emit_event "PROGRESS" \
    "uploaded" "$processed" \
    "total" "$total" \
    "failed" "$failed" \
    "percent" "$percent" \
    "elapsed_seconds" "$elapsed" \
    "rate_files_per_second" "$rate" \
    "eta_seconds" "$eta"
}

TMP_FILE_LIST="$(mktemp)"
cleanup() {
  rm -f "$TMP_FILE_LIST"
}
trap cleanup EXIT

if [[ -f "$SOURCE" ]]; then
  printf '%s\n' "$SOURCE" > "$TMP_FILE_LIST"
elif [[ -d "$SOURCE" ]]; then
  find "$SOURCE" -type f | LC_ALL=C sort > "$TMP_FILE_LIST"
else
  echo "Error: source must be a file or directory: $SOURCE" >&2
  exit 2
fi

TOTAL_FILES="$(wc -l < "$TMP_FILE_LIST" | tr -d '[:space:]')"
if [[ -z "$TOTAL_FILES" ]]; then
  TOTAL_FILES="0"
fi

MODE="upload"
if [[ "$DRY_RUN" == "true" ]]; then
  MODE="dry-run"
fi
AUTH_MODE="none"
if [[ -n "$BEARER_TOKEN" ]]; then
  AUTH_MODE="bearer"
elif [[ -n "$USERNAME" ]]; then
  AUTH_MODE="basic"
fi

emit_event "START" \
  "mode" "$MODE" \
  "source" "$SOURCE" \
  "total" "$TOTAL_FILES"

emit_event "PREFLIGHT" \
  "protocol" "$PROTOCOL" \
  "host" "$HOST" \
  "port" "$PORT" \
  "source" "$SOURCE" \
  "id_prefix" "$ID_PREFIX" \
  "single_id" "$SINGLE_ID" \
  "deploy" "$DEPLOY" \
  "replace" "$REPLACE" \
  "auth_mode" "$AUTH_MODE" \
  "log_format" "$LOG_FORMAT" \
  "quiet_success" "$QUIET_SUCCESS" \
  "progress_every" "$PROGRESS_EVERY" \
  "timeout_seconds" "$TIMEOUT_SECONDS" \
  "max_retries" "$MAX_RETRIES" \
  "retry_backoff_ms" "$RETRY_BACKOFF_MS" \
  "continue_on_error" "$CONTINUE_ON_ERROR" \
  "dry_run" "$DRY_RUN"

if [[ -n "$FAILURES_FILE" ]]; then
  : > "$FAILURES_FILE"
fi

FAILURES=0
PROCESSED=0
OK_COUNT=0
START_EPOCH="$(date +%s)"
LAST_PROGRESS_UPLOADED="-1"

while IFS= read -r file_path; do
  [[ -z "$file_path" ]] && continue

  rel_path=""
  if [[ -d "$SOURCE" ]]; then
    rel_path="${file_path#$SOURCE/}"
  fi
  upload_id="$(build_id_for_file "$file_path" "$SOURCE" "$rel_path")"

  if [[ "$DRY_RUN" == "true" ]]; then
    OK_COUNT=$((OK_COUNT + 1))
    if [[ "$QUIET_SUCCESS" != "true" ]]; then
      emit_event "DRYRUN" "file" "$file_path" "id" "$upload_id"
    fi
  else
    if upload_one "$file_path" "$upload_id"; then
      OK_COUNT=$((OK_COUNT + 1))
      if [[ "$QUIET_SUCCESS" != "true" ]]; then
        emit_event "OK" "file" "$file_path" "id" "$upload_id" "status" "$UPLOAD_LAST_STATUS" "attempts" "$UPLOAD_LAST_ATTEMPTS"
      fi
    else
      FAILURES=$((FAILURES + 1))
      emit_event "FAIL" \
        "file" "$file_path" \
        "id" "$upload_id" \
        "status" "${UPLOAD_LAST_STATUS:-none}" \
        "attempts" "$UPLOAD_LAST_ATTEMPTS" \
        "error" "$UPLOAD_LAST_ERROR"
      append_failure_artifact \
        "$file_path" \
        "$upload_id" \
        "${UPLOAD_LAST_STATUS:-none}" \
        "$UPLOAD_LAST_ATTEMPTS" \
        "$UPLOAD_LAST_ERROR" \
        "$UPLOAD_LAST_BODY"

      if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
        PROCESSED=$((PROCESSED + 1))
        emit_progress "$PROCESSED" "$TOTAL_FILES" "$FAILURES" "$START_EPOCH"
        LAST_PROGRESS_UPLOADED="$PROCESSED"
        break
      fi
    fi
  fi

  PROCESSED=$((PROCESSED + 1))
  if (( PROGRESS_EVERY > 0 )); then
    if (( PROCESSED % PROGRESS_EVERY == 0 || PROCESSED == TOTAL_FILES )); then
      emit_progress "$PROCESSED" "$TOTAL_FILES" "$FAILURES" "$START_EPOCH"
      LAST_PROGRESS_UPLOADED="$PROCESSED"
    fi
  fi
done < "$TMP_FILE_LIST"

END_EPOCH="$(date +%s)"
ELAPSED_SECONDS=$((END_EPOCH - START_EPOCH))

if [[ "$LAST_PROGRESS_UPLOADED" != "$PROCESSED" ]]; then
  emit_progress "$PROCESSED" "$TOTAL_FILES" "$FAILURES" "$START_EPOCH"
fi

emit_event "DONE" \
  "mode" "$MODE" \
  "total" "$TOTAL_FILES" \
  "ok" "$OK_COUNT" \
  "failed" "$FAILURES" \
  "elapsed_seconds" "$ELAPSED_SECONDS"

if [[ -n "$SUMMARY_FILE" ]]; then
  ensure_parent_dir "$SUMMARY_FILE" || { echo "Error: unable to create parent for summary file: $SUMMARY_FILE" >&2; exit 1; }
  python3 - "$SUMMARY_FILE" "$MODE" "$SOURCE" "$HOST" "$PORT" "$PROTOCOL" "$TOTAL_FILES" "$OK_COUNT" "$FAILURES" "$ELAPSED_SECONDS" "$LOG_FORMAT" "$QUIET_SUCCESS" "$PROGRESS_EVERY" "$MAX_RETRIES" "$TIMEOUT_SECONDS" "$RETRY_BACKOFF_MS" "$CONTINUE_ON_ERROR" "$FAILURES_FILE" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

(
    summary_file,
    mode,
    source,
    host,
    port,
    protocol,
    total_files,
    ok_count,
    failed_count,
    elapsed_seconds,
    log_format,
    quiet_success,
    progress_every,
    max_retries,
    timeout_seconds,
    retry_backoff_ms,
    continue_on_error,
    failures_file
) = sys.argv[1:]

summary = {
    "mode": mode,
    "source": source,
    "host": host,
    "port": int(port),
    "protocol": protocol,
    "total_files": int(total_files),
    "ok": int(ok_count),
    "failed": int(failed_count),
    "elapsed_seconds": int(elapsed_seconds),
    "log_format": log_format,
    "quiet_success": quiet_success == "true",
    "progress_every": int(progress_every),
    "max_retries": int(max_retries),
    "timeout_seconds": int(timeout_seconds),
    "retry_backoff_ms": int(retry_backoff_ms),
    "continue_on_error": continue_on_error == "true",
    "failures_file": failures_file if failures_file else None,
    "generated_at": datetime.now(timezone.utc).isoformat(),
}

path = pathlib.Path(summary_file)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
fi

if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi

exit 0

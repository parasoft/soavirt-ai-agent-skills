#!/usr/bin/env bash

set -o pipefail

usage() {
  cat <<'EOF'
Usage:
  bash soatest-scenario-execution-runner.sh --tst-file-id ID [options]

Required:
  --tst-file-id ID            SOAtest resource path

Optional:
  --host HOST                 SOAtest host (default: localhost)
  --port PORT                 SOAtest port (default: 9080)
  --protocol http|https       SOAtest protocol (default: http)
  --username USER             SOAtest username
  --password PASS             SOAtest password
  --bearer-token TOKEN        SOAtest bearer token
  --poll-interval-seconds N   Polling interval (default: 2)
  --max-wait-minutes N        Maximum wait time (default: 15)
  --execution-json JSON       Full execution request body
  --config CONFIG             SOAtest configuration ID
  --report-output-dir PATH    Directory for reports
                              (default: $TEMP/parasoft/soavirt/reports)
  --output-per-test-json      Also emit per-test JSON report
  --help                      Show this help text
EOF
}

default_report_output_dir() {
  local temp_base="${TEMP:-${TMPDIR:-/tmp}}"
  local report_dir="${temp_base}/parasoft/soavirt/reports"
  mkdir -p "$report_dir"
  printf '%s\n' "$report_dir"
}

TST_FILE_ID="" HOST="localhost" PORT="9080" PROTOCOL="http" USERNAME="" PASSWORD="" BEARER_TOKEN=""
POLL_INTERVAL_SECONDS="2" MAX_WAIT_MINUTES="15" EXECUTION_JSON="" CONFIG="soatest.builtin://Run Automated Server Tests"
REPORT_OUTPUT_DIR="" REPORT_OUTPUT_DIR_SPECIFIED="false" OUTPUT_PER_TEST_JSON="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --output-per-test-json) OUTPUT_PER_TEST_JSON="true"; shift ;;
    --tst-file-id|--host|--port|--protocol|--username|--password|--bearer-token|--poll-interval-seconds|--max-wait-minutes|--execution-json|--config|--report-output-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --tst-file-id) TST_FILE_ID="$2" ;; --host) HOST="$2" ;; --port) PORT="$2" ;; --protocol) PROTOCOL="$2" ;;
        --username) USERNAME="$2" ;; --password) PASSWORD="$2" ;; --bearer-token) BEARER_TOKEN="$2" ;;
        --poll-interval-seconds) POLL_INTERVAL_SECONDS="$2" ;; --max-wait-minutes) MAX_WAIT_MINUTES="$2" ;;
        --execution-json) EXECUTION_JSON="$2" ;;
        --config) CONFIG="$2" ;;
        --report-output-dir) REPORT_OUTPUT_DIR="$2"; REPORT_OUTPUT_DIR_SPECIFIED="true" ;;
      esac
      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$TST_FILE_ID" ]] || { echo "Error: --tst-file-id is required." >&2; usage; exit 2; }
[[ "$PROTOCOL" == "http" || "$PROTOCOL" == "https" ]] || { echo "Error: --protocol must be http or https." >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]+$ && "$POLL_INTERVAL_SECONDS" =~ ^[0-9]+$ && "$MAX_WAIT_MINUTES" =~ ^[0-9]+$ ]] || { echo "Error: numeric options must be non-negative integers." >&2; exit 2; }
for command_name in curl python3; do command -v "$command_name" >/dev/null || { echo "Error: $command_name is required." >&2; exit 2; }; done

if [[ "$REPORT_OUTPUT_DIR_SPECIFIED" != "true" ]]; then
  REPORT_OUTPUT_DIR="$(default_report_output_dir)"
fi
mkdir -p "$REPORT_OUTPUT_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/soatest-scenario-execution-helpers.sh"
initialize_soa_config "$HOST" "$PORT" "$PROTOCOL" "$USERNAME" "$PASSWORD" "$BEARER_TOKEN" 20

tst_base="$(basename "$TST_FILE_ID")"; tst_base="${tst_base%.tst}"
mkdir -p "$REPORT_OUTPUT_DIR"
run_timestamp="$(date +%s)"
report_base_name="${tst_base}-execution-report-${run_timestamp}"
report_dir="${REPORT_OUTPUT_DIR}/${report_base_name}" archive_path="${REPORT_OUTPUT_DIR}/${report_base_name}.zip" report_html="${report_dir}/report.html" job_id=""
cleanup() {
  if [[ -n "$job_id" ]]; then
    echo ""; echo "=== [3/3] Cleaning up execution history ==="
    if remove_soa_execution "$job_id"; then echo "  [OK] Deleted execution history for job: $job_id"; else echo "  [WARN] Could not delete execution history for job: $job_id"; fi
  fi
}
trap cleanup EXIT

echo ""; echo "=== [1/2] Executing tests: $TST_FILE_ID ==="
if [[ -n "$EXECUTION_JSON" ]]; then start_result="$(invoke_soa_execution_with_json "$EXECUTION_JSON")"; else start_result="$(invoke_soa_execution "$TST_FILE_ID" "$CONFIG")"; fi
if [[ "$start_result" == __SOA_EXECUTION_ERROR__* ]]; then
  response_payload="${start_result#__SOA_EXECUTION_ERROR__}"
  [[ -n "$response_payload" ]] && echo "[FATAL] Start execution response payload: $response_payload" >&2 || echo "[FATAL] Start execution response payload: <empty>" >&2
  exit 1
fi
job_id="$start_result"
[[ -n "$job_id" ]] || { echo "[FATAL] Could not start test execution. Aborting." >&2; exit 1; }
echo "[OK] Execution started: $job_id"
wait_soa_execution "$job_id" "$POLL_INTERVAL_SECONDS" "$MAX_WAIT_MINUTES" || exit 1

echo ""; echo "=== [2/2] Retrieving execution report ==="
results_file="$(mktemp)"
if ! get_soa_execution_results "$job_id" >"$results_file"; then echo "[FATAL] Could not retrieve execution results." >&2; exit 1; fi
if python3 - "$results_file" "$archive_path" <<'PY'
import base64
import json
import sys
data = json.loads(open(sys.argv[1], encoding='utf-8').read())
archive = data.get('reportArchive')
if not archive:
  raise SystemExit(1)
with open(sys.argv[2], 'wb') as output:
  output.write(base64.b64decode(archive))
PY
then
  rm -rf "$report_dir"
  python3 - "$archive_path" "$report_dir" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2])
PY
  rm -f "$archive_path"
  echo "  Execution report: $report_dir"
  report_xml="${report_dir}/report.xml"
  if [[ -f "$report_xml" ]]; then
    python3 - "$report_xml" "$report_dir" "$tst_base" "$OUTPUT_PER_TEST_JSON" <<'PY'
import html, json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path
xml_path, output_dir, tst_base, emit_per_test = sys.argv[1:]
root = ET.parse(xml_path).getroot(); project = root.find('.//Project')
if project is not None:
    total = int(project.attrib.get('total', 0)); passed = int(project.attrib.get('pass', 0))
    failed = int(project.attrib.get('fail', 0)) + int(project.attrib.get('err', 0))
    print(''); print('=== Test Execution Summary ===')
    print(f"  {'Total:':<9}{total}"); print(f"  {'Passed:':<9}{passed}"); print(f"  {'Failed:':<9}{failed}")
if emit_per_test == 'true':
    traffic = {n.attrib.get('tfcRef'): n for n in root.findall('.//Traffic')}; violations = {}
    for n in root.findall('.//FuncViol'): violations.setdefault(n.attrib.get('tfcRef'), n.attrib.get('msg'))
    results = []
    for test in root.findall('.//Test'):
        if 'status' not in test.attrib: continue
        item = {'testName': test.attrib.get('name'), 'status': test.attrib.get('status'), 'httpStatusCode': None, 'responseBody': None, 'violationMsg': violations.get(test.attrib.get('tfcRef'))}
        node = traffic.get(test.attrib.get('tfcRef'))
        if node is not None:
            match = re.search(r'HTTP/\d+\.\d+\s+(\d{3})', node.attrib.get('resHeaders', ''))
            item['httpStatusCode'] = int(match.group(1)) if match else None; item['responseBody'] = html.unescape(node.attrib.get('resBody', ''))
        results.append(item)
    path = Path(output_dir) / 'per-test-results.json'; path.write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(''); print('=== Per-Test Results ===')
    for item in results: print(f"  [{item['status'].upper():<4}] HTTP {item['httpStatusCode'] or '-':<4} | {item['testName']}")
    print(''); print(f'[OK] Per-test results: {path}')
PY
  fi
else
  rm -rf "$report_dir"
  mkdir -p "$report_dir"
  report_xml="${report_dir}/report.xml"
  python3 - "$results_file" "$report_xml" "$report_html" <<'PY'
import base64
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
written = False
for field, path in [('xmlReport', sys.argv[2]), ('htmlReport', sys.argv[3])]:
    value = data.get(field)
    if value:
        Path(path).write_bytes(base64.b64decode(value))
        written = True
if not written:
    raise SystemExit(1)
PY
  if [[ $? -eq 0 ]]; then
    echo "  Execution report: $report_dir"
    if [[ -f "$report_xml" ]]; then
      python3 - "$report_xml" "$report_dir" "$tst_base" "$OUTPUT_PER_TEST_JSON" <<'PY'
import html, json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path
xml_path, output_dir, tst_base, emit_per_test = sys.argv[1:]
root = ET.parse(xml_path).getroot(); project = root.find('.//Project')
if project is not None:
    total = int(project.attrib.get('total', 0)); passed = int(project.attrib.get('pass', 0))
    failed = int(project.attrib.get('fail', 0)) + int(project.attrib.get('err', 0))
    print(''); print('=== Test Execution Summary ===')
    print(f"  {'Total:':<9}{total}"); print(f"  {'Passed:':<9}{passed}"); print(f"  {'Failed:':<9}{failed}")
if emit_per_test == 'true':
    traffic = {n.attrib.get('tfcRef'): n for n in root.findall('.//Traffic')}; violations = {}
    for n in root.findall('.//FuncViol'): violations.setdefault(n.attrib.get('tfcRef'), n.attrib.get('msg'))
    results = []
    for test in root.findall('.//Test'):
        if 'status' not in test.attrib: continue
        item = {'testName': test.attrib.get('name'), 'status': test.attrib.get('status'), 'httpStatusCode': None, 'responseBody': None, 'violationMsg': violations.get(test.attrib.get('tfcRef'))}
        node = traffic.get(test.attrib.get('tfcRef'))
        if node is not None:
            match = re.search(r'HTTP/\d+\.\d+\s+(\d{3})', node.attrib.get('resHeaders', ''))
            item['httpStatusCode'] = int(match.group(1)) if match else None; item['responseBody'] = html.unescape(node.attrib.get('resBody', ''))
        results.append(item)
    path = Path(output_dir) / 'per-test-results.json'; path.write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(''); print('=== Per-Test Results ===')
    for item in results: print(f"  [{item['status'].upper():<4}] HTTP {item['httpStatusCode'] or '-':<4} | {item['testName']}")
    print(''); print(f'[OK] Per-test results: {path}')
PY
    fi
  else
    rmdir "$report_dir" 2>/dev/null || true
    echo "[WARN] Report archive not available in execution results."
  fi
fi
rm -f "$results_file"
echo ""; echo "=== DONE ==="; echo "  .tst file: $TST_FILE_ID"; [[ -d "$report_dir" ]] && echo "  Execution report: $report_dir"; [[ -f "$report_html" ]] && echo "  HTML report: $report_html" || echo "  HTML report: not generated"
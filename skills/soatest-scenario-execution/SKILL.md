---
name: soatest-scenario-execution
description: >
  Execute existing SOAtest .tst files and retrieve test results. Use when the user wants to: (1) run an existing .tst file on the SOAtest server, (2) execute a test suite and retrieve pass/fail results, (3) get a test execution report from SOAtest, or (4) re-run previously generated tests and see current results.
---

# SOAtest Scenario Execution

Execute an existing `.tst` file on the SOAtest server and retrieve the execution report.

## Path resolution contract (critical for agents)
- Treat all `scripts/...` references in this skill as paths relative to the directory containing this `SKILL.md` file.
- Define `<SKILL_DIR>` as the directory containing `SKILL.md`, then resolve script paths from `<SKILL_DIR>`.
- Do not assume the agent's current working directory is the skill directory.
- Use absolute script paths derived from `<SKILL_DIR>` whenever possible.

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `scripts/soatest-scenario-execution-helpers.ps1` | SOAtest API v6 execution operations: start execution, poll status, retrieve report archive |
| `scripts/soatest-scenario-execution-runner.ps1` | Runner: executes a `.tst` file by ID, extracts the execution report with a pass/fail summary, and optionally emits a per-test results JSON (`--output-per-test-json`) |
| `scripts/soatest-scenario-execution-helpers.sh` | Bash equivalent of the PowerShell helper functions |
| `scripts/soatest-scenario-execution-runner.sh` | Bash runner with the same execution, report, cleanup, and per-test JSON behavior |

Copilot does **not** dot-source or call the helper scripts directly. The runner script handles all of that.

The bash runner requires `bash`, `curl`, and `python3` (the Python standard library handles JSON and ZIP report parsing). The PowerShell runner requires PowerShell 5.1 or later. Choose the runner that matches the active terminal.

## Workflow

1. **Obtain SOAVirt API access** — call the `soavirtApiAccess` tool before any other SOAtest or SOAVirt REST API call. The successful response returns a full response path such as `https://myHost:9443/soavirt/api/v6/testExecutions`; from that value, extract the protocol, host, and port. Use the extracted protocol, host, and port for all subsequent SOAVirt REST API calls (for example, pass the extracted values as `--protocol`, `--host`, and `--port` arguments to the runner). If the tool returns an access token, pass it to the runner with `--bearer-token` and use that token for every subsequent SOAVirt REST API request. If the tool succeeds without returning a token, continue without bearer authentication because a token is not required. If the tool fails, stop and report the access failure.

2. **Identify the `.tst` file ID** — the SOAtest resource path, e.g. `/TestAssets/MyApi-Tests.tst`. When called from the `soatest-test-generation` skill, this is the path derived from the scenario name (`tstBase`) created in step 3 of that workflow. It can also be found by browsing the SOAtest workspace.

3. **Run the runner script** — immediately execute the runner via `run_in_terminal` (do not ask the user to run it). Resolve the script path from `<SKILL_DIR>` and do not assume the current working directory is the skill folder. Use the bash runner in a Linux/macOS/bash terminal and the PowerShell runner in a Windows PowerShell terminal. When `soavirtApiAccess` returns a token, include `--bearer-token "<access-token>"`; otherwise omit the authentication arguments.

  **Existing-result follow-up:** If the user asks for more information about a prior execution result, first use the existing execution report directory and read its `report.xml` (and, when present, `per-test-results.json`) instead of rerunning the scenario. Only rerun when no relevant report is available, the user explicitly requests a rerun, or the existing result cannot answer the question. Do not make another SOAtest API call just to answer a question that the existing report can answer.

   Bash:
   ```bash
   bash "<SKILL_DIR>/scripts/soatest-scenario-execution-runner.sh" \
     --tst-file-id "/TestAssets/MyApi-Tests.tst" \
     --host "<host-from-fullResourcePath>" --port <port-from-fullResourcePath> \
     --protocol "<protocol-from-fullResourcePath>" \
     --bearer-token "<access-token>" \
     --config "soatest.builtin://Run Automated Server Tests"
   ```

   PowerShell:
   ```
      powershell.exe -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\soatest-scenario-execution-runner.ps1" `
         --tst-file-id "/TestAssets/MyApi-Tests.tst" `
       --host "<host-from-fullResourcePath>" --port <port-from-fullResourcePath> --protocol "<protocol-from-fullResourcePath>" `
      --bearer-token "<access-token>" `
       --config "soatest.builtin://Run Automated Server Tests"
   ```
   For example, if `fullResourcePath` is `https://myHost:9443/soavirt/api/v6/testExecutions`, use `--host "myHost" --port 9443 --protocol "https"`, not `--host "localhost" --port 9080 --protocol "http"`.
   The runner accepts the following connection and execution arguments:
   - `--host` (default: `localhost`)
   - `--port` (default: `9080`)
   - `--protocol` (default: `http`, supports `http` and `https`)
   - `--username`
   - `--password`
   - `--bearer-token`
   - `--poll-interval-seconds` (default: `2` seconds)
   - `--max-wait-minutes` (default: `15` minutes)
   - `--execution-json` optionally supplies the complete test-execution request body as a JSON string. The runner sends it unchanged and uses it instead of the generated body from `--tst-file-id` and `--config`.
   - `--config` to specify the SOAtest test configuration (defaults to `soatest.builtin://Run Automated Server Tests`, which captures traffic for all tests regardless of pass/fail)
  - `--report-output-dir` to control where the execution report is saved. When omitted, both runners use and create the temp-based default report directory (`$env:TEMP/parasoft/soavirt/reports` for PowerShell and `$TEMP/parasoft/soavirt/reports` for Bash). The runner creates a unique report directory named `<tstBase>-execution-report-<unixEpochSeconds>`.
  - `--output-per-test-json` to also emit `per-test-results.json` inside the generated execution report directory, containing per-test HTTP status codes and response bodies. Include this flag only when the caller explicitly requests per-test response details; omit it for ordinary scenario execution requests.

   The bash runner accepts the same arguments and emits the same report directory and summary format. Invoke it with `bash "<SKILL_DIR>/scripts/soatest-scenario-execution-runner.sh" ...`; this does not depend on the agent's current working directory.

4. **Report results** — for a new execution, use the summary printed by the runner to report back. Include: `.tst` file path, execution report directory, test totals (Total/Passed/Failed), and the `HTML report:` line. The runner prints the full path to `report.html` when it was generated, or `HTML report: not generated` when it was absent. Do **not** infer HTML report availability from the execution-directory line. For follow-up questions about an existing execution, read the existing `report.xml` and/or `per-test-results.json` as needed instead of rerunning the scenario.

  > **Note for callers that need per-test response details** (e.g. `soatest-test-generation` step 5): pass `--output-per-test-json` to the runner. After execution completes the runner emits `per-test-results.json` inside the generated execution report directory, containing `testName`, `status`, `httpStatusCode`, `responseBody`, and `violationMsg` for every test. With the default `soatest.builtin://Run Automated Server Tests`, traffic is captured for all tests so `httpStatusCode` and `responseBody` are populated for passing tests too.

  > **Note for callers that need full execution settings:** callers may describe the desired execution settings in natural language and the agent can compose the `--execution-json` value from the `POST /testExecutions` schema. The request body must be a JSON object with required `general.config`; it may also include `general.localSettings` (name/value pairs), `general.nobuild`, `general.parallel`, `general.publish`, `general.showdetails`, `scopeOptions.workspace` (`resources`, `includes`, `excludes`, and `workItems` arrays), and `soatestOptions` (`dataGroupConfig`, `dataSource`, `environment`, `environmentConfig`, `router`, and `testNames`). Include `general.nobuild`, `general.parallel`, `general.publish`, or `general.showdetails` only when the user explicitly sets that field; otherwise omit it. Unless the user explicitly requests otherwise, always include `general.localSettings` with `report.archive` set to `true`. For example:
   > ```json
   > {
   >   "general": {
   >     "config": "soatest.builtin://Run Automated Server Tests",
   >     "localSettings": [
   >       {"name": "report.archive", "value": "true"}
   >     ],
   >     "nobuild": true,
   >     "parallel": false,
   >     "publish": false,
   >     "showdetails": true
   >   },
   >   "scopeOptions": {
   >     "workspace": {
   >       "resources": ["/TestAssets/MyApi-Tests.tst"]
   >     }
   >   }
   > }
   > ```
   > To execute only specific tests in the scenario, add `soatestOptions.testNames`. Each entry must be an object with a `value` property containing the exact test name:
   > ```json
   > {
   >   "general": {
   >     "config": "soatest.builtin://Run Automated Server Tests",
   >     "localSettings": [
   >       {"name": "report.archive", "value": "true"}
   >     ],
   >     "nobuild": true,
   >     "parallel": false,
   >     "publish": false,
   >     "showdetails": true
   >   },
   >   "scopeOptions": {
   >     "workspace": {
   >       "resources": ["/TestAssets/MyApi-Tests.tst"]
   >     }
   >   },
   >   "soatestOptions": {
   >     "testNames": [
   >       {"match": true,
   >        "value": "MyTest"}
   >     ]
   >   }
   > }
   > ```
   > For multiple tests, include one `{ "value": "..." }` object per exact test name. Pass this JSON unchanged through `--execution-json` together with the scenario's `--tst-file-id` and connection arguments.
   > Translate only the settings requested by the caller, preserve the schema property names and JSON types, and omit unspecified optional properties. Pass the resulting JSON string through `--execution-json`; the runner sends it unchanged instead of generating the standard body from `--tst-file-id` and `--config`.

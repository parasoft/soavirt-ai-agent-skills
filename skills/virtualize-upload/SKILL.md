---
name: virtualize-upload
description: Upload one file or a directory of files to the Virtualize REST API endpoint /v6/files/upload using a repeatable script that matches the user terminal (Linux bash or Windows PowerShell). Use this skill whenever the user OR any tool/MCP output indicates Virtualize file staging/upload, including phrases like "Invoke curl to stage this file by uploading it onto the server.", "stage this file", or "upload this file onto the server". Prefer this skill over ad-hoc curl when the target is Virtualize staging, even if /v6/files/upload is implied rather than explicitly named.
---

# Virtualize file upload skill

Use this skill to upload files to `POST /soavirt/api/v6/files/upload`.
It is also useful for staging files before virtual asset or virtual service creation steps.
## Path resolution contract (critical for agents)
- Treat all `scripts/...` references in this skill as paths relative to the directory containing this `SKILL.md` file.
- Define `<SKILL_DIR>` as the directory containing `SKILL.md`, then resolve script paths from `<SKILL_DIR>`.
- Do not assume the agent's current working directory is the skill directory.
- Use absolute script paths derived from `<SKILL_DIR>` whenever possible.

## High-priority trigger cues (including MCP/tool output)
- Trigger this skill when `manageVirtualServices` or another MCP/tool response says: `"Invoke curl to stage this file by uploading it onto the server."`
- Trigger this skill for equivalent staging language such as:
  - "stage this file"
  - "upload this file onto the server"
  - "upload/stage assets before creating or deploying the virtual service"
- Treat file-staging instructions as sufficient trigger context even when the endpoint path is not explicitly shown.

## What this skill provides
- A Linux bash script at `<SKILL_DIR>/scripts/upload_virtualize_files.sh` that uploads:
  - one file, or
  - all files inside a directory (recursive)
- A Windows PowerShell script at `<SKILL_DIR>/scripts/upload_virtualize_files.ps1` that uploads:
  - one file, or
  - all files inside a directory (recursive)
- Support for:
  - `--host` and `--port`
  - required `id` behavior
  - optional `deploy` and `replace`
  - optional auth:
    - basic auth (`--username`/`--password` or `VIRT_USERNAME`/`VIRT_PASSWORD`)
    - bearer auth (`--bearer-token` or `VIRT_BEARER_TOKEN`)
  - `--quiet-success` and `--progress-every` for manageable logs during long runs
  - `--log-format text|jsonl` for human-readable or machine-readable event streams
  - `--summary-file` and `--failures-file` artifacts for downstream agent steps
  - `--timeout-seconds`, `--max-retries`, and `--retry-backoff-ms` for resilience
  - `--continue-on-error` and `--dry-run` for controllable execution behavior

## API contract used
- Endpoint: `POST /soavirt/api/v6/files/upload`
- Query params:
  - `id` (required)
  - `deploy` (optional boolean)
  - `replace` (optional boolean)
- Body: `multipart/form-data` field `file`

## How to run
The examples below show invocations rooted at the skill folder. When generating commands from another location, resolve the script path from `<SKILL_DIR>` and invoke that full path.

### Linux terminal (bash) single file
```bash
./scripts/upload_virtualize_files.sh \
  --host localhost \
  --port 9080 \
  --source ./my-asset.pva \
  --id "VirtualAssets/my-asset.pva"
```

### Linux terminal (bash) directory upload
```bash
./scripts/upload_virtualize_files.sh \
  --host localhost \
  --port 9080 \
  --source ./assets \
  --id-prefix "VirtualAssets"
```

### Linux terminal (bash) agent-friendly directory upload
```bash
./scripts/upload_virtualize_files.sh \
  --host localhost \
  --port 9080 \
  --source ./assets \
  --id-prefix "VirtualAssets" \
  --quiet-success true \
  --progress-every 25 \
  --summary-file ./upload-summary.json \
  --failures-file ./upload-failures.jsonl
```

### Linux terminal (bash) with auth from environment variables
```bash
VIRT_USERNAME=admin VIRT_PASSWORD=secret \
./scripts/upload_virtualize_files.sh \
  --host localhost \
  --port 9080 \
  --source ./assets \
  --id-prefix "VirtualAssets"
```

### Linux terminal (bash) with bearer token
```bash
./scripts/upload_virtualize_files.sh \
  --host localhost \
  --port 9080 \
  --source ./assets \
  --id-prefix "VirtualAssets" \
  --bearer-token "{{VIRT_BEARER_TOKEN}}"
```

### Windows terminal (PowerShell) single file
```powershell
.\scripts\upload_virtualize_files.ps1 `
  --host localhost `
  --port 9080 `
  --source .\my-asset.pva `
  --id "VirtualAssets/my-asset.pva"
```

### Windows terminal (PowerShell) directory upload
```powershell
.\scripts\upload_virtualize_files.ps1 `
  --host localhost `
  --port 9080 `
  --source .\assets `
  --id-prefix "VirtualAssets"
```

### Windows terminal (PowerShell) agent-friendly directory upload
```powershell
.\scripts\upload_virtualize_files.ps1 `
  --host localhost `
  --port 9080 `
  --source .\assets `
  --id-prefix "VirtualAssets" `
  --quiet-success true `
  --progress-every 25 `
  --summary-file .\upload-summary.json `
  --failures-file .\upload-failures.jsonl
```

### Windows terminal (PowerShell) with bearer token
```powershell
.\scripts\upload_virtualize_files.ps1 `
  --host localhost `
  --port 9080 `
  --source .\assets `
  --id-prefix "VirtualAssets" `
  --bearer-token "{{VIRT_BEARER_TOKEN}}"
```

## Agent execution profile (recommended)
For large directory uploads, prefer:
- `--quiet-success true` to avoid flooding output with per-file success lines.
- `--progress-every 25` (or another interval) so progress is visible throughout the run.
- `--summary-file <path>` so the next agent step can parse totals and status.
- `--failures-file <path>` so only failures need detailed follow-up.
- `--log-format jsonl` when machine parsing of live logs is needed.

The scripts now emit deterministic lifecycle events:
- `START` once at beginning
- `PREFLIGHT` once with resolved options
- `PROGRESS` periodically
- `OK` (unless quiet mode)
- `FAIL` on each failed file
- `DONE` once at completion

In `jsonl` mode these events are emitted as one JSON object per line.

## Notes for LLM usage
- Choose the script by terminal type:
  - Linux bash terminal: use `<SKILL_DIR>/scripts/upload_virtualize_files.sh`.
  - Windows PowerShell terminal: use `<SKILL_DIR>/scripts/upload_virtualize_files.ps1`.
- When Virtualize staging/upload is requested, use this skill's scripts first instead of composing ad-hoc `curl` commands.
- This skill is a good fit when files need to be staged in Virtualize before virtual asset/service creation workflows.
- When generating commands, resolve script paths from `SKILL.md` location (`<SKILL_DIR>`), while user data paths such as `--source`, `--summary-file`, and `--failures-file` should follow the user's intended working directory unless absolute paths are provided.
- For single-file upload:
  - if `--id` is omitted, the script uses the file basename as `id`.
- For directory upload:
  - each file id is built as `<id-prefix>/<relative-path>` (or just relative path when no prefix is set).
- If `--bearer-token` is set (or `VIRT_BEARER_TOKEN` is present), bearer auth is used and takes precedence over basic auth settings.
- If any file fails, the script exits non-zero and can write failure details to `--failures-file`.
- Use `--dry-run true` to preview resolved file paths and upload IDs without sending requests.
- Do not trigger this skill for non-Virtualize uploads (for example generic S3/object-storage uploads) unless the workflow explicitly targets Virtualize staging.

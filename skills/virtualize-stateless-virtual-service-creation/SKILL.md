---
name: virtualize-stateless-virtual-service-creation
description: >-
  Create a complete **stateless** virtual-service representation folder (a flat folder of fixed request/response file pairs - Parasoft Virtualize-style) from an API definition (OpenAPI, Swagger, WSDL, etc), from a sample set of request/response files, or from a description of the stateless service provided by the user.
  Use this skill with the "manageVirtualServices" SOAVirt MCP tool whenever the user wants a **stateless** virtual service, stateless mock, stateless service virtualization asset, or fixed-response simulated backend built for it — even if they only say things like "build a stateless service for this API", "build a mock from these request/response files", "build a service as described below", "build a service that supports the following operations", "create a stateless virtual service".
  Do not use this skill if the user explicitly asks for a **stateful** service whose responses must depend on data persisted across calls; use the stateful virtual-service creator skill for that case instead.
context: text
---

# Virtualize Stateless Virtual Service Creator

## What this skill produces

Given an API definition, a folder of sample request/response pairs, or a description for some service, you produce a **service representation folder**: a flat folder of paired request/response files that implements the operations in the given service as a **stateless** virtual service. Each request file captures a fixed request pattern; its paired response file is the fixed response that is always returned when a matching request arrives. There is no state carried between calls — the same request always yields the same response.

Trigger this skill when the user wants to create a STATELESS virtual service. Once the request/response representation folder has been constructed, ask the user if they would like to deploy the service on the server. If they confirm deployment, prefer one `manageVirtualServices` call with `action=create` and `directoryPath` set to the representation folder, regardless of whether the service was derived from an API definition, sample request/response pairs, or a description. The only exception is a very simple service with exactly one request/response pair and no other interactions or documented statuses to create: for that case, a single `action=create` call with `requestContent` and `responseContent` is acceptable. For update actions - to add or update a single request/response pair to an already deployed existing service - calling the tool with `requestContent` and `responseContent` may be acceptable. Do not use pair-based creation/updating for services where multiple pairs would be involved; create/update those in one call from the complete folder. If the user has not supplied the tool's `name` and `deployment`, ask for them rather than inventing values.

When you are not given an API definition for the service but are given other artifacts that can be used to define it (e.g. a sample of request/response pairs which capture service behavior, a description of the service, or an outline of its operations) you should first examine the given artifacts and understand the service and its operations. You may clarify or validate with the user the list of operations and their request/response structure if it's not clear from the artifacts what the service looks like exactly.

The service representation folder is simply a directory containing one `*_request.txt` / `*_response.txt` file pair per interaction (one pair per operation, per documented response status).

---

## About the examples in this skill

**This skill uses the classic Petstore API as a running example throughout**, featuring pets, categories, tags, and store orders. The example request/response pairs shown here follow this naming and content pattern:

```
_pet_findByStatus_GET_request.txt   _pet_findByStatus_GET_response.txt
_pet_petId_POST_request.txt         _pet_petId_POST_response.txt
_pet_POST_request.txt               _pet_POST_response.txt
_pet_PUT_request.txt                _pet_PUT_response.txt
_store_inventory_GET_request.txt    _store_inventory_GET_response.txt
_store_order_POST_request.txt       _store_order_POST_response.txt
```

These examples are **instructional patterns** showing the flat file-pair layout, the naming convention, and the `.http`-style content format. **Apply these patterns to ANY API or service specification the user provides.** The Petstore service is simply a concrete example demonstrating the conventions you must follow — replace the specific entities, operations, and fields with those from the user's actual service specification. The Petstore example is for a JSON service, but the actual user service may be in JSON or XML.

---

## Step 1 — Examine the service

### Scope: which operations to include

When building from an API definition, the user may want the service to cover **all** operations in the definition, or only a **particular subset** (e.g. "just the pet endpoints", "only GET operations", "everything except the delete operations"). Determine the intended scope before generating anything:

- If the user's request already names or clearly implies the subset of operations they want, honor that subset exactly — do not add extra operations from the definition that were not requested, and do not silently drop requested ones.
- If the user gives no scoping instruction at all, default to covering **every** operation in the API definition.
- If it is ambiguous whether the user wants the full API or a subset, ask before generating files.
- The representation folder must contain request/response pairs **only** for the operations (and, per operation, only the statuses) actually in scope — do not pad the folder with out-of-scope operations or statuses "for completeness."

### Scope: which statuses to include

The user may also give instructions about which documented response status codes to include or exclude (e.g. "only success responses, skip the error cases", "include 404s but not 500s"). Apply those instructions exactly:

- If the user specifies which statuses they want, generate file pairs only for those statuses.
- If the user gives no instruction on statuses, default to the general rule elsewhere in this skill: one pair for the success response plus one pair per documented error status.

### Default request wildcarding (API-definition-driven generation)

When building the service from an **API definition** (OpenAPI, Swagger, WSDL, etc.), this wildcard-by-default behavior applies **only to the success-status request/response pair** for each operation. If the API definition also documents error statuses for an operation (e.g. `400`, `404`, `500`) and the user wants those error-status interactions included in the service, the request file for **each error-status pair must not be wildcarded** — populate its path parameters, query parameters, and body (as applicable) with concrete, realistic sample values representing the specific error case documented for that status, exactly as you would for a user-supplied sample request. See "Matching request and response fields to build inline expressions" below for the corresponding rule on error-status responses.

For the success-status pair, default every generated request file to a **wildcard match** for that operation, so that all requests for that operation return the matching success response rather than only one specific example value:

- **Path parameters**: leave each `{param}` segment as the bare parameter name in braces (e.g. `/pet/{petId}`) instead of substituting a concrete example value — per the wildcard rules in "Request-Response Correlation and Matching" below, `{parameterName}` already matches any value in that segment.
- **Query parameters** (if the operation has any): replace the entire query string with the full wildcard `?{*}` instead of enumerating example query values.
- **Request body**: for any HTTP method that may carry a body (e.g. `POST`, `PUT`, `PATCH`), include the payload wildcard `{*}` as the body — do this **regardless of whether the API definition documents a request body for that specific operation**. Only omit the body entirely for methods that never carry one (e.g. `GET`, `DELETE`, `HEAD`).

For example, given an API definition operation `POST /pet/{petId}` with a path parameter, a query parameter, and a request body, the default generated request wildcards all three:

```
POST /pet/{petId}?{*} HTTP/1.1

{*}
```

A couple more examples generated this way from the classic Petstore API definition — wildcarding only the parts of the request that are actually present:

`_store_order_orderId_GET_request.txt` (path parameter wildcarded; no query string or body on this operation):
```
GET /store/order/{orderId} HTTP/1.1

```

`_user_createWithList_POST_request.txt` (body wildcarded; no path or query parameters on this operation):
```
POST /user/createWithList HTTP/1.1

{*}
```

The paired response file is still the fixed, documented response body for that status — wildcarding only affects the request-matching pattern, not the response content, and does not prevent the response from using inline expressions to extract values out of whatever request actually arrives at runtime (see "Inline Expressions for Dynamic Responses" below).

This wildcard-by-default behavior applies specifically to the success-status pair of requests generated **from an API definition**. It does not apply to error-status pairs (see above), it does not apply when the user supplies concrete sample request/response pairs to reuse verbatim — reuse those exact values as documented in "Sample request" below — nor does it override an explicit user instruction to generate exact-match examples for specific documented cases.

### Data generation instructions

The user may give instructions about what kind of data should populate the generated request/response bodies (e.g. "IDs should be 3-digit numbers", "use realistic-looking names", "dates should be in 2025", "phone numbers should be US-formatted"). When such instructions are given:

- Apply them consistently to every generated field they logically cover, across all request and response files
- Where an instruction conflicts with a value taken verbatim from a user-supplied sample request/response, prefer the user's explicit data-generation instruction for newly generated fields, but do not alter sample values the user explicitly asked to reuse verbatim.

If the user gives no data-generation instructions at all, generate appropriate, realistic example values for each field based on its name, type, and format in the schema (as shown in the Petstore examples throughout this skill) — do not leave placeholder or nonsensical values.

Read the whole spec, request/response sample set, or description. For every operation capture:

- The **request shape**: HTTP method, URL path, path parameters, query parameters (required vs optional, types), and request body structure (if any).
- Every **response status** documented for the operation — the success code **and** each error code (e.g. 400/404/409/500). **Each documented status becomes its own request/response file pair.**
- The exact **response body structure** for each status, including realistic example values.
- Whether responses are static/fixed or need a small amount of dynamic content (e.g. an echoed request value, a generated timestamp, a correlation id) — this determines whether an inline expression is needed (see the "Inline Expressions" section below).
- Whether the operation's behavior depends only on the request content itself (always true for a stateless service) — if the user's description implies state that must persist and influence later responses, do not use this skill but use the stateful virtual-service creator skill instead. This skill only produces fixed, stateless request/response pairs.

If any of this is unclear from the given artifacts, ask the user to clarify or confirm the list of operations and their statuses before generating files.

### Matching request and response fields to build inline expressions (API-definition-driven generation)

When the service is being built from an **API definition** (OpenAPI, Swagger, WSDL, etc.), do not treat every response field as a fixed, independently-generated example value. For **each operation in scope**, before writing the example response body, examine the request and its response together field by field and try to identify which response fields are actually echoing data supplied by the caller in that same request, rather than being purely server-generated (e.g. a generated id, computed total, timestamp, or status determined by business logic):

1. For each field in the response payload, check whether its value plausibly originates from the request.
2. If it looks like it does, identify the specific source field in the request that supplies it. There are three source cases to consider:
   - The value comes from a **field in the request payload**.
   - The value comes from a **path parameter** in the request URL.
   - The value comes from a **query parameter** in the request URL.
3. If a plausible source field is found, replace the generated example value for that response field with the matching inline expression (see "Inline Expressions for Dynamic Responses" below) that extracts the value from the identified source:
   - From a request body field: `${{=/root/fieldName/text()}}` (adjust the XPath to the field's actual location in the request body).
   - From a path parameter: `${{=sv:url-path-param('parameterName', '/url/template/{parameterName}')}}`, matching by the parameter's name against a short operation URL path template — never by segment index. Use the documented parameter name if known, otherwise choose an appropriate descriptive name and use it consistently in both the function call and the template. Keep the template to just the one placeholder plus at most one stable segment on either side (see "Extract URL path parameters" below).
   - From a query parameter: `${{=sv:url-parameter('parameterName')}}`.
4. If no plausible source field exists in the request (the value is server-generated, computed, or otherwise not something the caller supplied), leave it as a realistic generated example value, following any user-given data generation instructions.

**Do not match on name alone.** Two fields sharing the same name in the request and response payloads are not automatically the same value — use the surrounding path and payload context (what the field represents, where it sits in the schema, what the operation does) to judge whether the response field is genuinely echoing that request field before wiring up an inline expression. For example, an `id` field in a request body that identifies a *related* resource is not necessarily the source for an `id` field in the response that identifies the *created* resource — the latter is more likely server-generated.

Apply this field-matching pass only to the **success-status** request/response pair produced for the operation, so its response file contains a mix of inline expressions for values extracted from the request and appropriate generated example values (following any user-given data instructions) for values that do not come from the request. **Error-status response pairs do not get this treatment by default**: since their paired request is populated with concrete sample values rather than wildcarded (see "Default request wildcarding" above), their response bodies should use fixed, realistic example values (following any user-given data instructions) rather than inline expressions extracting from the request, unless the user explicitly asks for dynamic error responses.

---

## Step 2 — Design the interactions

Before generating any files, go through **every** operation and **every** documented status for that operation, in the order they appear in the spec/description, and design the interaction pair:

1. **Sample request** — the exact method, path (with path/query parameters), and body (if any) that should trigger this response. When building from an API definition, default the **success-status** interaction's path parameters, query parameters, and body to wildcards per "Default request wildcarding" above; for **error-status** interactions, populate concrete, realistic sample values instead (not wildcards). When the user supplied example requests or a sample request/response set, reuse their exact values so the generated request file matches verbatim instead.
2. **Correlation strategy** — decide whether this interaction should match exactly (a specific path/query/body value) or should use a wildcard (see "Request-Response Correlation and Matching" below). When building from an API definition, default the success-status interaction to the wildcard strategy described above so the operation responds identically regardless of the actual id/query/payload value; error-status interactions default to an exact match against concrete sample values instead. Fall back to an exact match for the success interaction only for a documented example the user explicitly supplied or asked to keep verbatim.
3. **Sample response** — the fixed response body and status code that should always be returned for that request pattern. This must come directly from the API's documented response structure for that status.
4. **Dynamic content, if any** — note any response fields that should be computed at response time (timestamps, echoed request values, extracted headers/URL parts) and the inline expression that will produce them. When building from an API definition, this must include the field-matching pass described in "Matching request and response fields to build inline expressions" above, which applies only to the success-status pair — error-status responses use fixed example values by default, not inline expressions.

Present this design (the list of interactions with their sample request/response pairs) to the user before generating files if the service has many operations or the mapping from description to interactions is non-obvious.

---

## Step 3 — Generate the folder

Use a camelCase service name ending in `Service` (e.g. `PetStoreService`). Build a **flat** folder (no subfolders) directly under it:

```
<ServiceName>/
├── _<pathGroup>_<METHOD>[_<STATUS>]_request.txt
├── _<pathGroup>_<METHOD>[_<STATUS>]_response.txt
└── ... (one request/response pair per operation, per documented status)
```

> **Note:** The examples that follow use the Petstore API as an instructional reference. Apply the same file naming and content conventions to the actual entities and operations from the user's API.

### Naming and sanitization rules

- Each interaction is a **pair of files** sharing the same base name: `<base>_request.txt` and `<base>_response.txt`.
- **Base name construction**: take the API path, drop the leading `/`, replace every remaining `/` with `_`, and replace each `{param}` path segment with the bare parameter name (drop the braces). Then append `_<METHOD>` (uppercase). So `/pet/findByStatus` + `GET` → `_pet_findByStatus_GET`, and `/pet/{petId}` + `POST` → `_pet_petId_POST`.
- **Error/status suffix**: the success responder for an operation omits any status suffix (e.g. `_pet_POST_request.txt` / `_pet_POST_response.txt`). For each documented **error status**, append the status code before the `_request`/`_response` suffix, e.g. `_pet_petId_GET_404_request.txt` / `_pet_petId_GET_404_response.txt` for a documented 404 on `GET /pet/{petId}`. If an operation only ever has one documented non-2xx case that always applies (e.g. a single generic validation error), the status suffix still applies so the pair is unambiguous.
- Do not produce names with consecutive underscores; squish multiple consecutive underscores into a single one.
- Create **one file pair per documented status**: the success pair plus one pair for each documented error code.

### File content format

Both files are plain-text, `.http`-style content — these examples are for a JSON service, but the actual user service may use XML.

**`*_request.txt`**:
- First line: `<METHOD> <path>[?<queryParams>] HTTP/1.1`. When building from an API definition, default path parameters to `{paramName}` (left in braces, not a concrete value) and query parameters to the full wildcard `?{*}` **for the success-status pair**, per "Default request wildcarding" above. For an **error-status pair**, write concrete, realistic path/query values representing that error case instead — do not wildcard them. Also write concrete path/query values when reusing a user-supplied sample request verbatim or an intentional exact-match example.
- Optional header lines (e.g. `Content-Type: application/json; charset=UTF-8`) may follow the request line — headers are informational only and are never used for correlation (see below).
- A blank line.
- The request body for `POST`/`PUT`/`PATCH` (or any other method that may carry a body). When building from an API definition, default this to the payload wildcard `{*}` **for the success-status pair** per "Default request wildcarding" above, **even if the API definition does not document a request body for that operation**. For an **error-status pair**, use a concrete, realistic sample body representing that error case instead of a wildcard — the same applies when reusing a user-supplied sample verbatim or an intentional exact-match example. Bodyless requests (`GET`/`DELETE`/etc.) have nothing here. If the API specifies a genuinely empty body, leave it empty — not even `{}`.

**`*_response.txt`**:
- First line: `HTTP/1.1 <status>`.
- Optional header lines (e.g. `Content-Type: application/json; charset=UTF-8`).
- A blank line.
- The fixed response body for that status (or nothing for `204 No Content`).

**Instructional examples** (Petstore API — adapt the path, method, and body structure to match the user's actual API). These show the exact-match style, e.g. for a user-supplied sample request/response to reuse verbatim; when generating from an API definition, apply the wildcard defaults from "Default request wildcarding" above instead (see the wildcarded versions of these same examples in "Request-Response Correlation and Matching" below):

`_pet_findByStatus_GET_request.txt`:
```
GET /pet/findByStatus?status=available HTTP/1.1

```

`_pet_findByStatus_GET_response.txt`:
```
HTTP/1.1 200
Content-Type: application/json; charset=UTF-8

[ {
  "id" : 10,
  "name" : "doggie",
  "category" : {
    "id" : 1,
    "name" : "Dogs"
  },
  "photoUrls" : [ "https://example.com/images/doggie.png" ],
  "tags" : [ {
    "id" : 0,
    "name" : ""
  } ],
  "status" : "available"
} ]
```

`_store_order_POST_request.txt`:
```
POST /store/order HTTP/1.1
Content-Type: application/json; charset=UTF-8

{
  "id" : 10,
  "petId" : 198772,
  "quantity" : 7,
  "shipDate" : "",
  "status" : "approved",
  "complete" : false
}
```

`_store_order_POST_response.txt`:
```
HTTP/1.1 200
Content-Type: application/json; charset=UTF-8

{
  "id" : 10,
  "petId" : 198772,
  "quantity" : 7,
  "shipDate" : "",
  "status" : "approved",
  "complete" : false
}
```

For an error status pair (e.g. a documented `500` when required parameters are missing/invalid), follow the same file-pair naming with the status suffix, and give the response a fixed error body matching whatever the API documents for that status (or a simple descriptive error payload if the API does not specify one).

---

## General Rules for the `manageVirtualServices` MCP Tool

These rules apply whenever using the `manageVirtualServices` MCP tool to create or manage the stateless virtual service produced by this skill. They encode known tool behaviors and common agent mistakes to avoid.

### `deployment` Parameter and Request Path Overlap

The HTTP path in the generated request files — or in the `requestContent` field, for the single-pair creation case described above — must never repeat or overlap segments in the `deployment` path that the user specifies as the virtual service's base deployment path. The server prepends the deployment path to every request at runtime, so duplicating it in the files would make requests never match.

For example, if the user asks for `deployment` path `petstore`, generated paths must look like `GET /pet/findByStatus`, `POST /pet/{petId}`, or `POST /store/order` — never `GET /petstore/pet/findByStatus`, `POST /petstore/pet/{petId}`, or `POST /petstore/store/order`.

Apply this rule as follows, before calling `manageVirtualServices`:
- If **every** path in the service overlaps with the `deployment` path (starts with it, or — for a multi-segment `deployment` path — shares its leading segment(s)), strip the overlapping leading segment(s) from every path written to the files (or passed via `requestContent`).
- If **even one** path in the service has no overlap with the `deployment` path, leave **all** service paths unchanged — never strip segments from some paths but not others.

**Examples:**

| `deployment` | Service paths | Overlap check | Resulting paths |
|---|---|---|---|
| `pet` | `/pet/names`, `/pet/{id}`, `/pet/{id}/order` | All start with `/pet` | `/names`, `/{id}`, `/{id}/order` |
| `/v1/pet/` | `/pet/names`, `/pet/{id}`, `/pet/{id}/order` | All overlap on the `pet` segment | `/names`, `/{id}`, `/{id}/order` |
| `/v1/pet/` | `/pet/names`, `/pet/{id}`, `/pet/{id}/order`, `/customer/names`, `/customer/{id}` | `/customer/*` paths don't overlap with `pet` | Unchanged — all paths kept exactly as given |

### Empty Request Bodies

When a story specifies that the request body is empty (no payload), the request file must truly contain no payload — not even `{}`. Virtualize matching is payload-sensitive: a request file with no payload will fail to match an incoming request that carries any body content, and vice versa. When testing empty-body interactions, send POST requests that genuinely omit any body content.

### Downloading, Modifying, and Re-uploading Request/Response Files

It is normal and expected for an agent to download the request/response files of an existing virtual service in order to enrich or extend them — for example, to add inline expressions, correlation rules, or additional interactions — and then re-upload the modified files back to the server.

Before downloading and re-uploading files, consider whether a simpler path applies:
- **Fixing or replacing the response for a specific interaction** (e.g. correcting an inline expression, changing a status code) — call `manageVirtualServices action=update` with `requestContent` set to the matching request and `responseContent` set to the corrected response. No download or file manipulation is needed.
- **Adding a new interaction** — same as above; each `action=update` call appends a new request/response pair.
- **Bulk modifications across many interactions, or changes that cannot be expressed via `requestContent`/`responseContent`** — use the `directoryPath` or staging workflow below.

**Preferred approach — `directoryPath` on `update`**: after downloading and modifying files locally, call `manageVirtualServices` with `action=update` and `directoryPath` set to the local directory containing the modified files (the representation folder produced by this skill). This bypasses the upload API entirely and is the simplest path.

**Alternative — upload zip and `commitFromStaging`**: if the `directoryPath` approach is not applicable, use the full staging workflow:
1. **Download** — call `manageVirtualServices action=download`. The tool creates a staging directory on the server and returns the zip download URL and staging path.
2. **Modify** — download the zip, extract, edit the request/response files locally.
3. **Re-upload** — POST the modified zip back to the staging path using `multipart/form-data` with a field named `file`:
   ```
   POST /soavirt/api/v6/files/upload?id=<stagingPath>&replace=true
   Content-Type: multipart/form-data; boundary=<boundary>

   --<boundary>
   Content-Disposition: form-data; name="file"; filename="<service>.zip"
   Content-Type: application/zip

   <binary zip content>
   --<boundary>--
   ```
   The endpoint returns `HTTP 415` for `application/octet-stream` or `application/zip` as the top-level content type — `multipart/form-data` is the only accepted form.
4. **Commit** — call `manageVirtualServices action=update` with `commitFromStaging` set to the staging directory name returned in step 1.

---

## Request-Response Correlation and Matching

When creating the request/response file pairs, define correlation and matching so that incoming requests are correctly matched to the appropriate fixed response.

### Correlation and matching rules

- Correlate primarily from the request first line: HTTP method, URL path, and URL query parameters.
- Also correlate on the request body content specified after headers, when a body exists.
- Do not use request headers as correlation keys; headers present in request files are informational and must not drive match selection.
- Path matching behavior:
  - Incoming requests are allowed to have any number of additional URL path segments prepended.
  - The final path segments of the incoming request must match the configured request path segments in the request file.
  - When multiple candidates match, select the candidate with the greatest number of matching path segments.
  - If multiple candidates tie on segment count, select the candidate whose filename comes first alphabetically.
- Multi-interaction implementation guidance:
  - When the task context implies multiple request/response behaviors for the same endpoint (e.g. one pair per documented status), create distinct file pairs that preserve deterministic matching under the rules above.
  - Prefer explicit exact-match interactions for known story examples before adding broader wildcard patterns — except when building from an API definition, where the wildcarded form is the default **for the success-status pair only** (see "Default request wildcarding" above). Error-status pairs always use concrete sample values, never wildcards, even when built from an API definition.

### Wildcard rules

- Wildcards are supported, but exact matches always take precedence over wildcard matches.
- URL path wildcard forms:
  - `*` in a path segment to match any value in that segment.
  - `{parameterName}` in a path segment to match any value in that segment — the text inside `{parameterName}` is descriptive only and does not change matching behavior.
- URL query wildcard form:
  - Use `?{*}` as the full query-string wildcard to match any query value set, e.g. `POST /parabank/services/bank/billpay?{*}`.
- Payload wildcard form:
  - Use `{*}` as the entire payload to match any request body.
- Regex and pattern limitations:
  - Regular expressions are not supported for URL or payload matching.
  - To model distinct non-wildcard variants, create separate exact request/response file pairs rather than relying on regex-like patterns.

**Instructional examples using wildcards** (Petstore API — same file names as the exact-match examples, but with wildcard request content):

`_pet_findByStatus_GET_request.txt`:
```
GET /pet/findByStatus?{*} HTTP/1.1

```

`_pet_petId_POST_request.txt`:
```
POST /pet/{petId}?{*} HTTP/1.1

{*}
```

`_store_order_POST_request.txt`:
```
POST /store/order HTTP/1.1

{*}
```

When building from an API definition, this wildcarded form is the **default** for the **success-status** request file of every operation — per "Default request wildcarding" above, wildcard the path parameters, query parameters, and body so the operation responds identically regardless of the actual id/query/payload value. **Error-status request files are never wildcarded by default** — populate them with concrete sample values representing the documented error case instead (see "Default request wildcarding" above). Fall back to an exact request/response pair for the success interaction only for a documented, concrete example the user explicitly supplied or asked to keep verbatim.

---

## Inline Expressions for Dynamic Responses

A stateless response is normally fully fixed, but a small amount of dynamic content is still allowed and often expected (timestamps, echoed request values, extracted headers/URL parts). Use inline expressions **in the response files** to generate these values at response time.

### Syntax

All inline expressions use the `${{=expression}}` format.

- Use **single quotes only** in expressions (`'` not `"`).
- Do not use curly brackets `{}` inside expressions or default values.
- Default values use the `#` separator: `${{=expression#defaultValue}}`.

### Date-time manipulation

Current time with offset:
```
${{=sv:date-math('offset', 'outFormat')}}
```
Example: `${{=sv:date-math('0h', 'yyyy-MM-dd HH:mm:ss')}}`. Use explicit date patterns for `outFormat`; avoid aliases such as `ISO8601`, which may fail depending on runtime date parser support.

**⚠ Avoid literal `T` and `Z` inside a format string argument** — the Virtualize date parser treats `T` and `Z` as pattern letters (or a combined `TZ` timezone token), so embedding them directly in a format string causes a runtime error such as `Unknown pattern letter: TZ`.

Do **not** do this:
```
${{=sv:date-math('0h', 'yyyy-MM-ddTHH:mm:ss.SSS')}}Z
```

ISO 8601 workaround — split into two expressions:
```
${{=sv:date-math('0h', 'yyyy-MM-dd')}}T${{=sv:date-math('0h', 'HH:mm:ss.SSS')}}Z
```
This produces output like `2026-06-02T16:49:14.827Z` by placing the literal `T` and `Z` as plain text between and after the two `date-math` calls.

Offset format: `'1y 2M 3d 4h 5m 6s'` (can be positive or negative, units optional).

Specify a date with offset: `${{=sv:date-math('offset', 'format', 'date')}}`, e.g. `${{=sv:date-math('1y', 'yyyy-MM-dd', '2022-08-11')}}`.

Different input/output formats: `${{=sv:date-math('offset', 'outFormat', 'date', 'inFormat')}}`, e.g. `${{=sv:date-math('1y', 'MM/yyyy', '2022-08-11', 'yyyy-MM-dd')}}`.

With a default value: `${{=sv:date-math('1y', 'yyyy-MM-dd', /root/date/text())#2000-01-01}}`.

### Extract request values (XPath)

Extract JSON/XML values from the incoming request with `${{=/root/fieldName/text()}}`. For example, given a request body `{"accountNumber":"12345","transactionId":"abc-xyz"}` (parsed as XML-shaped paths), a response can include:
```json
{
  "requestedAccount": "${{=/root/accountNumber/text()}}",
  "correlationId": "${{=/root/transactionId/text()}}"
}
```

### Extract headers

```
${{=sv:header('headerName')}}
```
With index (if multiple headers with same name): `${{=sv:header('headerName', 2)}}`. With default: `${{=sv:header('Authorization')#noAuth}}`.

### Extract URL parameters

```
${{=sv:url-parameter('parameterName')}}
```
Example: request to `GET /api?accountId=999&type=premium` →
```json
{ "account": "${{=sv:url-parameter('accountId')}}", "tier": "${{=sv:url-parameter('type')}}" }
```
resolves to `{ "account": "999", "tier": "premium" }`.

### Extract URL path parameters (by name, via template matching)

```
${{=sv:url-path-param('parameterName', '/url/template/{parameterName}')}}
```
**Never extract path parameter values by segment index.** Always extract by matching the parameter's name against the operation's URL path template, where the parameter appears as a `{parameterName}` placeholder in that template.

**Keep the template short and containing exactly one path parameter** — the single one being extracted. Include **at most one stable (literal) segment before it and at most one stable segment after it**; drop any other segments, and never include more than one `{parameterName}` placeholder in the same template. If a nearby segment isn't needed to disambiguate, omit it.

Example: request `GET /pet/123` for the operation template `/pet/{petId}` → `${{=sv:url-path-param('petId', '/pet/{petId}')}}` resolves to `123`.

When the parameter's name isn't documented or known, choose an appropriate, descriptive name and use that same name both in the function call and as the placeholder in the template. Example: extracting the customer id from `GET /customers/123/orders`, where the path is shaped like `/customers/{customerId}/orders` → `${{=sv:url-path-param('customerId', '/customers/{customerId}/orders')}}` resolves to `123`.

When the operation has multiple path parameters, build a **separate, short template per parameter** rather than one long template covering all of them — each template should still have only one placeholder, with at most one stable segment on each side. For example, for `GET /users/{userId}/orders/{orderId}`:
- Extract `userId` with either `${{=sv:url-path-param('userId', '/users/{userId}')}}` (no segment after) or `${{=sv:url-path-param('userId', '/users/{userId}/orders')}}` (one stable segment after, if needed to disambiguate).
- Extract `orderId` with `${{=sv:url-path-param('orderId', '/orders/{orderId}')}}` (one stable segment before; the `userId` segment further back is dropped).

### Validating requests before using inline expressions

Before adding an inline expression to a response, always check the corresponding request file to ensure the data exists.

❌ **Problem**: a request with no XML/JSON body paired with a response using `${{=/root/accountNumber/text()}}` — there is nothing to extract.

✅ **Solution**: extract from the URL path instead, matching by name against a short path template, e.g. for a request to `GET /api/v1/cards/accounts/12345` (template `/accounts/{accountNumber}` — just the one stable segment immediately before the parameter): `"accountNumber": "${{=sv:url-path-param('accountNumber', '/accounts/{accountNumber}')}}"`.

✅ **Works**: a request that includes header `X-User-ID: user456` paired with a response using `${{=sv:header('X-User-ID')}}` resolves to `user456`.

⚠ **Fallback**: a response referencing a header that the request does not send, e.g. `${{=sv:header('X-User-Name')#unknown}}`, resolves to the **default** value `unknown`.

### Troubleshooting

**Error: `Unknown pattern letter` from `sv:date-math`** — cause: the date format contains unsupported pattern letters or uses an alias not recognized by the runtime parser. Fix: use explicit supported patterns such as `yyyy-MM-dd HH:mm:ss`; do not use aliases like `ISO8601`.
- ❌ `${{=sv:date-math('0h', 'ISO8601')}}`
- ✅ `${{=sv:date-math('0h', 'yyyy-MM-dd HH:mm:ss')}}`

### Common patterns

Echo request with dynamic timestamp:
```json
{
  "requestedId": "${{=/root/id/text()}}",
  "processedAt": "${{=sv:date-math('0h', 'yyyy-MM-dd HH:mm:ss')}}"
}
```

Correlation using request parameter:
```json
{
  "correlationId": "${{=sv:url-parameter('traceId')#unknown}}",
  "timestamp": "${{=sv:date-math('0h', 'yyyy-MM-dd HH:mm:ss')}}"
}
```

Extract from header:
```json
{
  "userId": "${{=sv:header('X-User-ID')#anonymous}}",
  "accountId": "${{=sv:url-path-param('accountId', '/accounts/{accountId}')}}",
  "createdAt": "${{=sv:date-math('0h', 'yyyy-MM-dd HH:mm:ss')}}"
}
```

### Applying inline expressions to an already-deployed service

When adding or fixing inline expressions on a service that already exists on the server (rather than during initial generation):
1. Edit the response file locally (in the downloaded/staged representation folder).
2. Re-check the corresponding `*_request.txt` file to confirm the field, header, or URL part being extracted is actually present in the request.
3. Add or correct the inline expression in the response body.
4. Save the file and push the change back using the `directoryPath` or staging workflow described in "Downloading, Modifying, and Re-uploading Request/Response Files" above.
5. Commit the change (`commitFromStaging` if using the staging workflow) and validate by sending a live test request.

---

## Final checklist

Before delivering the service representation folder, verify:

- [ ] Every operation in the API/description has a matching set of request/response file pairs, one pair per documented response status.
- [ ] File base names follow the `_<pathSegments>_<METHOD>[_<STATUS>]` convention, with parameterized path segments named (braces dropped) and no consecutive underscores.
- [ ] Success pairs omit the status suffix; every documented error status has its own suffixed pair.
- [ ] Each `*_request.txt` first line is `<METHOD> <path>[?query] HTTP/1.1`, followed by a blank line and the request body (or nothing, if the API defines an empty body — never `{}` in that case).
- [ ] Each `*_response.txt` first line is `HTTP/1.1 <status>`, followed by a blank line and the fixed response body (or nothing for `204`).
- [ ] Request paths never duplicate the `deployment` path segments: if every service path overlapped with `deployment`, the overlapping leading segment(s) were stripped from all paths; if any single path had no overlap, all paths were left unchanged (see "`deployment` Parameter and Request Path Overlap" above).
- [ ] Correlation strategy chosen per interaction: exact match for documented examples, wildcard (`*`, `{parameterName}`, `?{*}`, `{*}`) only where the response is intentionally the same for any value.
- [ ] Any dynamic response content uses a valid inline expression, and the corresponding request file actually contains the data the expression extracts (body field, header, or URL part).
- [ ] When built from an API definition, each response field was checked against the request (payload field, path parameter, query parameter) for a plausible source, using context rather than name-matching alone, and wired up with an inline expression where a genuine match was found.
- [ ] The folder is a flat set of request/response file pairs only.
- [ ] The design (list of interactions with sample request/response pairs) was shown to the user before file generation, if the service has many operations.

---
name: soatest-guided-api-test-creation
description: >-
  Interactively plan and build an API testing scenario based on an API definition (OpenAPI, Swagger, WSDL, etc.) if available, and other user-specified parameters.
  Use this skill when the user wants to plan and/or build a testing scenario for their API service or endpoint.
  Do not use this skill to create other kinds of tests, such as JUnit tests.
context: text
---

# Guided API Test Creation

## Prerequisites and Limitations

- In order to perform this skill, the `SOAtest` MCP server must be available. Before starting the workflow below, check the connection to this server by calling the `getStatus` MCP tool (or equivalent lightweight MCP health tool). If the connection fails, instruct the user to `Ensure the SOAtest Server is started and accessible` and ask how to resolve the issue.
- This skill only supports HTTP and HTTPS services.

## Workflow steps

1. Greet the user and prompt them to choose between the following, to define how to test their API service:
  - A service definition (WSDL, GraphQL SDL, OpenAPI, or XSD schema) URL or local file
  - Human-readable specification document URL or file
  - Raw traffic (`.har`) file
  - Manual entry of the endpoint and operations

Follow the instructions below according the user's choice to collect the HTTP endpoint(s), HTTP method(s), endpoint sub-paths, query parameters (if any), HTTP headers (if any), request/response message formats/schemas/examples, and HTTP response code(s).

2. Construct a list of several scenarios for the user, designed to test the operations of the API service. Ask the user to select one of the scenarios or specify their own. Include a suggested name for each scenario.

  - List only the scenario descriptions; do not show the steps, extractions, or validations unless requested by the user.
  - If needed, plan test steps to retrieve values that are needed for the operation under test. If the response message format is `XML` or `JSON`, build the expression(s) used to locate the value(s) to extract from the response payload; ensure the expression(s) conform to the description for response payload extractions in the `addTest` MCP tool input schema.
  - Plan the request and expected response values for the operation under test. If the response message format is `XML` or `JSON`, build the expression(s) used to locate the value(s) to validate from the response payload; ensure the expression(s) conform to the description for response payload assertions in the `addTest` MCP tool input schema. Response value validation for other message formats (neither `XML` nor `JSON`) is not supported.
  - For each test, include baseline validations for expected HTTP response status and key response fields (if applicable). Do not consider response content-type or performance metric validations. 
  - Consider other operations to call after the operation under test to verify the service state. For example: after adding an item to a shopping cart, get the shopping cart to verify that the added item is present.
  - Consider scenarios with test steps to validate error and boundary conditions, validated with assertions or expected response codes.
  - Consider adding teardown steps to return the API service to its original state. For example: After adding an item to a shopping cart, clear the cart at the end of the test.
  - The last step in a scenario will never need extracted values

Once the user has chosen a scenario, confirm the scenario name and steps with the user before continuing.

3. Ask the user if they would like to parameterize their scenario with an existing CSV (.csv) or Excel (.xls or .xlsx) file, generate a CSV data set, or use fixed values.

  - If the user chooses to use fixed values, collect the values to use for inputs and validations, and confirm these values with the user.
  - If the user chooses to use an existing CSV (.csv) file, prompt the user for the path to the file and then follow the `Using an Existing CSV Data Source` instructions below.
  - If the user chooses to use an existing Excel (.xls or .xlsx) file, prompt the user for the path to the file and then follow the `Using an Existing Excel Data Source` instructions below.
  - If the user chooses to generate a CSV data set, follow the `Generating a CSV Data Source` instructions below.

4. Use `SOAtest` MCP server tools to:

  - First, create the scenario with the `createScenario` MCP tool.
  - Second, if the scenario will be parameterized, use the `addDataSource` tool to add the data source to the scenario. Use the `Verifying a Data Source` instructions below to verify the result and correct issues before proceeding.
  - Third, use the `addTest` tool to add test steps to the scenario, including extractions and assertions (with expressions from step 2) as needed, and either fixed, parameterized, or extracted values. For each extraction added, note the extraction name for use in subsequent test steps.  Include a service definition in the test steps whenever one is available.
  - Fourth, use the `describeScenario` tool to verify the structure of the scenario and the order of test steps. If it does not match the expected structure, use other available `SOAtest` MCP server tools to fix and verify the scenario.
  - Finally, use the `describeTest` tool to verify each test step, including extractions and assertions. If the tool response includes a response payload `contentAsXML` field, check the extraction and assertion expression(s) against this XML to verify they will work as expected and fix any issues using the `modifyTest` MCP tool.

If any MCP tool call fails, ask the user how to resolve the issue before continuing; do not attempt to automatically fix and retry the MCP call unless the problem and the fix are trivial and obvious.

5. Provide a short description of the scenario and a summary of the test steps that were created. Do not attempt to run the test; this is not supported by the `SOAtest` MCP server. Do not show raw secrets; show masked values instead.

## Service definition (WSDL, GraphQL SDL, OpenAPI, or XSD schema) URL or local file

Retrieve the service definition using the `makeHTTPRequest` MCP tool, and read it to collect the available operations.

  - If you are unable to load the service definition: notify the user with the message `The service definition cannot be loaded. Double-check if the given URL refers to the service definition (WSDL, GraphQL SDL, OpenAPI, XSD schema, etc)` and ask whether to retry, change the service definition URL, or cancel.
  - Always use the `makeHTTPRequest` MCP tool to retrieve the service definition.
  - If the service definition is large, extract and use only the operation list and the schemas relevant to the selected operation(s). If needed, ask the user to narrow the operation scope before proceeding.

Confirm the API service endpoint with the user before continuing.

## Human-readable specification document URL or file

Load and read the document from the URL or file provided and collect available operations. If unable to load the document, ask the user for guidance before proceeding. Once the document has been loaded, ask the user which operation(s) they would like to focus their scenario on, if any. Prompt the user for any missing or incomplete information related to their chosen operation(s).

## Raw traffic (`.har`) file

Since the traffic file may include traffic that is un-related to the API service under test, first collect and group together the endpoints and operations from the traffic file. Ask the user which endpoint(s) they would like to create a scenario for.

Once the user has selected the endpoint(s) for their API service, collect information from the traffic file only for interactions with those selected endpoints. Note any security-related values (authorization, keys, cookies, sessions, passwords, or other secrets) - these must be excluded when creating and configuring tests steps later. Note the order in which calls occur in the traffic and identify temporary values which must be retrieved via one operation and passed to another (for example, using a GET to retrieve a list of products, then a POST to add one by ID to a shopping cart).

Review the request and response messages and headers for the selected endpoints to determine if they are `XML`, `JSON`, or another format. Attempt to detect whether these messages are SOAP, plain XML, GraphQL, plain JSON, or another format. Confirm the message format, service type, and content types of the request and response with the user. If an interaction's request includes an `accept` header, include it when creating a test based on the interaction.

## Manual entry of the endpoint and operations

Collect information about the API service using the following steps:

1. Prompt for the API service type (RESTful, SOAP, GraphQL, or Other). If the service is SOAP, ask which version (1.1 or 1.2).
2. Prompt for the base service endpoint.
3. Collect the set of operations available, adding one at a time until the user is done:
  - If the service is SOAP: collect the operation name or SOAPAction (if required by the service); assume the HTTP method is POST and all operations use the same endpoint. Prompt for example request and response messages.
  - For a RESTful or Other service: collect the HTTP method, endpoint sub-path, and query parameters (if any).
  - For GraphQL: collect the HTTP method, path, operation type (`query`/`mutation`), operation text, variables payload (if applicable), endpoint sub-path, query parameters (if any), and the GraphQL query to use for the request.
  - For all service types: collect HTTP headers (if any; excluding headers related to authorization, keys, cookies, sessions, passwords, or other secrets - these should be automatically configured by the MCP server), example request and response messages (if allowed for the HTTP method), expected status codes, and key response fields to validate (if an example response is available, and either `XML` or `JSON`).

## Using an Existing CSV Data Source

The goal of these steps is to verify the proper configuration for reading the .csv file and collect the column names to use in test steps.

1. Verify the .csv file exists and is readable - if not, notify the user and prompt them to provide either a correct path or to cancel this skill.

2. Notify the user that you will use the following configuration to read the file. Ask the user to either confirm or change the configuration to use:

  - The character encoding for the file - for example: `UTF-8` or `ISO-8859-1`; defaults to `UTF-8`
  - The first row in the data source defines column names - `true` or `false`; defaults to `true`
  - The separator between values - for example: `,` or `;`; defaults to `,`
  - The quote character used to quote field values containing separators, line breaks, or other special characters - for example: `"` or `'`; defaults to `"`

3. Parse the first record of the .csv file using the configured separator, quote, and encoding from the previous step; take care to properly handle the UTF-8 BOM if present.

  - If the configuration indicates that the first row defines column names, use this record as the list of available column names.
  - If the configuration indicates that the first row does not define column names, count the number of values in the record and generate the column names: `Column 0`, `Column 1`, `Column 2`, ...
  - If successful, confirm the list of column names with the user; otherwise, ask the user how to correct the issue and try again.

## Using an Existing Excel Data Source

The goal of these steps is to verify that the specified file exists and is readable, and collect the Excel sheet name and column names to use in test steps.

1. Verify the .xls or .xlsx file exists and is readable - if not, notify the user and prompt them to provide either a correct path or to cancel this skill.

2. Prompt the user for the sheet name, and list of column names that the sheet will have.

3. Read the entire file as bytes, then convert those bytes to a base64 string. Encode the file exactly as stored on disk. Do not modify, compress, transform, or escape the file before encoding. When decoded, the resulting byte stream must be identical to the original file contents. Do not attempt to load or parse the workbook, or validate the columns or sheet in the file at this time; validation and correction of the sheet and columns will occur later in the workflow.

## Verifying a Data Source

When calling `addDataSource` to add a data source to the scenario, check the result for issues:

  - First, verify the call succeeded and the returned set of column names matches the expected column names from previous workflow steps.
  - If using a CSV data source and the returned column names do not match the expected column names, ask the user how they would like to fix the issue before proceeding and use `modifyDataSource` to apply the requested changes.
  - If using an existing Excel file and an error occurred because the specified sheet name does not exist, prompt the user for the correct sheet name and try the `addDataSource` call again.
  - If using an existing Excel file and the returned column names do not match the expected column names, ask the user whether they would like to fix the issue by updating the sheet name with `modifyDataSource`, using the returned column names instead, or cancel and exit this skill. If the user chooses to use the returned column names, update the mapping of column names to input and output values and confirm these updates with the user before proceeding.
  - If any changes were made with `modifyDataSource`, perform the checks in this section again on the `modifyDataSource` result until all issues are resolved.

## Generating a CSV Data Source

The goal of this section is to construct a data source which will satisfy the testing requirements of the scenario.

  - Each column will map to either an input value to use in a request or output to validate. Columns can be re-used across multiple test steps.
  - Each row of values will be used for an iteration of the entire scenario as it executes. Values cannot be used to control which rows apply to which test steps.
  - Interactively review the data set with the user and confirm the correct mapping of column names to test inputs and outputs.
  - Build the data set in CSV format, where the first row indicates column names. Use `,` as the separator, and wrap any value that contains a special character (for example: newlines or `,`) in double-quotes (`"`). Be sure to escape double-quotes if they are part of the value.

# AI Agents for SOAtest and Virtualize

## Table of Contents

1. [Overview](#overview)
2. [Skills](#skills)
3. [Adding Custom Instructions to a Skill](#adding-custom-instructions-to-a-skill)

---

## Overview

Parasoft SOAtest and Virtualize AI Solutions extend your AI coding agent with the following skills:

### SOAtest

- `soatest-scenario-execution` for invoking a specific test scenario
- `soatest-guided-api-test-creation` for planing and building test scenarios for API services or endpoints

### Virtualize

- `virtualize-stateful-virtual-service-creation` for creating a stateful virtual service
- `virtualize-stateless-virtual-service-creation` for creating a stateless virtual service
- `virtualize-upload` for uploading files from the local machine to the Virtualize Server

These skills are described in detail below.

---

## Installation

Install these skills in the `skills` directory used by your LLM client (e.g., `.github/skills/` or `.agents/skills/`). If you're not certain what the correct directory is, check your LLM client's documentation.

---

## Skills

### SOAtest

#### soatest-scenario-execution

This skill is used to invoke a specific scenario. If the SOAVirt server requires authentication, the skill will obtain an access token and use it for subsequent calls to the SOAVirt server.

You can invoke the skill directly or by using a prompt like, "Execute the scenario with the id '/TestAssets/MyTests.tst'."

#### soatest-guided-api-test-creation

This skill is used to plan and/or build testing scenarios for API services or endpoints. It is designed to be interactive and can use API definitions (OpenAPI, Swagger, WSDL, and so on) or work just with parameters you specify.

This skill only supports HTTP and HTTPS services.

It is recommended that you invoke this skill directly when you want to use it.

### Virtualize

#### virtualize-stateful-virtual-service-creation

This skill creates a complete stateful virtual-service representation folder (MongoDB-backed - Parasoft Virtualize-style responders) from an API definition (OpenAPI, Swagger, WSDL, etc), from a sample set of request/response files, or from a description of the stateful service provided by the user. This folder is then used by the "manageVirtualServices" SOAVirt MCP tool to create the stateful virtual service on the Virtualize server.

#### Prerequisite

Before creating a stateful asset, you will need to configure the connection settings for a Data Repository Server that the MCP server can use. Do this under Parasoft > Preferences > Data Repository Servers.

#### How to Invoke

The following examples demonstrate prompts that invoke this skill to create a stateful virtual asset:

- "Create a stateful virtual service called demoApp for service definition c:\temp\demo-app-v1.json."

- "Create a stateful virtual service using the sample request and response traffic pairs in the shoppingCartTraffic folder."

- "Create a stateful virtual service called shoppingCart. It should have resources for items, customers and carts. Items should have id, name and price. Customers should have id, name, email."

**Notes**

- Be sure you have installed the stateful skill before using MCP to create stateful assets.

- Replace details like "demoApp", "shoppingCartTraffic", and "shoppingCart" with names appropriate to your request.

- Be sure to include the word "stateful" in your request; the LLM is likely to create stateless assets unless otherwise directed.

- You MCP client might have trouble creating a stateful virtual service from more than a handful of request/response pairs. If you experience this, ask the client to create an API definition file from traffic files first and create a stateful service from that definition.

### virtualize-stateless-virtual-service-creation

This skill creates a complete stateless virtual-service representation folder (a flat folder of fixed request/response file pairs - Parasoft Virtualize-style) from an API definition (OpenAPI, Swagger, WSDL, etc), from a sample set of request/response files, or from a description of the stateless service. This folder is then used by the "manageVirtualServices" SOAVirt MCP tool to create the stateless virtual service on the Virtualize server.

### virtualize-upload

This skill is used to help upload files from the local machine to the Virtualize Server. This skill is automatically used by AI Coding Agents when the Virtualize MCP server directs the agent to upload files.

---

## Adding Custom Instructions to a Skill

You might want to add your own custom instructions to a skill to improve its performance for your specific scenario/environment. It is strongly recommended that you do this by creating a complementary instruction file rather than making changes to the default instruction file. Simply create a complementary instruction file (e.g., *my.instructions.md*) and save it in the **instructions** folder that is adjacent to the **skills** folder containing the skill in question. It will be loaded and used alongside default instructions file for the skill.

The following is an example of a complementary instruction file for the `virtualize-stateful-virtual-service-creation` skill.

```
    ---
    description: "Additional customized guidance for **virtualize-stateful-virtual-service-creation** skill. Use when creating a stateful virtual-service representation folder with the virtualize-stateful-virtual-service-creation skill. The instructions here should be added to those in the skill and any specifics here should take precedence over those in the virtualize-stateful-virtual-service-creation skill."
    ---
    
    # Additional Instructions for Stateful Virtual Service Creator
    
    ## JavaScript File Header
    
    All JavaScript files generated for the stateful virtual service must include this header comment at the beginning:
    
    ```javascript
    /*
    
    This is automatically generated code, you may modify manually as appropriate.
    
    */
    ```
    
    This applies to all `.js` files created in the virtual service folder structure.
    
    ## Script.js Comment Exclusion
    
    For `script.js` files specifically, **do not include** the sample request and sample response comments that are normally added at the top and bottom of generated files.
    
    The `script.js` file should start immediately with the header comment above, followed directly by the JavaScript code, without any embedded sample request/response documentation comments.
```

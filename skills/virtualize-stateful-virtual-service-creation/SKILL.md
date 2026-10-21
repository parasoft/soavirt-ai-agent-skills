---
name: virtualize-stateful-virtual-service-creation
description: >-
  Create a complete **stateful** virtual-service representation folder (MongoDB-backed - Parasoft Virtualize-style responders) from an API definition (OpenAPI, Swagger, WSDL, etc), from a sample set of request/response files, or from a description of the stateful service provided by the user.
  Use this skill with the "manageVirtualServices" SOAVirt MCP tool whenever the user wants a **stateful** virtual service, stateful mock, stateful service virtualization asset, or stateful simulated backend built for it — even if they only say things like "build a stateful service for this API", "build a stateful service from these request/response files", "build a stateful service as described below", "build a stateful service that supports the following operations/workflow", "create a stateful virtual service".
  Do not use this skill unless the user asks explicitly for a **stateful** service.
context: text
---

# Virtualize Stateful Virtual Service Creator

## What this skill produces

Given an API definition, a folder of sample request/response pairs, or a description for some service, you produce a **service representation folder** which implements the operations in the given service as a stateful virtual service backed by a MongoDB repository. Trigger this skill when the user wants to create a STATEFUL virtual service and you will need to invoke the "manageVirtualServices" SOAVirt MCP tool, which requires the stateful virtual-service representation folder in order to create the stateful service on the server. Once the stateful virtual-service representation folder has been constructed ask the user if they would like to deploy the service on the server. If they confirm deployment:
1- Make sure you have confirmed the database name (in data_source/data_source_config.yaml) with the user. This is only a name, there are no MongoDB server settings required. If the user gives you a name different from that in data_source/data_source_config.yaml file in the representation folder, update the databaseName in data_source/data_source_config.yaml to what the user asked for before uploading the service to the server.
2- Call the "manageVirtualServices" SOAVirt MCP tool to create the stateful service on the server. Do not tell the user they need to initialize the database, the server will run the scripts automatically.

When you are not given an API definition for the service but are given other artifacts that can be used to define the service (e.g.: you may be given a sample of request/response pairs which capture service behavior, or a description of the service, or an outline of its operations, or the client workflow the service should support) you should first examine the given artifacts and understand the service and its operations. You may clarify or validate with the user the list of operations and their request/response structure if it's not clear from the artifacts what the service looks like exactly. Then:
1- **You must create an API definition file.**
2- **You must write that API definition file to disk.**
3- **You must share with the user the API defintion file you will be working from.**
4- **You must proceed with the construction of the service representation folder from the API definition file.**

Regardless of what the user instructions are regarding data storage or data manipulation (e.g. SQL database, SQL instructions) remember that the user is only describing service behavior and not implementation. The stateful service you will construct will always be backed by a MongoDB database.

The service representation folder has two halves:

1. **`data_source/`** — connection config plus MongoDB initialization scripts that create the collections, validators, indexes, ID counters, and some seed data (generate by default some sample seed data for each of the created collections unless the user asks you not to).

2. **`responders/`** — one responder per API operation (and per documented error status), each containing a sample request, a sample response, matching rules, and a `script.js` that reads/writes MongoDB to update state and power the response.

The whole point is a **stateful** mock: `GET` reflects whatever `POST`/`PUT`/`DELETE` did before it. State lives in MongoDB; `script.js` is the glue.

---

## About the examples in this skill

**This skill uses a Shopping Cart API as a running example throughout**, featuring customers, items, and carts with denormalized relationships. 

These examples are **instructional patterns** showing:

- **Folder structure**: How to organize the service representation folder, data source files, and responder hierarchies
- **MongoDB init**: How to define collections, validators, indexes, counters, and seed data in `init_files/*.js`
- **Responder structure**: How to create `matching.yaml`, `request_sample.http`, `response_sample.http`, `responder_config.yaml`, and `suite_config.yaml` files
- **Script.js patterns**: How to write MongoDB operations that maintain state and handle denormalized data propagation

**Apply these patterns to ANY API or service specification the user provides.** The Shopping Cart Service is simply a concrete example demonstrating the conventions you must follow. Replace the specific entities (customers, items, carts), fields, and operations with those from the user's actual service specification. The Shopping Cart example is for a JSON service but the actual user service may be in JSON or in XML.

---

## Non-negotiable design-first rule

Do **not** start creating files until you have finished the backend design. The quality of the service depends entirely on getting the MongoDB schema right. 

Work in this order:

1. **Examine** the given API, or the given request/response pairs, or the given service description in detail to understand the service. Understand the operations, the entities, their relationships and their constraints. Understand the request structure, any parameters (path parameters, query parameters, payload parameters) and the response structure for each operation. Understand whether the response is a list/array of a single object.

2. **Design** the MongoDB backend and **write out the design analysis** (the two deliverables below) for the user.

3. **Generate** the folder, deriving `init_files/*.js` and every `script.js` directly from that design.

> **Important:** Announce and present the design analysis before generating files. If the user gave you a spec with many resources, this design step is where you prevent an incoherent result.

---

## Step 0 — Validate the created API with the user

If the user did not provide an API for the service and you created the API from request/response files or form a user description/requirements for the service:
- Save the API to a file
- Inform the user the service API was created and ask for their confirmation to proceed based on the API only.

If the user gave you an API no need to perform this step.

---

## Step 1 — Examine the API

Read the whole spec. For every path + method, capture:

- The **resources/entities** and their fields, types, required-ness, nested objects, arrays, and enums (from `components/schemas`).

- The **relationships** between entities (e.g. a cart contains items and belongs to a customer). Note which responses **embed** another entity's data vs. just reference an id.

- **Path parameters, Query parameters, Request payloads** path parameters become MongoDB filters, request bodies become writes, and query parameters become filters/pagination.

- Every **response status** documented per operation — the success code **and** each error code (400/404/409/...). **Each documented status becomes its own responder.** For each error response (e.g., HTTP 400, 404, 409, etc.), you must create a separate responder with a static error body (no `script.js` needed for error responders).

- The exact **response body structure**, since all this data must come from the MongoDB queries. For error responses, use the error payload structure specified in the API if available; otherwise, use this fixed error template:  {"httpStatusCode": "${crudToolErrorCode}", "message": "${crudToolErrorMessage}"}

---

## Step 2 — Design the MongoDB backend (design-first, mandatory)

Examine the operations and payloads of the user-given API or request/response file pairs in detail.

Build a **very simple backend storage** in MongoDB to store the different entities in a **denormalized state**. The IDs of the objects are assigned **incrementally** for each entity. The goal is to enable **very simple MongoDB operations** for each of the API endpoints.

You are free to design the data schema however you see fit, provided that the schema can support each of the API endpoints with simple MongoDB operations. The one overriding goal is that the data schema should enable the API operations to keep and update their state using **only very simple MongoDB operations**. Ensure that **data integrity is maintained in all collections whenever some state update happens**.

### Design principles:

- **Incremental integer IDs per entity.** Object IDs are assigned incrementally per entity via a shared `counters` collection (one counter document per entity). This mirrors real create-endpoint behavior and keeps ids predictable. Never rely on random ObjectIds for the business id.

- **A dedicated integer `id` field is the business key. MongoDB's internal `_id` and API object `id` are completely separate things and must NEVER be mixed.** Store the incremental id in a top-level `id` field (not `_id`). MongoDB will automatically add its own internal `_id` field to every document, but you should ignore it completely. Filter, look up, and join on the `id` field; always hide Mongo's internal `_id` from responses by using a `{ _id: 0 }` projection. Always hide Mongo's internal `_id` by using a `{ _id: 0 }` projection when querying things from MongoDB which will be used as response payload elements or as API paylod elements (e.g. for inserting a new document that is made up of elements which are objects retrieved from MongoDB). Never use MongoDB's internal `_id` in schemas, validators, embedded documents, indexes, or scripts as if it were related to the API entity `id`. Never try to map internal `_id` to the `id` of the entity in the API. The `id` field is for your application; the `_id` field is MongoDB's internal implementation detail.

- **Simplicity over normalization.** Prefer operations like `findOne`, `find`, `insertOne`, `findOneAndUpdate`, `deleteOne`, `updateMany` with `$set` / `$pull` / array filters. If an endpoint would need aggregation pipelines or multi-step joins to build its response, that is a signal to **denormalize** (embed the related data) so the read becomes a single simple query. The query result should match as close as possible to the response structure.

- **Denormalize what a response embeds; propagate to keep integrity.** If a response returns entity A with entity B's data embedded (e.g. a cart embeds the full customer and full item details), store B's data embedded inside A. Then whenever B changes, the write side of the affected endpoints **must propagate** that change into every place B is embedded, so the data never goes stale. Example: updating an item must also update that item's copy inside every cart line; deleting an item must pull it from every cart.

- **Data integrity on every state change.** For each write, ask "what other collections hold a copy of, or a reference to, this data?" and update all of them in the same `script.js`. Add supporting indexes for the fields those propagation updates filter on.

With that goal in mind, answer these two critical design questions:

1. **What do the MongoDB collections look like for this API/service?** Ensure you understand in detail the MongoDB collections that will be needed, how they can be created, and detailed examples of what their data looks like.

2. **What are the MongoDB operations each API/service endpoint should perform on the database to maintain state?** For each of the API endpoints in order, outline the full MongoDB command(s) that should be performed when the request is received (ensuring state integrity by performing updates in any collections that are affected) and the full MongoDB statement(s) to retrieve data for the API response.

Then produce these **two written deliverables** before generating anything:

### Deliverable 1 — The collections, in detail

List every MongoDB collection. For each one give:

- Its purpose and a full example document (realistic values, showing nested objects/arrays).
- Its JSON-schema validator (required fields, `bsonType`s, enums, `additionalProperties: true`). Do not be too strict unless required.
  - **CRITICAL:** When using `additionalProperties: false` in a validator, you **MUST** include `_id: { bsonType: "objectId" }` in the properties list. MongoDB automatically adds an internal `_id` field of bsonType "objectId" to every document, and if your validator has `additionalProperties: false` without explicitly allowing `_id`, document insertions will fail with validation errors. Always add `_id: { bsonType: "objectId" }` to the properties of any schema with `additionalProperties: false`.
- Its indexes (unique indexes that enforce business constraints like the 409-conflict cases, plus supporting indexes for propagation filters).
- How it is created — the exact `db.createCollection(...)` / `createIndex(...)` statements.

Always include a `counters` collection: `{ entity: "<entityName>", seq: <int> }`, one document per entity, plus the `getNextSequence(name)` helper that does an atomic `findOneAndUpdate({entity:name}, {$inc:{seq:1}}, {returnDocument:"after"})`. Use a dedicated `entity` field (not `_id`) to maintain complete separation between MongoDB's internal fields and application data.

### Deliverable 2 — The per-endpoint MongoDB operations

Go through **every** API endpoint **in the order they appear in the spec**. For each endpoint, outline:

1. **Sample request** containing parameters to be used in its MongoDB operations (showing path parameters, query parameters, and request body as applicable)

2. **MongoDB operations to be executed for the request** — the full MongoDB statement(s) to perform state updates when the request is received. Ensure state integrity by performing updates in any collections that are affected. Say "None" for read-only endpoints.

3. **MongoDB operations to be executed to retrieve the response data** — the full MongoDB statement(s) with projection to produce the response. Say "None" for `204 No Content`.

4. **Sample response** with the result of the response MongoDB operations (showing the actual data structure that would be returned)

> **Note:** This deliverable is the literal source for each responder's `script.js`. Getting it right here means the file generation is mechanical.

---

## Step 3 — Generate the folder

Use a camelCase service name ending in `Service` (e.g. `ShoppingCartService`). Then build this exact layout.

```
<ServiceName>/
├── data_source/
│   ├── data_source_config.yaml
│   └── init_files/
│       ├── 0-init.js                   # init: drops collections, creates with validators/indexes
│       ├── 1_<entity>_seed_<n>.js      # optional seed scripts, numbered
│       └── ...
└── responders/
    └── <apiFileName>.yaml/             # top suite, named after the spec file
        ├── suite_config.yaml
        └── _<pathGroup>/               # one dir per API path
            ├── suite_config.yaml
            └── _<pathGroup>_-_<METHOD>[_-_<STATUS>]/   # one dir per responder
                ├── matching.yaml
                ├── request_sample.http     # could be JSON or XML
                ├── response_sample.http    # could be JSON or XML
                ├── responder_config.yaml
                └── script.js           # only on responders that touch MongoDB
```

> **Note:** The examples that follow use the Shopping Cart API (with customers, items, and carts) as an instructional reference. Apply the same file structure, naming conventions, and MongoDB patterns to the actual entities and operations from the user's API.

### Naming and sanitization rules

- **Top suite dir** = the spec file name, kept verbatim, e.g. `shoppingCartV6.yaml`.

- **Path-group dir**: take the API path and replace `/` with `_`, drop `{`, and replace `}` with `_`. So `/items` → `_items` and `/items/{itemId}` → `_items_itemId_`. Group all methods and status variants of one path under the same path-group dir.

- **Responder dir**: from the display name `"<path> - <METHOD>"` (success) or `"<path> - <METHOD> - <STATUS>"` (errors), replace `/` and spaces with `_`. So `"/items - GET"` → `_items_-_GET`, `"/items/{itemId} - PUT - 404"` → `_items_itemId_-_PUT_-_404`. Do not produce folder names with consecutive underscores, squish multiple  consecutive underscores into a single one.

- Create **one responder per documented status**: the success responder (with a `script.js`) plus one responder for each documented error code (static error body, no `script.js`).

### File-by-file specification

Every file follows precise conventions. The examples below show the exact patterns to follow.

#### `data_source/data_source_config.yaml`

MongoDB connection info:

```yaml
---
databaseName: <dbNameGivenByTheUser>
```

Use the database name the user provides. If none is given, propose a good name based on the service name and confirm it with the user. Confirm the database name with the user before you upload the service to the server. 

#### `data_source/init_files/0-init.js`

The heart of the data source. **This script should drop all collections at the beginning before creating them. Ensure no errors are thrown by this and other init scripts, especially errors like message='Document failed validation'. **

**CRITICAL VALIDATOR REQUIREMENT FOR _id HANDLING:** 
- **Top-level collection validators**: MongoDB automatically adds an internal `_id` field of bsonType "objectId" to every top-level document in a collection. If your collection's JSON schema validator uses `additionalProperties: false`, you **MUST** explicitly include `_id: { bsonType: "objectId" }` in the properties object, otherwise document insertions will fail with validation errors.
- **Nested object schemas**: MongoDB does NOT add `_id` to nested/embedded objects within documents. For nested schemas (like addressSchema, embedded customer objects, etc.) that use `additionalProperties: false`, do NOT include `_id` in the properties. Including `_id: { bsonType: "objectId" }` in nested schemas will cause a "TypeMismatch" error stating "Nested schema for $jsonSchema property '_id' must be an object".
- **Exception**: If a schema is reused both as a top-level collection validator AND as a nested schema (like customerSchema in the example), include `_id: { bsonType: "objectId" }` to accommodate the top-level case. This definition explicitly specifies MongoDB's internal ObjectId type and will be ignored when the schema is used for nested documents.

**INSTRUCTIONAL EXAMPLE** (Shopping Cart API with customers, items, and carts — adapt these patterns to the user's actual entities and relationships):
```javascript
/**
 * 0-init.js
 * ---------------------------------------------------------------------------
 * Shopping Cart API - MongoDB collection init (denormalized schema, v6).
 * 
 * Drops all existing collections, then creates the collections (counters, customers, items, carts)
 * with JSON-schema validators, seeds the counters, and builds the required indexes.
 *
 * Run against your target database, e.g.:
 *   mongosh "mongodb://localhost:27017/shoppingcart" 0-init.js
 *
 * Note on numeric BSON types:
 * - integer fields (id, seq, quantity) are wrapped in NumberInt() so they satisfy
 *   `bsonType: "int"` validators.
 * - money fields (price, amount, subtotal, total, tax, fee, cost, balance, unitPrice)
 *   are wrapped in NumberDecimal() so they satisfy `bsonType: "decimal"` validators.
 * ---------------------------------------------------------------------------
 */

// --- Drop all existing collections -----------------------------------------
db.counters.drop();
db.customers.drop();
db.items.drop();
db.carts.drop();

// --- Reusable schema fragments ---------------------------------------------
const addressSchema = {
  bsonType: "object",
  required: ["street", "city", "state", "zip", "country"],
  additionalProperties: false,
  properties: {
    // Note: _id is NOT included here because MongoDB only adds _id to top-level
    // collection documents, not to nested/embedded objects like this address.
    street:  { bsonType: "string" },
    city:    { bsonType: "string" },
    state:   { bsonType: "string" },
    zip:     { bsonType: "string" },
    country: { bsonType: "string" }
  }
};

// Full customer document; reused for the embedded customer inside a cart.
// Note: When used as a top-level collection validator, MongoDB will add its own
// internal _id field automatically. When used as an embedded document schema
// (inside carts), MongoDB does NOT add _id to the nested object.
// We use a separate 'id' field as the business key that is exposed in the API.
const customerSchema = {
  bsonType: "object",
  required: ["id", "name", "email", "account"],
  additionalProperties: false,
  properties: {
    // Note: _id is included here because this schema is used BOTH as:
    // 1. A top-level collection validator (customers collection) where MongoDB adds _id
    // 2. A nested schema (embedded customer in carts) where MongoDB does NOT add _id
    // MongoDB's _id field is of bsonType "objectId", explicitly specified here.
    _id: { bsonType: "objectId" },
    id:   { bsonType: "int" },
    name:  { bsonType: "string" },
    email: { bsonType: "string" },
    account: {
      bsonType: "object",
      required: ["type", "number", "address"],
      additionalProperties: true,
      properties: {
        type:    { bsonType: "string", enum: ["VISA", "Mastercard", "Amex", "Discover"] },
        number:  { bsonType: "string" },
        address: addressSchema
      }
    }
  }
};

// Item "info" sub-document; reused for the embedded item info inside a cart.
const infoSchema = {
  bsonType: "object",
  required: ["manufacturer", "date", "address"],
  additionalProperties: true,
  properties: {
    // Note: _id is NOT included here because this is always used as a nested object,
    // never as a top-level collection document. MongoDB only adds _id to top-level documents.
    manufacturer: { bsonType: "string" },
    date:         { bsonType: "string" },
    address:      addressSchema
  }
};

// --- 1. counters -----------------------------------------------------------
// Supports auto-incrementing integer IDs for each entity.
// Note: Uses a dedicated 'entity' field (not _id) to maintain complete separation
// between MongoDB's internal fields and application data.
db.createCollection("counters", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["entity", "seq"],
      additionalProperties: false,
      properties: {
        _id: { bsonType: "objectId" },  // MongoDB's internal ID field (always present, objectId type)
        entity: { bsonType: "string", description: "entity name, e.g. 'customers'" },
        seq: { bsonType: "int", minimum: 0, description: "current sequence value" }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// Unique index on entity field for fast lookups
db.counters.createIndex({ entity: 1 }, { unique: true });

db.counters.insertMany([
  { entity: "customers", seq: NumberInt(0) },
  { entity: "items",     seq: NumberInt(0) },
  { entity: "carts",     seq: NumberInt(0) }
]);

// --- 2. customers ----------------------------------------------------------
db.createCollection("customers", {
  validator: { $jsonSchema: customerSchema },
  validationLevel: "strict",
  validationAction: "error"
});

// Unique index on the business 'id' field for fast lookups.
db.customers.createIndex({ id: 1 }, { unique: true });

// Unique index on email (enforces the 409 Conflict on duplicate emails).
db.customers.createIndex({ email: 1 }, { unique: true });

// --- 3. items --------------------------------------------------------------
// Note: MongoDB will add its own internal _id field automatically, but we use a
// separate 'id' field as the business key that is exposed in the API.
db.createCollection("items", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["id", "name", "description", "price", "info"],
      additionalProperties: true,
      properties: {
        _id: { bsonType: "objectId" },  // MongoDB's internal ID field (always present, objectId type)
        id:         { bsonType: "int" },
        name:        { bsonType: "string" },
        description: { bsonType: "string" },
        price:       { bsonType: "decimal" },
        info:        infoSchema
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// Unique index on the business 'id' field for fast lookups.
db.items.createIndex({ id: 1 }, { unique: true });

// --- 4. carts --------------------------------------------------------------
// Carts embed the full customer object and full item details (denormalized).
// Note: MongoDB will add its own internal _id field automatically, but we use a
// separate 'id' field as the business key that is exposed in the API.
db.createCollection("carts", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["id", "customer", "items"],
      additionalProperties: false,
      properties: {
        _id: { bsonType: "objectId" },  // MongoDB's internal ID field (always present, objectId type)
        id: { bsonType: "int" },
        // Full embedded customer, or null (e.g. guest cart / deleted customer).
        customer: {
          oneOf: [
            { bsonType: "null" },
            customerSchema
          ]
        },
        items: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["itemId", "name", "description", "price", "info", "quantity"],
            additionalProperties: true,
            properties: {
              itemId:      { bsonType: "int" },
              name:        { bsonType: "string" },
              description: { bsonType: "string" },
              price:       { bsonType: "decimal" },
              info:        infoSchema,
              quantity:    { bsonType: "int", minimum: 1 }
            }
          }
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// Unique index on the business 'id' field for fast lookups.
db.carts.createIndex({ id: 1 }, { unique: true });

// Supporting indexes for the denormalized propagation operations:
//   - customer update/delete filters on carts.customer.id (NOT customer._id!)
//   - item update/delete filters on carts.items.itemId
db.carts.createIndex({ "customer.id": 1 });
db.carts.createIndex({ "items.itemId": 1 });
```

The `0-init.js` init script must:

- **Drop all existing collections first** using `.drop()` to ensure a clean state.
- `db.createCollection(name, { validator: { $jsonSchema: ... }, validationLevel: "strict", validationAction: "error" })` for every collection from Deliverable 1.
- Create the `counters` collection and `insertMany` one seed doc per entity at `seq: 0`.
- Create unique indexes for business-uniqueness constraints (these produce the 409 responses) and supporting indexes for propagation filters.
- Wrap all integer literals in `NumberInt(...)`, because the mongo shell stores plain numbers as doubles and the `bsonType: "int"` validators will otherwise reject them. Wrap all monetary literals (`price`, `amount`, `subtotal`, `total`, `tax`, `fee`, `cost`, `balance`, `unitPrice`) in `NumberDecimal(...)` so they satisfy `bsonType: "decimal"` validators. Explain this in a header comment.

#### `data_source/init_files/N_<entity>_seed_<count>.js`

Optional seed scripts, one per seeded collection, numbered **starting from 1** after the `0-init.js` script.

**INSTRUCTIONAL EXAMPLE** (customers seed script for the Shopping Cart API — adapt the entity, fields, and data to match the user's API):
```javascript
/**
 * 1_customers_seed_10.js
 * ---------------------------------------------------------------------------
 * Seeds 10 customers. IDs are assigned via the counters collection, mirroring
 * the POST /customers endpoint. Run 0-init.js first.
 *
 *   mongosh "mongodb://localhost:27017/shoppingcart" 1_customers_seed_10.js
 * ---------------------------------------------------------------------------
 */

// Atomically increment and return the next id for the given entity.
function getNextSequence(name) {
  const ret = db.counters.findOneAndUpdate(
    { entity: name },
    { $inc: { seq: NumberInt(1) } },
    { returnDocument: "after" }
  );
  if (!ret) {
    throw new Error("Counter '" + name + "' not found. Run 0-init.js first.");
  }
  return ret.seq;
}

const customers = [
  { name: "Jane Doe",      email: "jane.doe@example.com",      account: { type: "VISA",       number: "4111111111111111", address: { street: "123 Main St",   city: "Springfield", state: "IL", zip: "62701", country: "US" } } },
  { name: "John Smith",    email: "john.smith@example.com",    account: { type: "Mastercard", number: "5500005555555559", address: { street: "789 Oak Ave",   city: "Chicago",     state: "IL", zip: "60601", country: "US" } } },
  { name: "Alice Johnson", email: "alice.johnson@example.com", account: { type: "Amex",       number: "378282246310005",  address: { street: "55 Pine Rd",    city: "Denver",      state: "CO", zip: "80202", country: "US" } } },
  { name: "Bob Williams",  email: "bob.williams@example.com",  account: { type: "Discover",   number: "6011000990139424", address: { street: "200 Elm St",    city: "Portland",    state: "OR", zip: "97201", country: "US" } } },
  { name: "Carol Brown",   email: "carol.brown@example.com",   account: { type: "VISA",       number: "4012888888881881", address: { street: "12 Maple Dr",   city: "Austin",      state: "TX", zip: "73301", country: "US" } } },
  { name: "David Jones",   email: "david.jones@example.com",   account: { type: "Mastercard", number: "5105105105105100", address: { street: "340 Birch Ln",  city: "Seattle",     state: "WA", zip: "98101", country: "US" } } },
  { name: "Emma Garcia",   email: "emma.garcia@example.com",   account: { type: "Amex",       number: "371449635398431",  address: { street: "78 Cedar Blvd", city: "Miami",       state: "FL", zip: "33101", country: "US" } } },
  { name: "Frank Miller",  email: "frank.miller@example.com",  account: { type: "Discover",   number: "6011111111111117", address: { street: "90 Walnut Way", city: "Boston",      state: "MA", zip: "02108", country: "US" } } },
  { name: "Grace Davis",   email: "grace.davis@example.com",   account: { type: "VISA",       number: "4222222222222",    address: { street: "5 Spruce Ct",   city: "New York",    state: "NY", zip: "10001", country: "US" } } },
  { name: "Henry Wilson",  email: "henry.wilson@example.com",  account: { type: "Mastercard", number: "5555555555554444", address: { street: "410 Ash St",    city: "San Jose",    state: "CA", zip: "95101", country: "US" } } }
];

customers.forEach(function (c) {
  db.customers.insertOne({
    id: getNextSequence("customers"),
    name: c.name,
    email: c.email,
    account: c.account
  });
});

```

Each seed script defines `getNextSequence()` and inserts docs exactly the way the corresponding `POST` endpoint would (assign `id` from the counter). Seed denormalized collections **last** and build their embedded data by looking up the already-seeded parents, so the seeds obey the same integrity rules as the live service.

#### `responders/<apiFile>.yaml/suite_config.yaml`

Top suite configuration:

```yaml
---
name: <apiFile>.yaml
children:
- /items
- /items/new
- "/items/{itemId}"
```

`children` lists every API path (quote entries containing `{}`). When two or more API paths have an equal number of segments and equal segment values except for parameterized segments (e.g. {itemId}), **the paths with parameterized segments should come after the paths with fixed value segments**. E.g.: These paths are all equal except parameterized segments. **The more fixed ones come first and the more parameterized ones come last**.
    /carts/pending/items/deleted
    /carts/pending/items/{itemId}
    /carts/{cartId}/items/deleted
    /carts/{cartId}/items/{temId}

**Instructional example** for a Shopping Cart API with two path groups (adapt to list all actual paths from the user's API):

```yaml
---
name: shoppingCartV6.yaml
children:
- /items
- /items/new
- "/items/{itemId}"
```

#### `responders/.../_<pathGroup>/suite_config.yaml`

Path suite configuration:

```yaml
---
name: /items
children:
- /items - GET
- /items - POST
- /items - POST - 400
```

`children` lists the display names of every responder under this path. Include entries for all documented status codes, with error statuses following the format `"<path> - <METHOD> - <STATUS>"`.

#### `matching.yaml`

How an incoming request is routed to this responder. The structure is the same for both success and error responders.

```yaml
---
bodyFormat: JSON
methods:
- GET
path: /items
httpStatusCode: 200
```

For parameterized paths, replace each `{param}` segment with `*`, e.g. `/items/{itemId}` → `path: /items/*` and `/carts/{cartId}/items/{itemId}` → `path: /carts/*/items/*`.

The `httpStatusCode` field specifies the HTTP status code for the response, matching what the API specifies (e.g., 200, 201, 204, 400, 404, 409).

**Instructional examples** (replace with the actual path, method, and status code from the user's API):

Success responder for `GET /items` returning 200:

```yaml
---
bodyFormat: JSON
methods:
- GET
path: /items
httpStatusCode: 200
```

Error responder for `PUT /customers/{customerId}` returning 409 Conflict:

```yaml
---
bodyFormat: JSON
methods:
- PUT
path: /customers/*
httpStatusCode: 409
```

#### `request_sample.http`

A sample request showing realistic data for this operation. These examples are for a JSON definition, the actual user service may use XML. First line `"<METHOD> <path> HTTP/1.1"`, a blank line, then the JSON body for `POST`/`PUT` (use a realistic example from the schema), or nothing for `GET`/`DELETE`. The <path> in the first line should preserve path and request parameters (named as in the given service definition, or appropriately named if no service definition was given) and not substitute these with concrete values: e.g DELETE /carts/{cartId}/items/{itemId} HTTP/1.1, PUT /customers/{customerId} HTTP/1.1

**The content of this file must exactly match the sample request that appears commented out at the top of the corresponding `script.js` file.**
For any money-like request fields (`price`, `amount`, `subtotal`, `total`, `tax`, `fee`, `cost`, `balance`, `unitPrice`), keep the API example shape as defined by the API, but ensure the corresponding `script.js` converts and persists those values with `NumberDecimal(...)`.

**Instructional examples** (adapt the path and body structure to match the user's API):

GET request:

```
GET /items/{itemId} HTTP/1.1

```

POST request:

```
POST /items HTTP/1.1

{"name":"Wireless Headphones","description":"Over-ear noise-cancelling wireless headphones.","price":79.99,"info":{"manufacturer":"Acme Corp","date":"2025-03-15","address":{"street":"123 Main St","city":"Springfield","state":"IL","zip":"62701","country":"US"}}}
```

#### `response_sample.http`

A concrete sample response with realistic data for this operation. These examples are for a JSON definition, the actual user service may use XML. First line `"HTTP/1.1 <status>"`, a blank line, then the actual response body showing what the operation would return. 

**The content of this file must exactly match the sample response that appears commented out at the bottom of the corresponding `script.js` file.**
For money-like response fields (`price`, `amount`, `subtotal`, `total`, `tax`, `fee`, `cost`, `balance`, `unitPrice`), align with the API schema while ensuring the underlying MongoDB value is stored as Decimal128 (`bsonType: "decimal"`).

**Instructional examples** (Shopping Cart API — adapt the structure and field names to match the user's actual API response schemas):

Success list example (`GET /items` — showing actual sample data):

```
HTTP/1.1 200

[
  {
    "id": 1,
    "name": "Wireless Headphones",
    "description": "Over-ear noise-cancelling wireless headphones.",
    "price": 79.99,
    "info": { "manufacturer": "Acme Corp", "date": "2025-03-15", "address": { "street": "123 Main St", "city": "Springfield", "state": "IL", "zip": "62701", "country": "US" } }
  }
]
```

**For error responders:**
- The response is fixed and the response file should be named **response.http**
- If the API specification defines the error response payload, response.http payload should match the API exactly as defined
- If the API does not specify the error response payload, response.http payload should be a fixed template exactly as below:

{"httpStatusCode": "${crudToolErrorCode}", "message": "${crudToolErrorMessage}"}

Error responder examples:

Using API-specified error schema:


reponse.http

```
HTTP/1.1 404

{"code":"NOT_FOUND","message":"The requested resource does not exist."}
```

Using default template when API doesn't specify error payload (e.g., for `PUT /customers/{customerId}` returning 409 Conflict):

response.http

```
HTTP/1.1 409

{"httpStatusCode": "${crudToolErrorCode}", "message": "${crudToolErrorCode}"}
```

#### `responder_config.yaml`

```yaml
---
name: <responder display name>
serviceDefinitionType: SWAGGER
serviceDefinitionLocation: file:///<absolute path to the spec file>
```


**Instructional example** for `GET /items` in the Shopping Cart API (replace service name, API file, paths, and file location with actual values from the user's context):

```yaml
---
name: /items - GET
serviceDefinitionType: SWAGGER
serviceDefinitionLocation: file:///C:\Users\tester\Desktop\playground\shoppingCartV6.yaml
```

#### `script.js`

Present on every success responder that reads or writes state (omit it on static error responders). 

The file must have **three parts in order**: 
1. A multi-line comment at the top with the sample request matching `request_sample.http`. Always include.
2. The executable JavaScript code performing the MongoDB operations
3. A multi-line comment at the bottom with the sample response matching `response_sample.http`. Always include.

Follow this exact three-part shape, taken verbatim from Deliverable 2.
---

### Script.js Requirements

#### Built-in request object

The scripts have access to a built-in object named `request`, which provides access to values from the HTTP request:

- `request.body` — the request payload as a JavaScript object. If the request's MIME type is XML, the application layer will have already converted it using the jackson-dataformat-xml library. **IMPORTANT: `request.body` is already a deserialized JavaScript object — never wrap it in `JSON.parse()`.**
- `request.pathParams` — an object containing path parameter values (e.g., `request.pathParams.itemId`)
- `request.queryParams` — an object containing query parameter values

#### Type conversion

Convert integer, decimal, and monetary request fields to their proper types using `NumberInt()` or `NumberLong()` or `NumberDecimal()` to avoid type mismatch with the collection validators. For example:

```javascript
var itemId = NumberInt(request.pathParams.itemId);
var price = NumberDecimal(String(request.body.price));
```

#### Compatibility

- Use **only MongoDB script syntax compatible with ES5**
- Do **not** use any deprecated methods, e.g. findAndModify.
- Do **not** use transactions or any bulk operations
- Use `==` and `!=` instead of `===` and `!==` unless you know the precise data type
- **IMPORTANT: Never call `.map()`, `.filter()`, or `.forEach()` on `.toArray()` results — use a `for` loop instead.** `.toArray()` returns a Java array type which does not have any of those JavaScript methods.

#### Return value

The **last line** of the script implicitly returns the data that the operation needs to compose the response. This should be the result of the MongoDB retrieval query (with `{_id: 0}` projection to hide the internal `_id` field). When the return value is not directly the result of a query, assign the value to a variable and implicitly return the variable, e.g.:

```javascript
var items = db.items.find(
  {},
  { _id: 0, id: 1, name: 1, description: 1, inStock: 1, image: 1, region: 1, lastAccessedDate: 1, categoryId: 1 }
).sort({ id: 1 }).toArray();

var result = {
  status: 1,
  message: "success",
  data: {
    totalElements: items.length,
    totalPages: 1,
    size: items.length,
    number: 0,
    numberOfElements: items.length,
    sort: "",
    content: items
  }
};

result;   # return value
```

** The script must never end with a var assignment statement **

#### Comments

- Add the **sample request** as a comment at the beginning of the script file
- Add the **sample response** as a comment at the end of the script file (after the script code)

#### Error handling

Success responder scripts (`script.js`) must validate the request and throw errors for API-defined error conditions. When an error condition is detected, throw an error in the format:

```javascript
throw "<httpStatusCode>_<errorMessage>";
```

For example:

```javascript
throw "404_Resource not found";
throw "409_A resource with the given unique value already exists.";
throw "400_Invalid request payload";
```

Example common error scenarios to check in success responder scripts. These are only examples, follow the actual error conditions as defined in the service API:

- **GET operations** (single resource): Throw `404_Resource not found` if the requested resource does not exist
- **PUT operations**:
  - Throw `404_Resource not found` if the resource to be updated does not exist
  - Throw `409_A resource with the given unique value already exists.` if the update would violate a uniqueness constraint
  - Throw `400_Invalid request payload` for invalid/malformed request data (e.g.: payload is missing required field)
- **DELETE operations**: Throw `404_Resource not found` if the resource to be deleted does not exist
- **POST operations**: Throw `409_A resource with the given unique value already exists.` if the creation would violate a uniqueness constraint

Always check the API definition to determine which error conditions are documented for each operation, and implement the corresponding validation checks in the success responder's `script.js`. The error message should match the description in the API definition.

---
### Instructional Examples (Shopping Cart API)

**INSTRUCTIONAL EXAMPLES** (Shopping Cart API operations — these demonstrate the patterns for GET, POST, PUT, and DELETE operations with state management and denormalized data propagation. Adapt the entities, collections, fields, and MongoDB operations to match the user's actual API):

#### Example 1: GET /items (read-only list operation)
```javascript
/*
Sample request:
GET /items HTTP/1.1

*/

// Request operations (state updates)
// None

// Response retrieval operations
var result = db.items.find(
  {},
  { _id: 0, id: 1, name: 1, description: 1, price: 1, info: 1 }
).sort({ id: 1 }).toArray();

result;   # return value

/*
Sample response (200):
HTTP/1.1 200

[
  {
    "id": 1,
    "name": "Wireless Headphones",
    "description": "Over-ear noise-cancelling wireless headphones.",
    "price": 79.99,
    "info": { "manufacturer": "Acme Corp", "date": "2025-03-15", "address": { "street": "123 Main St", "city": "Springfield", "state": "IL", "zip": "62701", "country": "US" } }
  }
]
*/
```

#### Example 1a: GET /items/{itemId} (read-only single resource with error handling)
```javascript
/*
Sample request:
GET /items/1 HTTP/1.1

*/

// Request operations (state updates)
// None

// Response retrieval operations
var itemId = NumberInt(request.pathParams.itemId);
var item = db.items.findOne(
  { id: itemId },
  { _id: 0, id: 1, name: 1, description: 1, price: 1, info: 1 }
);

// Error handling: throw 404 if item not found
if (!item) {
  throw "404_Resource not found";
}

item; # return value

/*
Sample response (200):
HTTP/1.1 200

{
  "id": 1,
  "name": "Wireless Headphones",
  "description": "Over-ear noise-cancelling wireless headphones.",
  "price": 79.99,
  "info": { "manufacturer": "Acme Corp", "date": "2025-03-15", "address": { "street": "123 Main St", "city": "Springfield", "state": "IL", "zip": "62701", "country": "US" } }
}
*/
```

#### Example 2: POST /items (create operation with counter increment)

```javascript
/*
Sample request:
POST /items HTTP/1.1

{"name":"Portable Speaker","description":"Bluetooth speaker with deep bass.","price":49.50,"info":{"manufacturer":"Acme Corp","date":"2025-05-01","address":{"street":"10 Audio Ln","city":"Nashville","state":"TN","zip":"37201","country":"US"}}}
*/

// Request operations (state updates)
var counterDoc = db.counters.findOneAndUpdate(
  { entity: "items" },
  { $inc: { seq: NumberInt(1) } },
  { upsert: true, returnNewDocument: true }
);

var newItemId = NumberInt(counterDoc.seq);
var itemPrice = NumberDecimal(String(request.body.price));
var itemToInsert = {
  id: newItemId,
  name: request.body.name,
  description: request.body.description,
  price: itemPrice,
  info: request.body.info
};

db.items.insertOne(itemToInsert);

// Response retrieval operations
var item = db.items.findOne(
  { id: newItemId },
  { _id: 0, id: 1, name: 1, description: 1, price: 1, info: 1 }
);

item; # return value

/*
Sample response (201):
HTTP/1.1 201

{
  "id": 3,
  "name": "Portable Speaker",
  "description": "Bluetooth speaker with deep bass.",
  "price": 49.5,
  "info": { "manufacturer": "Acme Corp", "date": "2025-05-01", "address": { "street": "10 Audio Ln", "city": "Nashville", "state": "TN", "zip": "37201", "country": "US" } }
}
*/
```

#### Example 3: PUT /items/{itemId} (update operation with denormalized propagation and error handling)

```javascript
/*
Sample request:
PUT /items/1 HTTP/1.1

{"name":"Wireless Headphones Pro","description":"Over-ear ANC headphones with multipoint Bluetooth.","price":99.99,"info":{"manufacturer":"Acme Corp","date":"2025-06-01","address":{"street":"500 Factory Ave","city":"Chicago","state":"IL","zip":"60601","country":"US"}}}
*/

// Request operations (state updates)
var itemId = NumberInt(request.pathParams.itemId);
var updatedPrice = NumberDecimal(String(request.body.price));

// Error handling: check if item exists before updating
var existingItem = db.items.findOne({ id: itemId });
if (!existingItem) {
  throw "404_Resource not found";
}

var updateResult = db.items.findOneAndUpdate(
  { id: itemId },
  {
    $set: {
      name: request.body.name,
      description: request.body.description,
      price: updatedPrice,
      info: request.body.info
    }
  },
  { returnNewDocument: true }
);

// Propagate the update to all carts that contain this item (denormalized integrity)
if (updateResult && updateResult.value) {
  db.carts.updateMany(
    { "items.itemId": itemId },
    {
      $set: {
        "items.$[line].name": request.body.name,
        "items.$[line].description": request.body.description,
        "items.$[line].price": updatedPrice,
        "items.$[line].info": request.body.info
      }
    },
    {
      arrayFilters: [{ "line.itemId": itemId }]
    }
  );
}

// Response retrieval operations
var item = db.items.findOne(
  { id: itemId },
  { _id: 0, id: 1, name: 1, description: 1, price: 1, info: 1 }
);

item; # return value

/*
Sample response (200):
HTTP/1.1 200

{
  "id": 1,
  "name": "Wireless Headphones Pro",
  "description": "Over-ear ANC headphones with multipoint Bluetooth.",
  "price": 99.99,
  "info": { "manufacturer": "Acme Corp", "date": "2025-06-01", "address": { "street": "500 Factory Ave", "city": "Chicago", "state": "IL", "zip": "60601", "country": "US" } }
}
*/
```

#### Example 3a: PUT /customers/{customerId} (update operation with comprehensive error handling)

```javascript
/*
Sample request:
PUT /customers/1 HTTP/1.1

{"name":"Jane Doe Updated","email":"jane.updated@example.com","account":{"type":"VISA","number":"4111111111111111","address":{"street":"456 Oak St","city":"Springfield","state":"IL","zip":"62702","country":"US"}}}
*/

// Request operations (state updates)
var customerId = NumberInt(request.pathParams.customerId);

// Error handling: validate required fields in request payload (400)
if (!request.body.name || !request.body.email || !request.body.account) {
  throw "400_Invalid request payload";
}

// Additional validation for nested required fields in account
if (!request.body.account.type || !request.body.account.number || !request.body.account.address) {
  throw "400_Invalid request payload";
}

// Error handling: check if customer exists (404)
var existingCustomer = db.customers.findOne({ id: customerId });
if (!existingCustomer) {
  throw "404_Resource not found";
}

// Error handling: check for duplicate email (409 conflict)
// Only check if the email is changing to a different value
if (request.body.email != existingCustomer.email) {
  var duplicateEmail = db.customers.findOne({ email: request.body.email });
  if (duplicateEmail) {
    throw "409_A resource with the given unique value already exists.";
  }
}

var updateResult = db.customers.findOneAndUpdate(
  { id: customerId },
  {
    $set: {
      name: request.body.name,
      email: request.body.email,
      account: request.body.account
    }
  },
  { returnNewDocument: true }
);

// Propagate the update to all carts that contain this customer (denormalized integrity)
if (updateResult && updateResult.value) {
  db.carts.updateMany(
    { "customer.id": customerId },
    {
      $set: {
        customer: {
          id: customerId,
          name: request.body.name,
          email: request.body.email,
          account: request.body.account
        }
      }
    }
  );
}

// Response retrieval operations
var customer = db.customers.findOne(
  { id: customerId },
  { _id: 0, id: 1, name: 1, email: 1, account: 1 }
);

customer; # return value

/*
Sample response (200):
HTTP/1.1 200

{
  "id": 1,
  "name": "Jane Doe Updated",
  "email": "jane.updated@example.com",
  "account": { "type": "VISA", "number": "4111111111111111", "address": { "street": "456 Oak St", "city": "Springfield", "state": "IL", "zip": "62702", "country": "US" } }
}
*/
```

#### Example 4: DELETE /items/{itemId} (delete operation with denormalized propagation and error handling)

```javascript
/*
Sample request:
DELETE /items/2 HTTP/1.1

*/

// Request operations (state updates)
var itemId = NumberInt(request.pathParams.itemId);

// Error handling: check if item exists before deleting
var existingItem = db.items.findOne({ id: itemId });
if (!existingItem) {
  throw "404_Resource not found";
}

var deleteResult = db.items.deleteOne({ id: itemId });

// Remove this item from all carts that contain it (denormalized integrity)
if (deleteResult.deletedCount == 1) {
  db.carts.updateMany(
    { "items.itemId": itemId },
    { $pull: { items: { itemId: itemId } } }
  );
}

// Response retrieval operations
// None for 204 No Content

/*
Sample response (204):
HTTP/1.1 204

*/
```

---

### Key script.js patterns from the examples

- **Three-part structure**: The file has (1) top comment with the sample request (matching `request_sample.http`), (2) the MongoDB operations code, (3) bottom comment with the sample response (matching `response_sample.http`).

- **Request object access**: Access request data via the built-in `request` object: `request.pathParams`, `request.queryParams`, and `request.body`.

- **Money values must use Decimal128.** For any monetary field (e.g. `price`, `amount`, `subtotal`, `total`, `tax`, `fee`, `cost`, `balance`, `unitPrice`), use `bsonType: "decimal"` in validators and use `NumberDecimal(...)` in init/seed/scripts. Do not store money as `double` or `int`.

- **Type conversion**: Convert integer path/query params with `NumberInt(request.pathParams.<name>)` or `NumberLong(...)` before using them as filters to match `bsonType: "int"` requirements. Convert every monetary field (for example `price`, `amount`, `subtotal`, `total`, `tax`, `fee`, `cost`, `balance`, `unitPrice`) with `NumberDecimal(String(...))` to match `bsonType: "decimal"` requirements.

- **ID assignment**: Assign new ids by incrementing the entity's counter:
  ```javascript
  var counterDoc = db.counters.findOneAndUpdate(
    {entity:"<entity>"},
    {$inc:{seq:NumberInt(1)}},
    {upsert:true, returnNewDocument:true}
  );
  var newId = NumberInt(counterDoc.seq);
  ```

- **Return value**: The **last expression** in the file is the retrieval query whose result is returned in the response. Project with `{ _id: 0, ... }` so `_id` never leaks. For `204` responses, perform the writes and add a comment `// None` for the retrieval section.

- **Data propagation**: For denormalized data, do the primary write first, then guard the propagation writes on success (e.g. only propagate to carts if the item update/delete actually matched), so integrity is preserved across every collection that embeds the changed data.

- **Comparison operators**: Use `==` and `!=` for comparisons (not `===` and `!==`) unless you know the precise data type.

- **Compatibility**: Use only ES5-compatible JavaScript and MongoDB 3.6-compatible commands. No deprecated methods, no transactions, no bulk operations.

---

## Pattern Reference (Shopping Cart Example)

**The examples above are instructional patterns from a Shopping Cart API**, featuring customers, items, and carts. They demonstrate the canonical patterns you should follow for **any** stateful virtual service:

### What the Shopping Cart example teaches

#### MongoDB schema patterns

- An auto-increment `counters` collection providing sequential integer IDs (one counter per entity type)
- Entity collections keyed by integer `id` field (not MongoDB's `_id`)
- Denormalized relationships (carts embed full customer and item details) to keep queries simple
- Supporting indexes for propagation operations (e.g., `carts.items.itemId` for item updates)

#### Folder structure patterns

- `data_source/` with connection config and numbered `init_files/*.js` scripts
- `responders/<apiFile>.yaml/` with nested path-group directories
- One responder directory per operation per documented status code

#### Script.js operation patterns

- Each `script.js` has three parts: (1) sample request comment (matching `request_sample.http`), (2) MongoDB operations code, (3) sample response comment (matching `response_sample.http`)
- `POST` operations: increment counter, insert document, return the created resource
- `GET` operations: simple `find` or `findOne` with `{_id:0}` projection
- `PUT` operations: update the primary entity **and** propagate changes to all denormalized copies
- `DELETE` operations: remove the primary entity **and** clean up references/embedded copies
- Always use `NumberInt()` for integer values to satisfy `bsonType: "int"` validators, and `NumberDecimal()` for monetary values (`price`, `amount`, `subtotal`, `total`, `tax`, `fee`, `cost`, `balance`, `unitPrice`) to satisfy `bsonType: "decimal"` validators

### Adapt these patterns to the user's API/service

Replace `customers`, `items`, `carts` with the actual entities from the user's API/service. Replace the Shopping Cart operations (`POST /items`, `GET /items/{itemId}`, etc.) with the actual operations from the user's specification. Follow the same MongoDB conventions (integer IDs, denormalization for simplicity, propagation for integrity) and file structure patterns (naming, `script.js` three-part shape, response samples.).

### Special instructions if the service is SOAP
- Instead of HTTP method and resource, create responders for each SOAP operation.
- The `matching.yaml` file for each operation should specify that the `SOAPAction` header is expected to be the operation name and the SOAP body is expected to contain the request's root element. In the following example, the operation name is `getItemById` and the request's root element is named `item`.

```yaml
---
bodyFormat: XML
headers:
  SOAPAction: getItemById
xpaths:
- "local-name(/*/*[local-name(.)=\"Body\"]/*)=\"item\""
```

- Each `script.js` should handle the SOAP operation accordingly. Use the `request.body` object to access the values in the SOAP body; e.g. `request.body.item` refers to the element `/Envelope/Body/item`.
- Ensure that the request and response samples match the SOAP operations.

---

## Final checklist

Before delivering the service representation folder, verify:

- [ ] Design analysis (Deliverable 1 + Deliverable 2) written and shown to the user before file generation.

- [ ] `0-init.js` script drops all collections first, then creates them with validators and indexes.

- [ ] Seed scripts are numbered starting from 1 (e.g., `1_customers_seed_10.js`).

- [ ] One responder per documented status per operation; success responders have `script.js`, error responders have a static body and no `script.js`.

- [ ] `id` convention consistent across validators, seeds, and every `script.js`; `_id` hidden in responses.

- [ ] Every write propagates to all collections that embed/reference the changed data; supporting indexes exist for those filters.

- [ ] `NumberInt(...)` used for all integer literals in the init and seed scripts, and for converting integer request parameters in `script.js`; `NumberDecimal(...)` used for all monetary values (`price`, `amount`, `subtotal`, `total`, `tax`, `fee`, `cost`, `balance`, `unitPrice`) in validators and script writes/updates.

- [ ] `script.js` files use ES5 compatible syntax, use `==`/`!=` comparisons, and have the three-part structure (sample request comment, code, sample response comment).
**Ensure the script does not end in a var assignment statement.**

- [ ] `suite_config.yaml` `children` lists complete at both suite levels. For top level suite the list order for same paths should put paths with fixed segments first and paths with parameterized segments later; `matching.yaml` paths use `*` for path parameters; `request_sample.http` and `response_sample.http` contain actual sample data matching what appears in the comments of the corresponding `script.js` file.

# Contract Governance Model

The keywords **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are normative.

## 1. Ownership and truth sources

| Artifact | Owner | Meaning |
|---|---|---|
| `contracts/<service>/api.yaml` | Provider service | Canonical HTTP operations and schemas |
| `contracts/<service>/events/` | Provider service | Canonical event schemas |
| `contracts/_registry/<service>.yaml` | Backend Consumer service | Dependencies consumed by that service |
| `contracts/_consumers/<consumer>.yaml` | Frontend Consumer | Expected operations, fields, evidence, and status |
| `contracts/SERVICE-MAP.md` | Generated view | Provider, Consumer, and dependency topology |

A registry MUST NOT duplicate Provider operation inventories such as
`feign_operations`, `http_operations`, or `mq_operations`. The topology can be
reconstructed from Provider contracts and Consumer declarations.

## 2. Caller boundaries

OpenAPI operation tags classify callers:

- `前端API`: frontend-accessible operation.
- `外部API`: explicitly exposed external operation.
- `Feign`: backend Feign operation; its path MUST use the configured internal prefix.
- `内部API`: language-neutral backend HTTP operation; its path MUST use the configured
  internal prefix and Consumers MUST declare it in `consumes.http`.

Frontend Consumers MUST NOT resolve `Feign`, `内部API`, or internal-path operations.
One operation SHOULD NOT combine frontend and backend-only tags.

## 3. Consumer state machine

```text
PENDING  -> RESOLVED
PENDING  -> MISMATCH
MISMATCH -> RESOLVED
RESOLVED -> MISMATCH  (provider drift or incompatible change)
```

- `PENDING`: the expectation exists but Provider semantics are not confirmed.
- `RESOLVED`: operation identity, caller tag, required fields, permissions, error
  semantics, and business meaning are confirmed.
- `MISMATCH`: Provider behavior does not satisfy the expectation; the difference and
  resolution decision MUST be recorded.

Tools MUST NOT promote `PENDING` automatically. Structural validation is necessary but
not sufficient for business confirmation.

## 4. Schema compatibility

For a `RESOLVED` Consumer, every `required_fields` entry MUST resolve recursively through
the successful response schema, including `$ref`, arrays, and `allOf` composition.
Nested fields use dotted paths such as `data.records.id`; array traversal is automatic,
so paths MUST NOT include `[]` markers.

Breaking changes include operation removal, required request additions, response field
removal, incompatible type or format changes, enum narrowing, status-code removal,
operationId changes, and caller-tag boundary changes. A breaking change MUST identify
affected Consumers and track acknowledgment.

## 5. Authentication and isolation

`internal_service_auth_mode` controls internal operations:

- `provider-defined`: the Provider decides whether OpenAPI security applies.
- `network-only`: internal operations MUST NOT declare or inherit OpenAPI security;
  secured top-level documents MUST override internal operations with `security: []`.

This policy does not remove authentication requirements from frontend or external APIs.
Deployment plans involving internal operations SHOULD include gateway and network
isolation tasks.

## 6. Validation levels

- Structural validation detects malformed ownership, paths, tags, statuses, and links.
- Semantic audit detects required-field gaps, drift, stale PENDING items, event
  incompatibility, and unacknowledged breaking changes.
- Runtime OpenAPI comparison checks implementation drift from the declared Provider.
- Business confirmation remains a human ownership decision.

An exit code of zero from structural validation MUST NOT be described as delivery
completion when semantic warnings or unconfirmed Consumer states remain.

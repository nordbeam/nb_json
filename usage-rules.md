# NbJson Usage Rules

`nb_json` is the Phoenix JSON API contract layer for the nb ecosystem. It
owns endpoint declarations, request validation, response/error envelopes,
OpenAPI metadata, and optional TypeScript client generation. Serialization,
typed routes, pagination, and authentication remain composable integrations.

## Installation

Add `{:nb_json, "~> 0.1"}` and use the installer for optional integrations:

```bash
mix igniter.install nb_json
mix igniter.install nb_json --with-typescript
```

OpenApiSpex is enabled by default by the installer. Use its negation only when
the application intentionally wants plain JSON spec generation without
OpenApiSpex plugs or serving.

## Contracts and runtime behavior

- In controllers, `use NbJson.Controller` and declare `json_endpoint`
  metadata beside the matching action. Keep path placeholders aligned with
  `location: :path` fields and declare a success response for every endpoint.
- Validate through the documented plug order, then render with
  `render_json/3`, `render_error/3`, or the validation helpers. Preserve the
  declared status codes, envelope keys, serializer refs, and meta/links shape.
- Configure `NbJson.Plug.Secure` and application-owned auth/authorization
  adapters explicitly. Contract metadata is not authentication, and secrets or
  tenant policy must remain in the host application.
- Generate OpenAPI and TypeScript clients from the declarations; do not hand
  edit generated clients/specs. Confirm serializer imports and auth options
  after regeneration.

## Verification

For contract failures, inspect duplicate endpoint/field/status declarations,
invalid locations/types, and action verification. For runtime failures, check
plug order and controller metadata. Run `mix compile`, `mix test`, and the
available `mix nb_json.openapi` or client-generation tasks for the selected
integrations.

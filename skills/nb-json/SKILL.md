---
name: nb-json
description: "Build, configure, upgrade, diagnose, and verify nb_json typed Phoenix JSON APIs, validation, auth, OpenAPI, TypeScript clients, and JSON:API responses."
---

# NbJson

Use this skill for `nb_json` controller endpoint contracts, request validation, response/error envelopes, auth/authorization adapters, OpenAPI generation, TypeScript clients, React Query output, JSON:API profiles, and Flop-compatible API params.

## Discover the target release

- Inspect the target app's `mix.exs`, `mix.lock`, `config/config.exs`, controllers/router pipelines, serializers, `assets/package.json`/lockfile, generated API clients, and OpenAPI files. Read the selected README, installer/client/OpenAPI tasks, controller/type/validation source, and companion package versions before changing a contract.
- `nb_serializer`, `nb_ts`, `nb_routes`, `nb_flop`, Phoenix/Plug/Ecto, and OpenApiSpex are composable integrations. Preserve their optional boundaries and add only the packages/features the target task and user require.

## Install

- Prefer `mix igniter.install nb_json` with only target-supported options such as `--with-typescript`, `--with-open-api-spex`/its negation, `--camelize-props`, and `--yes`. The current installer defaults OpenApiSpex on; inspect the selected task before relying on that default.
- Review generated `:nb_json` config and API spec module. If TypeScript is requested, verify the composed `nb_ts` installer and output path. If OpenApiSpex is disabled, do not leave plugs/spec routes that require it.

## Implement and configure

- In controllers use the target `NbJson.Controller` DSL: `json_endpoint` with method/path, params, response/error declarations, and optional auth/authorization metadata. Enable action verification only when every declared endpoint has a matching controller action.
- Validate request params through the documented validation plug/function and render through `render_json`/`render_error`/validation helpers. Keep response envelopes, status codes, serializer refs, and meta/links consistent with the declared contract.
- For auth, implement the app's `NbJson.Auth` and `NbJson.Authorization` adapters and configure `NbJson.Plug.Secure` before validation. Never treat contract metadata as authentication; the app owns credentials, tenants, roles, and policy.
- Generate OpenAPI with the current task and expose it through OpenApiSpex only when installed/configured. Generate TypeScript clients with the target options (serializer imports, auth options, React Query, etc.) and inspect generated output before importing it.
- Use `profile: :json_api`, Flop params, and serializer-aware output only when the installed source supports them; verify JSON:API `data`/relationships rules and query encodings from generated artifacts.

## Upgrade or migrate

- Compare locked package versions, endpoint metadata, generated OpenAPI/client files, serializer/type imports, auth adapters, and OpenApiSpex/Phoenix versions before upgrading. Contract changes are API changes: review status codes, field names, envelopes, auth schemes, and path parameters.
- Regenerate clients/specs from declarations instead of hand-editing output. Migrate one surface at a time (runtime response, validation, OpenAPI, client) and keep backward-compatible routes/fields when consumers require them.
- Re-test auth failures and validation error envelopes after changing adapters or OpenApiSpex; do not silently weaken security to make a generated client compile.

## Diagnose and verify

- For compile-time DSL errors, inspect duplicate endpoint/field/status declarations, path placeholders vs path params, missing success responses, invalid locations/types, and action-verification settings. For runtime validation errors, check plug order and controller/action metadata.
- For spec/client mismatches, regenerate with verbose output, compare serializer metadata/imports, confirm auth scheme names, and inspect path/query/body encoding. For unauthorized requests, test missing/invalid/expired credentials and policy denial separately.
- Verify with `mix deps.get`, `mix compile`, `mix test`, `mix nb_json.openapi ...` and client generation as exposed, strict TypeScript compilation, OpenApiSpex response assertions, and tagged production-smoke tests when the target package provides them.
- If “latest” is requested, consult current package source/HexDocs, official OpenAPI/OpenApiSpex/Phoenix docs, and TypeScript/React Query package metadata; state the date checked and reconcile with lockfiles.

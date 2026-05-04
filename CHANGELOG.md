# Changelog

## 0.1.0

Initial development release.

- Added `nb_serializer` metadata expansion for OpenAPI component schemas.
- Added optional `open_api_spex` bridge via `NbJson.OpenApi.to_open_api_spex/2`
  and `use NbJson.OpenApiSpex`.
- Added endpoint operation metadata for tags, security, custom operation IDs,
  deprecation, servers, and request body descriptions.
- Added `NbJson.Plug.Validate` for contract-backed request validation in
  Phoenix/Plug pipelines.
- Added `NbJson.TestAssertions` for validating rendered responses against the
  generated OpenApiSpex spec.
- Added `flop_params/1` and `flop_meta/0` helpers for Flop-compatible list
  endpoint contracts.
- Added a standalone TypeScript fetch client generator in `nb_json`, including
  nested Phoenix query encoding for Flop-style filters.
- Added opt-in TanStack React Query client generation with query keys, query
  option factories, hooks for `GET` endpoints, and mutation hooks for write
  endpoints.
- Added compile-time DSL verification for duplicate declarations, response
  contracts, path params, shape fields, status codes, and opt-in controller
  action checks.
- Added optional JSON:API response profiles with `type`/`id`/`attributes` and
  relationship conventions, including response DSL defaults, OpenAPI schemas,
  and TypeScript client output.
- Added auth contracts, app-provided authentication and authorization adapter
  behaviours, `NbJson.Plug.Secure`, OpenAPI security generation, and generated
  TypeScript bearer/API key auth header support.
- Added production smoke coverage for fresh Phoenix installation, real
  Phoenix/OpenApiSpex request flow, and strict TypeScript client compilation.
- Fixed installer companion dependency handling so fresh apps receive
  `open_api_spex` before the generated ApiSpec is compiled.
- Fixed serializer tuple detection so nested keyword data is not mistaken for
  an `nb_serializer` module tuple.
- Removed compile warnings when optional `Decimal` or `NbSerializer.Config`
  modules are not installed.

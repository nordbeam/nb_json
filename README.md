# NbJson

`NbJson` is the Phoenix JSON API companion for the `nb_` ecosystem. Where
`nb_inertia` optimizes Phoenix + Inertia.js DX, `nb_json` focuses on Phoenix
controllers that serve JSON APIs.

The package is designed as a composition layer, not a replacement for existing
packages:

- `nb_serializer` owns resource serialization.
- `nb_ts` can consume contracts for TypeScript output.
- `nb_routes` can provide typed API route helpers.
- `nb_flop` can provide pagination/filter metadata.
- `nb_json` ties those pieces together for API contracts, response envelopes,
  OpenAPI metadata, and Phoenix rendering.

## Goals

- Declare request and response contracts next to controller actions.
- Render consistent success and error envelopes.
- Materialize `nb_serializer` tuples automatically when installed.
- Generate OpenAPI from the same declarations, with `nb_serializer` components.
- Interoperate with `open_api_spex` for serving, casting, and validation.
- Keep every integration optional so Phoenix APIs can adopt pieces gradually.

## Installation

```elixir
def deps do
  [
    {:nb_json, "~> 0.1.0"}
  ]
end
```

With Igniter:

```bash
mix igniter.install nb_json --with-typescript
```

By default the installer also adds `open_api_spex` because that is the
recommended production path for serving specs and validating requests. Pass
`--no-with-open-api-spex` only when you want plain JSON spec generation.

## Quick Start

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  use NbJson.Controller

  alias MyApp.Accounts
  alias MyAppWeb.Serializers.UserSerializer

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug NbJson.Plug.Validate

  json_endpoint :index,
    method: :get,
    path: "/api/users",
    tags: ["Users"],
    security: [bearerAuth: []] do
    params do
      field :page, :integer, optional: true
      field :search, :string, optional: true
    end

    response 200, description: "Users list" do
      data :users, list_of(ref(UserSerializer))
      meta :pagination, shape(page: :integer, total: :integer)
    end

    error 422, code: :validation_failed
  end

  def index(conn, _params) do
    params = conn.private.nb_json_params
    users = Accounts.list_users(params)

    render_json(conn, :index,
      users: serialize(UserSerializer, users),
      meta: %{pagination: %{page: 1, total: length(users)}}
    )
  end
end
```

The response shape is:

```json
{
  "data": {
    "users": []
  },
  "meta": {
    "pagination": {
      "page": 1,
      "total": 0
    }
  }
}
```

## Error Responses

```elixir
render_error(conn, :not_found, "User not found")
```

```json
{
  "error": {
    "code": "not_found",
    "message": "User not found",
    "status": 404
  }
}
```

Validation details can be built from plain maps or Ecto changesets:

```elixir
NbJson.Response.validation_error(changeset)
```

## Compile-Time DSL Verification

`json_endpoint` contracts are validated while the controller module compiles.
These mistakes fail before the app boots:

- duplicate endpoint names
- duplicate request params
- duplicate response status codes
- duplicate `data` or `meta` response keys
- missing success responses
- invalid HTTP status codes
- invalid param locations
- path placeholders without matching `location: :path` fields
- `location: :path` fields that do not appear in the path
- duplicate fields inside `shape(...)`

For controller modules, enable action verification when you want every
`json_endpoint :name` to require a matching `def name(conn, params)`:

```elixir
use NbJson.Controller, validate_actions: true
```

That option is off by default so contract-only modules can still be used for
tests, generated specs, or shared API descriptions.

## Request Validation

Declared `params` can validate regular Phoenix params maps. Values are returned
with atom keys and common scalar types are coerced from strings:

```elixir
case validate_json_params(:index, %{"page" => "2", "search" => "ada"}) do
  {:ok, params} ->
    # %{page: 2, search: "ada"}
    render_json(conn, :index, users: list_users(params))

  {:error, errors} ->
    # %{page: ["must be an integer"]}
    render_validation_error(conn, errors)
end
```

Or let `NbJson.Plug.Validate` validate every request before it reaches the
action:

```elixir
plug NbJson.Plug.Validate

def index(conn, _params) do
  params = conn.private.nb_json_params
  render_json(conn, :index, users: Accounts.list_users(params))
end
```

The plug infers the controller/action in Phoenix. For router pipelines or other
Plug apps, pass `controller:` and `endpoint:` explicitly.

## OpenAPI

Generate an OpenAPI document from controller declarations. Serializer refs that
expose `nb_serializer` metadata are expanded into reusable component schemas:

```bash
mix nb_json.openapi MyAppWeb.UserController --output priv/openapi.json
```

Or from Elixir:

```elixir
NbJson.OpenApi.to_map([MyAppWeb.UserController],
  title: "My API",
  version: "1.0.0"
)
```

For production Phoenix apps, install `open_api_spex` and expose the same
contract as an `OpenApiSpex.OpenApi` spec:

```elixir
defmodule MyAppWeb.ApiSpec do
  use NbJson.OpenApiSpex,
    controllers: [MyAppWeb.UserController],
    title: "My API",
    version: "1.0.0",
    servers: ["https://api.example.com"],
    security_schemes: [
      bearerAuth: :bearer
    ]
end
```

Then put the spec in the API pipeline and run request validation in controllers
that declare `json_endpoint` contracts:

```elixir
pipeline :api do
  plug OpenApiSpex.Plug.PutApiSpec, module: MyAppWeb.ApiSpec
end

scope "/api" do
  pipe_through :api
  get "/openapi", OpenApiSpex.Plug.RenderSpec, []
end

defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  use NbJson.Controller

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug NbJson.Plug.Validate
end
```

`OpenApiSpex.Plug.CastAndValidate` should run in the controller, where Phoenix
has already assigned controller/action metadata for operation inference.

`NbJson.OpenApi.to_open_api_spex/2` is also available for tests and custom
integration code.

Endpoint metadata maps directly to OpenAPI operation fields:

```elixir
json_endpoint :create,
  method: :post,
  path: "/api/users",
  operation_id: "users.create",
  tags: ["Users"],
  security: [%{bearerAuth: ["users:write"]}],
  request_body_description: "Create a user" do
  params do
    field :name, :string
  end

  response 201 do
    data :user, ref(UserSerializer)
  end
end
```

In controller tests, validate actual responses against the generated spec:

```elixir
import NbJson.TestAssertions

conn =
  conn
  |> OpenApiSpex.Plug.PutApiSpec.call(MyAppWeb.ApiSpec)
  |> get(~p"/api/users")

assert_json_response(conn, MyAppWeb.UserController, :index)
```

## TypeScript Client

Generate a dependency-free fetch client and exported request/response types from
the same contracts:

```bash
mix nb_json.gen.client MyAppWeb.UserController --output assets/js/api.ts
```

Example generated usage:

```typescript
import { usersIndex } from '@/api';

const response = await usersIndex({ page: 2, search: 'ada' });
response.data.users;
```

By default, serializer refs import the matching generated serializer types, which
fits apps that also use `nb_ts`. For standalone API clients, emit fallback
aliases instead:

```bash
mix nb_json.gen.client MyAppWeb.UserController \
  --output assets/js/api.ts \
  --no-serializer-imports
```

When you use `nb_ts`, the same `nb_json` contracts can be included in the wider
generated type bundle:

```bash
mix nb_ts.gen --output-dir assets/js/types
```

### React Query

React apps should use TanStack React Query for caching, background refetching,
mutations, optimistic updates, and server-state lifecycles. `nb_json` can emit
query keys, query option factories, and hooks next to the raw fetch helpers:

```bash
npm install @tanstack/react-query
mix nb_json.gen.client MyAppWeb.UserController \
  --output assets/js/api.ts \
  --react-query
```

Generated `GET` endpoints include stable query keys, reusable query options, and
hooks:

```typescript
import { usersIndexQueryOptions, useUsersIndex } from '@/api';

const users = useUsersIndex({ page: 1 });

// Also works with loaders, prefetching, and SSR helpers:
queryClient.prefetchQuery(usersIndexQueryOptions({ page: 1 }));
```

Generated non-`GET` endpoints become mutations:

```typescript
import { useUsersCreate, usersIndexQueryRootKey } from '@/api';

const createUser = useUsersCreate({
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: usersIndexQueryRootKey() });
  }
});

createUser.mutate({ name: 'Ada', active: true });
```

The raw fetch functions are still generated in the same file, so teams can use
React Query in app code while keeping tests, scripts, and non-React clients on
plain promises.

## JSON:API Profile

APIs that prefer JSON:API conventions can opt in per response. The profile keeps
the same controller DSL, OpenAPI generation, TypeScript client output, and
runtime rendering path:

```elixir
json_endpoint :show, method: :get, path: "/api/articles/:id" do
  params do
    field :id, :uuid, location: :path
  end

  response 200,
    profile: :json_api,
    type: "articles",
    relationships: [author: [type: "people"], comments: [type: "comments"]] do
    data :article, ref(ArticleSerializer)
  end
end

def show(conn, %{"id" => id}) do
  article = Blog.get_article!(id)

  render_json(conn, :show,
    article: %{
      id: article.id,
      title: article.title,
      author: %{id: article.author_id},
      comments: Enum.map(article.comments, &%{id: &1.id})
    }
  )
end
```

The rendered document follows JSON:API resource object conventions:

```json
{
  "data": {
    "type": "articles",
    "id": "1",
    "attributes": {
      "title": "Typed APIs"
    },
    "relationships": {
      "author": {
        "data": { "type": "people", "id": "2" }
      },
      "comments": {
        "data": [{ "type": "comments", "id": "3" }]
      }
    }
  }
}
```

`profile: :json_api` requires exactly one `data` field in the response DSL, so
bad contracts fail at compile time. At runtime `:meta`, `:links`, and
`:included` assigns are lifted to the JSON:API top level. Direct helper usage is
also available:

```elixir
NbJson.Response.success([user: %{id: 1, name: "Ada"}],
  profile: :json_api,
  type: "users"
)
```

## Production Smoke Checks

The default suite covers the library and an in-process Phoenix/OpenApiSpex
router flow. Heavier release smoke checks are tagged so they can be run before
publishing or upgrading a production app:

```bash
mix test
mix test --include production_smoke test/smoke/production_smoke_test.exs
```

The production smoke creates a fresh Phoenix API project, installs `nb_json`
from the local package path, compiles it with warnings as errors, and compiles
the generated TypeScript client with strict TypeScript.

## Flop Params

List endpoints can declare Flop-compatible pagination, sorting, and filters
without repeating the same params everywhere:

```elixir
json_endpoint :index, method: :get, path: "/api/users" do
  params do
    flop_params pagination: :all
  end

  response 200 do
    data :users, list_of(ref(UserSerializer))
    flop_meta()
  end
end
```

`flop_params/1` emits query params for page, offset, and cursor pagination,
sorting, and linear filter lists. The validated output is plain atom-keyed data
that can be passed into your Flop query layer.

## Contract Types

`NbJson.Controller` imports the same Elixir-first type style used across the
`nb_` packages:

```elixir
field :id, :uuid
field :status, enum([:draft, :published])
data :users, list_of(ref(UserSerializer))
meta :pagination, shape(page: :integer, total: :integer)
data :subject, union([ref(UserSerializer), ref(TeamSerializer)])
data :deleted_at, nullable(:datetime)
```

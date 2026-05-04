defmodule NbJson.OpenApiTest do
  use ExUnit.Case

  defmodule UserSerializer do
  end

  defmodule ProfileSerializer do
    def __nb_serializer_type_metadata__ do
      %{
        bio: %{type: :string, optional: true, nullable: true},
        public: %{type: :boolean, optional: false, nullable: false}
      }
    end
  end

  defmodule RichUserSerializer do
    def __nb_serializer_type_metadata__ do
      %{
        id: %{type: :uuid, optional: false, nullable: false},
        full_name: %{type: :string, optional: false, nullable: false},
        status: %{enum: ["active", "disabled"], optional: false, nullable: false},
        tags: %{type: :string, list: true, optional: true, nullable: false},
        profile: %{serializer: ProfileSerializer, optional: true, nullable: true}
      }
    end
  end

  defmodule ArticleSerializer do
    use NbSerializer.Serializer

    namespace("API")

    schema do
      field(:id, :uuid)
      field(:title, :string)
      field(:internal_code, :string, if: :include_internal?)
    end

    def include_internal?(_data, _opts), do: false
  end

  defmodule AuthorSerializer do
    use NbSerializer.Serializer

    typescript_name("Writer")

    schema do
      field(:id, :uuid)
      field(:full_name, :string)
      has_many(:posts, serializer: ArticleSerializer, key: :articles)
    end
  end

  defmodule ActorUser do
    defstruct [:id]
  end

  defmodule ActorProfile do
    defstruct [:id]
  end

  defmodule ActivitySerializer do
    def __nb_serializer_type_metadata__ do
      %{
        id: %{type: :uuid, optional: false, nullable: false},
        actor: %{
          polymorphic: [
            {ActorUser, RichUserSerializer},
            {ActorProfile, ProfileSerializer}
          ],
          optional: false,
          nullable: false
        }
      }
    end
  end

  defmodule UsersController do
    use NbJson.Controller

    json_endpoint :index, method: :get, path: "/api/users", summary: "List users" do
      params do
        field(:page, :integer, optional: true)
      end

      response 200 do
        data(:users, list_of(ref(UserSerializer)))
      end

      error(404, code: :not_found)
    end

    json_endpoint :create, method: :post, path: "/api/users" do
      params do
        field(:name, :string)
        field(:active, :boolean, optional: true)
      end

      response 201 do
        data(:id, :uuid)
      end
    end
  end

  defmodule RichUsersController do
    use NbJson.Controller

    json_endpoint :show,
      method: :get,
      path: "/api/users/{id}",
      tags: ["Users"],
      security: [bearerAuth: []] do
      params do
        field(:id, :uuid, location: :path)
      end

      response 200 do
        data(:user, ref(RichUserSerializer))
        data(:author, ref(AuthorSerializer))
        data(:activity, ref(ActivitySerializer))
      end
    end

    json_endpoint :create,
      method: :post,
      path: "/api/users",
      operation_id: "users.create",
      tags: ["Users"],
      deprecated: true,
      security: [%{bearerAuth: ["users:write"]}],
      request_body_description: "Create a user" do
      params do
        field(:name, :string)
      end

      response 201 do
        data(:user, ref(RichUserSerializer))
      end
    end
  end

  defmodule ApiSpec do
    use NbJson.OpenApiSpex,
      controllers: [NbJson.OpenApiTest.RichUsersController],
      title: "Rich API",
      version: "2.0.0",
      servers: ["https://api.example.com"]
  end

  test "generates OpenAPI paths from endpoint contracts" do
    doc = NbJson.OpenApi.to_map(UsersController, title: "Example API", version: "1.0.0")

    assert doc["info"] == %{"title" => "Example API", "version" => "1.0.0"}
    assert %{"get" => operation} = doc["paths"]["/api/users"]
    assert operation["operationId"] == "#{inspect(UsersController)}.index"
    assert [%{"name" => "page", "required" => false}] = operation["parameters"]
    assert %{"200" => _, "404" => _} = operation["responses"]
  end

  test "generates request bodies for body params" do
    doc = NbJson.OpenApi.to_map(UsersController)

    assert %{"post" => operation} = doc["paths"]["/api/users"]
    assert operation["parameters"] == []

    assert %{
             "content" => %{
               "application/json" => %{
                 "schema" => %{
                   "properties" => %{"name" => %{"type" => "string"}},
                   "required" => ["name"]
                 }
               }
             }
           } = operation["requestBody"]
  end

  test "expands nb_serializer metadata into OpenAPI component schemas" do
    doc =
      NbJson.OpenApi.to_map(RichUsersController,
        security_schemes: [bearerAuth: :bearer],
        security: [bearerAuth: []]
      )

    assert doc["openapi"] == "3.0.3"
    assert doc["security"] == [%{"bearerAuth" => []}]

    assert doc["components"]["securitySchemes"]["bearerAuth"] == %{
             "type" => "http",
             "scheme" => "bearer"
           }

    assert %{
             "RichUser" => rich_user,
             "Profile" => profile,
             "Writer" => writer,
             "APIArticle" => article,
             "Activity" => activity
           } = doc["components"]["schemas"]

    assert rich_user["properties"]["id"] == %{"type" => "string", "format" => "uuid"}
    assert rich_user["properties"]["fullName"] == %{"type" => "string"}
    assert rich_user["properties"]["status"] == %{"enum" => ["active", "disabled"]}

    assert rich_user["properties"]["tags"] == %{
             "type" => "array",
             "items" => %{"type" => "string"}
           }

    assert rich_user["properties"]["profile"] == %{
             "allOf" => [%{"$ref" => "#/components/schemas/Profile"}],
             "nullable" => true
           }

    assert rich_user["required"] == ["fullName", "id", "status"]
    assert profile["properties"]["bio"] == %{"type" => "string", "nullable" => true}
    assert profile["properties"]["public"] == %{"type" => "boolean"}
    assert profile["required"] == ["public"]

    assert writer["properties"]["articles"]["items"] == %{
             "$ref" => "#/components/schemas/APIArticle"
           }

    assert article["properties"]["internalCode"] == %{"type" => "string"}
    refute "internalCode" in article["required"]

    assert activity["properties"]["actor"] == %{
             "oneOf" => [
               %{"$ref" => "#/components/schemas/RichUser"},
               %{"$ref" => "#/components/schemas/Profile"}
             ]
           }

    response_schema =
      doc["paths"]["/api/users/{id}"]["get"]["responses"]["200"]["content"]["application/json"][
        "schema"
      ]

    assert response_schema["properties"]["data"]["properties"]["user"] == %{
             "$ref" => "#/components/schemas/RichUser"
           }

    operation = doc["paths"]["/api/users/{id}"]["get"]
    assert operation["tags"] == ["Users"]
    assert operation["security"] == [%{"bearerAuth" => []}]

    create = doc["paths"]["/api/users"]["post"]
    assert create["operationId"] == "users.create"
    assert create["deprecated"] == true
    assert create["security"] == [%{"bearerAuth" => ["users:write"]}]
    assert create["requestBody"]["description"] == "Create a user"
  end

  test "converts generated documents to OpenApiSpex structs when available" do
    if Code.ensure_loaded?(OpenApiSpex.OpenApi) do
      spec = NbJson.OpenApi.to_open_api_spex(RichUsersController)

      assert %OpenApiSpex.OpenApi{} = spec
      assert spec.openapi == "3.0.3"
      assert Map.has_key?(spec.components.schemas, "RichUser")
    end
  end

  test "builds an OpenApiSpex operation for a controller action" do
    operation = NbJson.OpenApi.open_api_operation(RichUsersController, :show)

    assert %OpenApiSpex.Operation{} = operation
    assert operation.operationId == "#{inspect(RichUsersController)}.show"
    assert operation.security == [%{"bearerAuth" => []}]
  end

  test "defines an OpenApiSpex behaviour module from controller contracts" do
    spec = ApiSpec.spec()

    assert %OpenApiSpex.OpenApi{} = spec
    assert spec.info.title == "Rich API"
    assert spec.info.version == "2.0.0"
    assert [%OpenApiSpex.Server{url: "https://api.example.com"}] = spec.servers
  end
end

defmodule NbJson.PhoenixPipelineSmokeTest do
  use ExUnit.Case

  import NbJson.TestAssertions
  import Plug.Test

  defmodule UserSerializer do
    def __nb_serializer_type_metadata__ do
      %{
        fields: [
          %{name: :id, type: :uuid, opts: []},
          %{name: :name, type: :string, opts: []}
        ]
      }
    end
  end

  defmodule UsersController do
    use Phoenix.Controller, formats: [:json]
    use NbJson.Controller

    plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)
    plug(NbJson.Plug.Validate)

    json_endpoint :index, method: :get, path: "/api/users", tags: ["Users"] do
      params do
        field(:page, :integer, optional: true)
      end

      response 200 do
        data(:page, :integer)
        data(:users, list_of(ref(UserSerializer)))
      end

      error(422, details: shape(page: list_of(:string)))
    end

    json_endpoint :create,
      method: :post,
      path: "/api/users",
      tags: ["Users"],
      request_body_description: "User create payload" do
      params do
        field(:name, :string)
        field(:active, :boolean, default: true)
      end

      response 201 do
        data(:id, :uuid)
      end

      error(422)
    end

    def index(conn, _params) do
      page = Map.get(conn.assigns.nb_json_params, :page, 1)

      render_json(conn, :index,
        page: page,
        users: [
          %{
            id: "123e4567-e89b-12d3-a456-426614174000",
            name: "Ada"
          }
        ]
      )
    end

    def create(conn, _params) do
      render_json(conn, :create, id: "123e4567-e89b-12d3-a456-426614174000")
    end
  end

  defmodule ApiSpec do
    use NbJson.OpenApiSpex,
      controllers: [NbJson.PhoenixPipelineSmokeTest.UsersController],
      title: "Smoke API",
      version: "1.0.0"
  end

  defmodule Router do
    use Phoenix.Router

    pipeline :api do
      plug(:accepts, ["json"])

      plug(Plug.Parsers,
        parsers: [:json],
        pass: ["application/json"],
        json_decoder: Jason
      )

      plug(OpenApiSpex.Plug.PutApiSpec, module: ApiSpec)
    end

    scope "/api" do
      pipe_through(:api)

      get("/users", UsersController, :index)
      post("/users", UsersController, :create)
    end
  end

  test "valid GET requests pass through Phoenix, OpenApiSpex, NbJson validation, and response assertions" do
    conn =
      :get
      |> conn("/api/users?page=2")
      |> Router.call(Router.init([]))

    assert conn.status == 200
    assert conn.assigns.nb_json_params == %{page: 2}

    assert Jason.decode!(conn.resp_body) == %{
             "data" => %{
               "page" => 2,
               "users" => [
                 %{
                   "id" => "123e4567-e89b-12d3-a456-426614174000",
                   "name" => "Ada"
                 }
               ]
             }
           }

    assert_json_response(conn, UsersController, :index)
  end

  test "invalid query params are rejected in the real router pipeline" do
    conn =
      :get
      |> conn("/api/users?page=bad")
      |> Router.call(Router.init([]))

    assert conn.status == 422
    assert conn.halted
    assert %{"errors" => _errors} = Jason.decode!(conn.resp_body)
  end

  test "JSON body requests are cast, validated, rendered, and response-validated" do
    conn =
      :post
      |> conn("/api/users", Jason.encode!(%{name: "Ada", active: true}))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Router.call(Router.init([]))

    assert conn.status == 201
    assert conn.assigns.nb_json_params == %{name: "Ada", active: true}

    assert Jason.decode!(conn.resp_body) == %{
             "data" => %{"id" => "123e4567-e89b-12d3-a456-426614174000"}
           }

    assert_json_response(conn, UsersController, :create)
  end
end

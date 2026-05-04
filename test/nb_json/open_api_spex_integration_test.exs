defmodule NbJson.OpenApiSpexIntegrationTest do
  use ExUnit.Case
  import Plug.Test

  defmodule UserSerializer do
    def __nb_serializer_type_metadata__ do
      %{
        id: %{type: :uuid, optional: false, nullable: false},
        name: %{type: :string, optional: false, nullable: false}
      }
    end
  end

  defmodule UsersController do
    use NbJson.Controller

    json_endpoint :index,
      method: :get,
      path: "/api/users",
      tags: ["Users"],
      security: [bearerAuth: []] do
      params do
        field(:page, :integer, optional: true)
      end

      response 200 do
        data(:users, list_of(ref(UserSerializer)))
      end
    end
  end

  defmodule ApiSpec do
    use NbJson.OpenApiSpex,
      controllers: [NbJson.OpenApiSpexIntegrationTest.UsersController],
      title: "Integration API",
      version: "1.0.0",
      security_schemes: [bearerAuth: :bearer]
  end

  test "OpenApiSpex CastAndValidate can infer nb_json controller operations" do
    conn =
      :get
      |> conn("/api/users?page=2")
      |> Plug.Conn.fetch_query_params()
      |> Plug.Conn.put_private(:phoenix_controller, UsersController)
      |> Plug.Conn.put_private(:phoenix_action, :index)
      |> OpenApiSpex.Plug.PutApiSpec.call(ApiSpec)
      |> OpenApiSpex.Plug.CastAndValidate.call(
        OpenApiSpex.Plug.CastAndValidate.init(json_render_error_v2: true)
      )

    assert conn.private.open_api_spex.operation_id == "#{inspect(UsersController)}.index"
    assert conn.params[:page] == 2
  end

  test "validates rendered JSON responses against the generated OpenApiSpex spec" do
    operation_id = "#{inspect(UsersController)}.index"

    body =
      UsersController.build_json(:index,
        users: [
          %{
            id: "123e4567-e89b-12d3-a456-426614174000",
            name: "Ada"
          }
        ]
      )

    conn =
      :get
      |> conn("/api/users?page=2")
      |> OpenApiSpex.Plug.PutApiSpec.call(ApiSpec)
      |> Plug.Conn.put_private(:open_api_spex, %{
        spec_module: ApiSpec,
        operation_id: operation_id
      })
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))

    assert NbJson.TestAssertions.assert_json_response(conn, UsersController, :index) == conn
  end
end

defmodule NbJson.Plug.ValidateTest do
  use ExUnit.Case
  import Plug.Test

  defmodule UsersController do
    use NbJson.Controller

    json_endpoint :index, method: :get, path: "/api/users" do
      params do
        field(:page, :integer, optional: true)
        field(:active, :boolean, optional: true)
      end

      response 200 do
        data(:users, :list)
      end
    end
  end

  test "validates params and stores coerced values in conn private and assigns" do
    conn =
      :get
      |> conn("/api/users?page=2&active=true")
      |> Plug.Conn.fetch_query_params()
      |> Plug.Conn.put_private(:phoenix_controller, UsersController)
      |> Plug.Conn.put_private(:phoenix_action, :index)
      |> NbJson.Plug.Validate.call(NbJson.Plug.Validate.init([]))

    assert conn.private.nb_json_params == %{page: 2, active: true}
    assert conn.assigns.nb_json_params == %{page: 2, active: true}
    refute conn.halted
  end

  test "renders validation errors and halts invalid requests" do
    conn =
      :get
      |> conn("/api/users?page=bad")
      |> Plug.Conn.fetch_query_params()
      |> NbJson.Plug.Validate.call(
        NbJson.Plug.Validate.init(controller: UsersController, endpoint: :index)
      )

    assert conn.halted
    assert conn.status == 422

    assert Jason.decode!(conn.resp_body) == %{
             "error" => %{
               "code" => "validation_failed",
               "message" => "Validation failed",
               "status" => 422,
               "details" => %{"page" => ["must be an integer"]}
             }
           }
  end
end

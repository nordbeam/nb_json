defmodule NbJson.AuthPlugTest do
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  defmodule AuthAdapter do
    @behaviour NbJson.Auth

    @impl true
    def authenticate(conn, auth, _opts) do
      send(self(), {:auth_contract, auth})

      case get_req_header(conn, "authorization") do
        ["Bearer valid"] -> {:ok, %{id: 1}, %{scopes: ["users:read"]}}
        ["Bearer forbidden"] -> {:ok, %{id: 2}, %{scopes: []}}
        ["Bearer expired"] -> {:error, :expired}
        [] -> {:error, :missing}
        _other -> {:error, :invalid}
      end
    end
  end

  defmodule AuthorizationAdapter do
    @behaviour NbJson.Authorization

    @impl true
    def authorize(%{id: 1}, requirement, conn, _opts) do
      send(self(), {:authorization_requirement, requirement, conn.path_params})
      :ok
    end

    def authorize(_subject, requirement, _conn, _opts) do
      send(self(), {:authorization_requirement, requirement, %{}})
      {:error, :forbidden}
    end
  end

  defmodule UsersController do
    use NbJson.Controller

    json_endpoint :show,
      method: :get,
      path: "/api/accounts/:account_id/users/:id",
      auth: [scheme: :bearer, scopes: ["users:read"], realm: "api"] do
      params do
        field(:account_id, :uuid, location: :path)
        field(:id, :uuid, location: :path)
      end

      authorize(resource: :user, action: :read, id: :id, tenant: :account_id)

      response 200 do
        data(:ok, :boolean)
      end
    end

    json_endpoint :optional, method: :get, path: "/api/optional", auth: [optional: true] do
      response 200 do
        data(:ok, :boolean)
      end
    end

    json_endpoint :public, method: :get, path: "/api/public" do
      response 200 do
        data(:ok, :boolean)
      end
    end
  end

  test "authenticate stores subject and claims for protected endpoints" do
    conn =
      :get
      |> conn("/api/accounts/acc/users/user")
      |> put_req_header("authorization", "Bearer valid")
      |> put_private(:phoenix_controller, UsersController)
      |> put_private(:phoenix_action, :show)
      |> NbJson.Plug.Authenticate.call(%{auth_adapter: AuthAdapter})

    assert conn.assigns.nb_json_subject == %{id: 1}
    assert conn.assigns.nb_json_claims == %{scopes: ["users:read"]}

    assert_receive {:auth_contract,
                    %{
                      scheme: :bearer,
                      scopes: ["users:read"],
                      security_scheme: :bearerAuth
                    }}
  end

  test "authenticate returns a standard 401 for missing credentials" do
    conn =
      :get
      |> conn("/api/accounts/acc/users/user")
      |> put_private(:phoenix_controller, UsersController)
      |> put_private(:phoenix_action, :show)
      |> NbJson.Plug.Authenticate.call(%{auth_adapter: AuthAdapter})

    assert conn.status == 401
    assert conn.halted
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer, realm="api")]

    assert Jason.decode!(conn.resp_body) == %{
             "error" => %{
               "code" => "missing_credentials",
               "message" => "Authentication required",
               "status" => 401
             }
           }
  end

  test "authenticate lets optional auth continue when credentials are missing" do
    conn =
      :get
      |> conn("/api/optional")
      |> put_private(:phoenix_controller, UsersController)
      |> put_private(:phoenix_action, :optional)
      |> NbJson.Plug.Authenticate.call(%{auth_adapter: AuthAdapter})

    refute conn.halted
    refute Map.has_key?(conn.assigns, :nb_json_subject)
  end

  test "authorize calls the app policy adapter with declared requirements" do
    conn =
      :get
      |> conn("/api/accounts/acc/users/user")
      |> Map.put(:path_params, %{"account_id" => "acc", "id" => "user"})
      |> put_private(:phoenix_controller, UsersController)
      |> put_private(:phoenix_action, :show)
      |> assign(:nb_json_subject, %{id: 1})
      |> NbJson.Plug.Authorize.call(%{authorization_adapter: AuthorizationAdapter})

    refute conn.halted

    assert_receive {:authorization_requirement,
                    %{resource: :user, action: :read, id: :id, tenant: :account_id},
                    %{"account_id" => "acc", "id" => "user"}}
  end

  test "secure plug authenticates and authorizes in order" do
    conn =
      :get
      |> conn("/api/accounts/acc/users/user")
      |> put_req_header("authorization", "Bearer valid")
      |> put_private(:phoenix_controller, UsersController)
      |> put_private(:phoenix_action, :show)
      |> NbJson.Plug.Secure.call(%{
        auth_adapter: AuthAdapter,
        authorization_adapter: AuthorizationAdapter
      })

    refute conn.halted
    assert conn.assigns.nb_json_subject == %{id: 1}
    assert_receive {:authorization_requirement, %{action: :read}, _path_params}
  end

  test "secure plug returns 403 when authorization fails" do
    conn =
      :get
      |> conn("/api/accounts/acc/users/user")
      |> put_req_header("authorization", "Bearer forbidden")
      |> put_private(:phoenix_controller, UsersController)
      |> put_private(:phoenix_action, :show)
      |> NbJson.Plug.Secure.call(%{
        auth_adapter: AuthAdapter,
        authorization_adapter: AuthorizationAdapter
      })

    assert conn.status == 403
    assert conn.halted

    assert Jason.decode!(conn.resp_body) == %{
             "error" => %{
               "code" => "forbidden",
               "message" => "Forbidden",
               "status" => 403
             }
           }
  end

  test "public endpoints skip auth" do
    conn =
      :get
      |> conn("/api/public")
      |> put_private(:phoenix_controller, UsersController)
      |> put_private(:phoenix_action, :public)
      |> NbJson.Plug.Secure.call(%{
        auth_adapter: AuthAdapter,
        authorization_adapter: AuthorizationAdapter
      })

    refute conn.halted
    refute_received {:auth_contract, _auth}
  end
end

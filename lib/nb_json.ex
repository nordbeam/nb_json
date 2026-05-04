defmodule NbJson do
  @moduledoc """
  Phoenix JSON API developer experience for the nb ecosystem.

  `NbJson` is intentionally a composition layer:

  * endpoint contracts live next to Phoenix controllers
  * response envelopes are consistent across controllers
  * `NbSerializer` tuples are materialized automatically when the dependency is installed
  * OpenAPI metadata can be generated from the same declarations

  ## Example

      defmodule MyAppWeb.UserController do
        use MyAppWeb, :controller
        use NbJson.Controller

        alias MyAppWeb.Serializers.UserSerializer

        json_endpoint :index, method: :get, path: "/api/users" do
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
          render_json(conn, :index,
            users: serialize(UserSerializer, list_users()),
            meta: %{pagination: %{page: 1, total: 20}}
          )
        end
      end
  """

  @version "0.1.0"

  @doc "Returns the current NbJson version."
  def version, do: @version
end

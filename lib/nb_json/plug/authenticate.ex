defmodule NbJson.Plug.Authenticate do
  @moduledoc """
  Plug for authenticating requests against `json_endpoint` auth contracts.

  The plug infers `:controller` and `:endpoint` from Phoenix metadata, matching
  `NbJson.Plug.Validate`. Applications provide an auth adapter through plug opts
  or config:

      config :nb_json, auth_adapter: MyAppWeb.ApiAuth

      plug NbJson.Plug.Authenticate

  On success, the subject is stored in `conn.private[:nb_json_subject]` and
  `conn.assigns[:nb_json_subject]`. Claims are stored under `:nb_json_claims`.
  """

  @doc false
  def init(opts), do: Map.new(opts)

  @doc false
  def call(conn, opts) do
    with {:ok, endpoint} <- fetch_endpoint(conn, opts),
         %{auth: auth} when not is_nil(auth) <- endpoint do
      authenticate(conn, auth, opts)
    else
      %{auth: nil} -> conn
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp authenticate(conn, auth, opts) do
    adapter = Map.get(opts, :auth_adapter) || Application.get_env(:nb_json, :auth_adapter)

    case NbJson.Auth.authenticate(adapter, conn, auth, Map.to_list(opts)) do
      {:ok, subject} ->
        put_subject(conn, subject, %{})

      {:ok, subject, claims} when is_map(claims) ->
        put_subject(conn, subject, claims)

      {:error, reason} ->
        if auth.optional and NbJson.Auth.missing_reason?(reason) do
          conn
        else
          conn
          |> maybe_put_www_authenticate(auth, reason)
          |> render_error(reason, opts)
          |> halt()
        end

      other ->
        raise ArgumentError,
              "auth adapter returned #{inspect(other)}. Expected {:ok, subject}, " <>
                "{:ok, subject, claims}, or {:error, reason}."
    end
  end

  defp fetch_endpoint(conn, opts) do
    controller = Map.get(opts, :controller) || conn.private[:phoenix_controller]
    endpoint = Map.get(opts, :endpoint) || Map.get(opts, :action) || conn.private[:phoenix_action]

    if is_atom(controller) and is_atom(endpoint) do
      NbJson.Controller.fetch_endpoint(controller, endpoint)
    else
      {:error,
       "NbJson.Plug.Authenticate requires a controller and endpoint. " <>
         "Pass :controller/:endpoint or use it inside a Phoenix controller."}
    end
  end

  defp put_subject(conn, subject, claims) do
    conn
    |> put_private(:nb_json_subject, subject)
    |> put_private(:nb_json_claims, claims)
    |> put_assign(:nb_json_subject, subject)
    |> put_assign(:nb_json_claims, claims)
  end

  defp render_error(conn, reason, opts) do
    case Map.get(opts, :render_auth_error) || Map.get(opts, :render_error) do
      nil ->
        NbJson.Controller.render_error(
          conn,
          NbJson.Auth.error_code(reason),
          NbJson.Auth.error_message(reason),
          status: 401
        )

      module when is_atom(module) ->
        apply(module, :call, [conn, reason])

      {module, function} when is_atom(module) and is_atom(function) ->
        apply(module, function, [conn, reason])

      function when is_function(function, 2) ->
        function.(conn, reason)
    end
  end

  defp maybe_put_www_authenticate(conn, %{scheme: :bearer} = auth, reason) do
    challenge =
      ["Bearer", realm(auth), bearer_error(reason)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    put_resp_header(conn, "www-authenticate", challenge)
  end

  defp maybe_put_www_authenticate(conn, _auth, _reason), do: conn

  defp realm(%{realm: realm}) when is_binary(realm), do: ~s(realm="#{realm}")
  defp realm(_auth), do: nil

  defp bearer_error(:invalid), do: ~s(error="invalid_token")
  defp bearer_error(:invalid_credentials), do: ~s(error="invalid_token")
  defp bearer_error(:expired), do: ~s(error="invalid_token")
  defp bearer_error(:expired_credentials), do: ~s(error="invalid_token")
  defp bearer_error(_reason), do: nil

  defp put_private(conn, key, value) do
    if Code.ensure_loaded?(Plug.Conn) do
      apply(Plug.Conn, :put_private, [conn, key, value])
    else
      put_in(conn.private[key], value)
    end
  end

  defp put_assign(conn, key, value) do
    if Code.ensure_loaded?(Plug.Conn) do
      apply(Plug.Conn, :assign, [conn, key, value])
    else
      put_in(conn.assigns[key], value)
    end
  end

  defp put_resp_header(conn, key, value) do
    if Code.ensure_loaded?(Plug.Conn) do
      apply(Plug.Conn, :put_resp_header, [conn, key, value])
    else
      conn
    end
  end

  defp halt(conn) do
    if Code.ensure_loaded?(Plug.Conn) do
      apply(Plug.Conn, :halt, [conn])
    else
      conn
    end
  end
end

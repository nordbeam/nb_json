defmodule NbJson.Plug.Authorize do
  @moduledoc """
  Plug for authorizing requests against endpoint `authorize/1` requirements.

  Use it after `NbJson.Plug.Authenticate`, or pass a custom subject through
  `conn.assigns`/`conn.private`.
  """

  @doc false
  def init(opts), do: Map.new(opts)

  @doc false
  def call(conn, opts) do
    with {:ok, endpoint} <- fetch_endpoint(conn, opts),
         [_ | _] = requirements <- Map.get(endpoint, :authorizations, []) do
      authorize_requirements(conn, requirements, opts)
    else
      [] -> conn
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp authorize_requirements(conn, requirements, opts) do
    case subject(conn, opts) do
      nil ->
        conn
        |> NbJson.Controller.render_error(:unauthorized, "Authentication required", status: 401)
        |> halt()

      subject ->
        adapter =
          Map.get(opts, :authorization_adapter) ||
            Application.get_env(:nb_json, :authorization_adapter)

        Enum.reduce_while(requirements, conn, fn requirement, conn ->
          case NbJson.Authorization.authorize(
                 adapter,
                 subject,
                 requirement,
                 conn,
                 Map.to_list(opts)
               ) do
            :ok ->
              {:cont, conn}

            true ->
              {:cont, conn}

            false ->
              {:halt, forbidden(conn, false, opts)}

            {:error, reason} ->
              {:halt, forbidden(conn, reason, opts)}

            other ->
              raise ArgumentError,
                    "authorization adapter returned #{inspect(other)}. Expected :ok, true, " <>
                      "false, or {:error, reason}."
          end
        end)
    end
  end

  defp subject(conn, opts) do
    key = Map.get(opts, :subject_key, :nb_json_subject)
    assign_key = Map.get(opts, :current_subject_assign, key)

    conn.private[key] || conn.assigns[assign_key] || conn.assigns[key]
  end

  defp forbidden(conn, reason, opts) do
    conn
    |> render_error(reason, opts)
    |> halt()
  end

  defp render_error(conn, reason, opts) do
    case Map.get(opts, :render_authorization_error) || Map.get(opts, :render_error) do
      nil ->
        status = if NbJson.Authorization.error_code(reason) == :unauthorized, do: 401, else: 403

        NbJson.Controller.render_error(
          conn,
          NbJson.Authorization.error_code(reason),
          NbJson.Authorization.error_message(reason),
          status: status
        )

      module when is_atom(module) ->
        apply(module, :call, [conn, reason])

      {module, function} when is_atom(module) and is_atom(function) ->
        apply(module, function, [conn, reason])

      function when is_function(function, 2) ->
        function.(conn, reason)
    end
  end

  defp fetch_endpoint(conn, opts) do
    controller = Map.get(opts, :controller) || conn.private[:phoenix_controller]
    endpoint = Map.get(opts, :endpoint) || Map.get(opts, :action) || conn.private[:phoenix_action]

    if is_atom(controller) and is_atom(endpoint) do
      NbJson.Controller.fetch_endpoint(controller, endpoint)
    else
      {:error,
       "NbJson.Plug.Authorize requires a controller and endpoint. " <>
         "Pass :controller/:endpoint or use it inside a Phoenix controller."}
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

defmodule NbJson.Plug.Validate do
  @moduledoc """
  Plug for validating request params against `NbJson.Controller` contracts.

  In Phoenix controllers, `:controller` and `:endpoint` are inferred from
  `conn.private.phoenix_controller` and `conn.private.phoenix_action`:

      plug NbJson.Plug.Validate

  For router pipelines or non-Phoenix plugs, pass them explicitly:

      plug NbJson.Plug.Validate,
        controller: MyAppWeb.UserController,
        endpoint: :index

  Validated params are stored in `conn.private[:nb_json_params]` and assigned as
  `conn.assigns[:nb_json_params]` when Plug is available.
  """

  @doc false
  def init(opts), do: Map.new(opts)

  @doc false
  def call(conn, opts) do
    controller = Map.get(opts, :controller) || conn.private[:phoenix_controller]
    endpoint = Map.get(opts, :endpoint) || Map.get(opts, :action) || conn.private[:phoenix_action]

    unless is_atom(controller) and is_atom(endpoint) do
      raise ArgumentError,
            "NbJson.Plug.Validate requires a controller and endpoint. " <>
              "Pass :controller/:endpoint or use it inside a Phoenix controller."
    end

    params = request_params(conn)

    case NbJson.Controller.validate_json_params(controller, endpoint, params, Map.to_list(opts)) do
      {:ok, validated} ->
        conn
        |> put_private(:nb_json_params, validated)
        |> put_assign(:nb_json_params, validated)

      {:error, errors} ->
        conn
        |> render_error(errors, opts)
        |> halt()
    end
  end

  defp request_params(conn) do
    [
      map_or_empty(conn.query_params),
      map_or_empty(conn.body_params),
      map_or_empty(conn.path_params),
      map_or_empty(conn.params)
    ]
    |> Enum.reduce(%{}, fn params, acc -> Map.merge(acc, params) end)
  end

  defp map_or_empty(%{} = map) do
    if Map.get(map, :__struct__) == Plug.Conn.Unfetched, do: %{}, else: map
  end

  defp map_or_empty(_value), do: %{}

  defp render_error(conn, errors, opts) do
    case Map.get(opts, :render_error) do
      nil ->
        NbJson.Controller.render_validation_error(conn, errors,
          status: Map.get(opts, :status, 422)
        )

      module when is_atom(module) ->
        apply(module, :call, [conn, errors])

      {module, function} when is_atom(module) and is_atom(function) ->
        apply(module, function, [conn, errors])

      function when is_function(function, 2) ->
        function.(conn, errors)
    end
  end

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

  defp halt(conn) do
    if Code.ensure_loaded?(Plug.Conn) do
      apply(Plug.Conn, :halt, [conn])
    else
      conn
    end
  end
end

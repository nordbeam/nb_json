defmodule NbJson.Controller do
  @moduledoc """
  Controller DSL and rendering helpers for typed Phoenix JSON APIs.

  The DSL records endpoint contracts and can validate runtime request params from
  those same declarations.
  """

  alias NbJson.Response
  alias NbJson.Type

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import NbJson.Controller
      import NbJson.Type

      Module.register_attribute(__MODULE__, :nb_json_endpoints, accumulate: false)
      Module.register_attribute(__MODULE__, :nb_json_current_endpoint, accumulate: false)
      Module.register_attribute(__MODULE__, :nb_json_current_context, accumulate: false)
      Module.register_attribute(__MODULE__, :nb_json_params, accumulate: true)
      Module.register_attribute(__MODULE__, :nb_json_responses, accumulate: true)
      Module.register_attribute(__MODULE__, :nb_json_response_data, accumulate: true)
      Module.register_attribute(__MODULE__, :nb_json_response_meta, accumulate: true)

      Module.put_attribute(__MODULE__, :nb_json_endpoints, %{})

      Module.put_attribute(
        __MODULE__,
        :nb_json_validate_actions,
        Keyword.get(opts, :validate_actions, false)
      )

      if Code.ensure_loaded?(NbTs.CompileHooks) do
        @after_compile {NbTs.CompileHooks, :__after_compile__}
      end

      @before_compile NbJson.Controller

      @doc false
      def render_json(conn, endpoint, assigns, opts \\ []) do
        NbJson.Controller.render_json(__MODULE__, conn, endpoint, assigns, opts)
      end

      @doc false
      def build_json(endpoint, assigns, opts \\ []) do
        NbJson.Controller.build_json(__MODULE__, endpoint, assigns, opts)
      end

      @doc false
      def validate_json_params(endpoint, params, opts \\ []) do
        NbJson.Controller.validate_json_params(__MODULE__, endpoint, params, opts)
      end

      @doc false
      def validate_json_params!(endpoint, params, opts \\ []) do
        NbJson.Controller.validate_json_params!(__MODULE__, endpoint, params, opts)
      end

      @doc false
      def open_api_operation(action) do
        NbJson.OpenApi.open_api_operation(__MODULE__, action)
      end

      defoverridable render_json: 4,
                     build_json: 3,
                     validate_json_params: 3,
                     validate_json_params!: 3,
                     open_api_operation: 1
    end
  end

  @doc """
  Declares a JSON API endpoint contract.

      json_endpoint :index, method: :get, path: "/api/users" do
        params do
          field :page, :integer, optional: true
        end

        response 200 do
          data :users, list_of(ref(UserSerializer))
        end
      end
  """
  defmacro json_endpoint(name, opts \\ [], do: block) do
    quote do
      Module.put_attribute(__MODULE__, :nb_json_current_endpoint, unquote(name))
      Module.delete_attribute(__MODULE__, :nb_json_params)
      Module.delete_attribute(__MODULE__, :nb_json_responses)

      unquote(block)

      params = (Module.get_attribute(__MODULE__, :nb_json_params) || []) |> Enum.reverse()
      responses = (Module.get_attribute(__MODULE__, :nb_json_responses) || []) |> Enum.reverse()

      endpoint =
        NbJson.Controller.build_endpoint_config!(
          unquote(name),
          unquote(opts),
          params,
          responses
        )

      endpoints = Module.get_attribute(__MODULE__, :nb_json_endpoints) || %{}

      if Map.has_key?(endpoints, unquote(name)) do
        raise ArgumentError,
              "duplicate json_endpoint #{inspect(unquote(name))} in #{inspect(__MODULE__)}"
      end

      Module.put_attribute(
        __MODULE__,
        :nb_json_endpoints,
        Map.put(endpoints, unquote(name), endpoint)
      )

      Module.delete_attribute(__MODULE__, :nb_json_current_endpoint)
      Module.delete_attribute(__MODULE__, :nb_json_current_context)
      Module.delete_attribute(__MODULE__, :nb_json_params)
      Module.delete_attribute(__MODULE__, :nb_json_responses)
    end
  end

  @doc """
  Declares request parameters for the current endpoint.
  """
  defmacro params(do: block) do
    quote do
      Module.put_attribute(__MODULE__, :nb_json_current_context, :params)
      unquote(block)
      Module.delete_attribute(__MODULE__, :nb_json_current_context)
    end
  end

  @doc """
  Declares a request parameter.
  """
  defmacro field(name, type \\ :any, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      case Module.get_attribute(__MODULE__, :nb_json_current_context) do
        :params ->
          Module.put_attribute(
            __MODULE__,
            :nb_json_params,
            NbJson.Controller.build_field_config!(name, type, opts)
          )

        other ->
          raise ArgumentError,
                "field/2 and field/3 must be used inside params/1, got context: #{inspect(other)}"
      end
    end
  end

  @doc """
  Declares standard Flop-compatible pagination, sorting, and filter params.

      params do
        flop_params pagination: :page
      end
  """
  defmacro flop_params(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      unless Module.get_attribute(__MODULE__, :nb_json_current_context) == :params do
        raise ArgumentError, "flop_params/1 must be used inside params/1"
      end

      Enum.each(NbJson.Flop.param_specs(opts), fn {name, type} ->
        Module.put_attribute(
          __MODULE__,
          :nb_json_params,
          NbJson.Controller.build_field_config!(name, type,
            optional: true,
            location: :query
          )
        )
      end)
    end
  end

  @doc """
  Declares a success response for the current endpoint.
  """
  defmacro response(status, opts \\ [], do: block) do
    quote do
      Module.put_attribute(__MODULE__, :nb_json_current_context, :response)
      Module.delete_attribute(__MODULE__, :nb_json_response_data)
      Module.delete_attribute(__MODULE__, :nb_json_response_meta)

      unquote(block)

      data = (Module.get_attribute(__MODULE__, :nb_json_response_data) || []) |> Enum.reverse()
      meta = (Module.get_attribute(__MODULE__, :nb_json_response_meta) || []) |> Enum.reverse()

      Module.put_attribute(
        __MODULE__,
        :nb_json_responses,
        NbJson.Controller.build_response_config!(unquote(status), unquote(opts), data, meta)
      )

      Module.delete_attribute(__MODULE__, :nb_json_current_context)
      Module.delete_attribute(__MODULE__, :nb_json_response_data)
      Module.delete_attribute(__MODULE__, :nb_json_response_meta)
    end
  end

  @doc """
  Declares a data field inside a response block.
  """
  defmacro data(name, type \\ :any, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      NbJson.Controller.ensure_response_context!(__MODULE__, :data)

      Module.put_attribute(
        __MODULE__,
        :nb_json_response_data,
        NbJson.Controller.build_field_config!(name, type, opts)
      )
    end
  end

  @doc """
  Declares a meta field inside a response block.
  """
  defmacro meta(name, type \\ :any, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      NbJson.Controller.ensure_response_context!(__MODULE__, :meta)

      Module.put_attribute(
        __MODULE__,
        :nb_json_response_meta,
        NbJson.Controller.build_field_config!(name, type, opts)
      )
    end
  end

  @doc """
  Declares standard pagination metadata for Flop-backed list endpoints.

      response 200 do
        data :users, list_of(ref(UserSerializer))
        flop_meta()
      end
  """
  defmacro flop_meta(name \\ :pagination, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      NbJson.Controller.ensure_response_context!(__MODULE__, :meta)

      Module.put_attribute(
        __MODULE__,
        :nb_json_response_meta,
        NbJson.Controller.build_field_config!(
          name,
          NbJson.Flop.meta_type(opts),
          Keyword.put_new(opts, :optional, true)
        )
      )
    end
  end

  @doc """
  Declares a standard error response for the current endpoint.
  """
  defmacro error(status, opts \\ []) do
    quote bind_quoted: [status: status, opts: opts] do
      Module.put_attribute(
        __MODULE__,
        :nb_json_responses,
        NbJson.Controller.build_error_config!(status, opts)
      )
    end
  end

  @doc """
  Builds an explicit serializer tuple for JSON response assigns.
  """
  @spec serialize(module(), any()) :: {module(), any()}
  @spec serialize(module(), any(), keyword()) :: {module(), any(), keyword()}
  def serialize(serializer, data, opts \\ [])
  def serialize(serializer, data, []) when is_atom(serializer), do: {serializer, data}

  def serialize(serializer, data, opts) when is_atom(serializer) and is_list(opts),
    do: {serializer, data, opts}

  @doc false
  def build_endpoint_config!(name, opts, params, responses)
      when is_atom(name) and is_list(opts) do
    method = normalize_method(Keyword.get(opts, :method, :get))
    path = Keyword.get(opts, :path)
    params = Enum.map(params, &default_param_location(&1, method, path))

    validate_field_names!(params, "params", name)
    validate_param_locations!(params, name)
    validate_path_params!(path, params, name)
    validate_responses!(responses, name)

    %{
      name: name,
      method: method,
      path: path,
      operation_id: Keyword.get(opts, :operation_id),
      summary: Keyword.get(opts, :summary),
      description: Keyword.get(opts, :description),
      tags: List.wrap(Keyword.get(opts, :tags, [])),
      deprecated: Keyword.get(opts, :deprecated, false),
      security: Keyword.get(opts, :security),
      servers: Keyword.get(opts, :servers),
      request_body_description: Keyword.get(opts, :request_body_description),
      params: params,
      responses: responses
    }
  end

  @doc false
  def build_field_config!(name, type, opts) when is_atom(name) and is_list(opts) do
    %{
      name: name,
      type: Type.validate_type!(type),
      optional: Keyword.get(opts, :optional, false),
      location: Keyword.get(opts, :location),
      description: Keyword.get(opts, :description),
      example: Keyword.get(opts, :example)
    }
    |> maybe_put(:default, Keyword.get(opts, :default), Keyword.has_key?(opts, :default))
  end

  @doc false
  def build_response_config!(status, opts, data, meta)
      when is_integer(status) and is_list(opts) do
    validate_status!(status, :response)
    validate_field_names!(data, "response #{status} data", :response)
    validate_field_names!(meta, "response #{status} meta", :response)

    profile = normalize_response_profile!(Keyword.get(opts, :profile))
    json_api = json_api_response_options!(profile, opts, data)

    %{
      kind: :success,
      status: status,
      description: Keyword.get(opts, :description),
      profile: profile,
      json_api: json_api,
      data: data,
      meta: meta
    }
  end

  @doc false
  def build_error_config!(status, opts) when is_integer(status) and is_list(opts) do
    validate_status!(status, :error)

    %{
      kind: :error,
      status: status,
      code: Keyword.get(opts, :code, NbJson.PlugStatus.reason_atom(status) || status),
      description: Keyword.get(opts, :description),
      details: Keyword.get(opts, :details, :map)
    }
  end

  defp normalize_response_profile!(nil), do: nil
  defp normalize_response_profile!(:default), do: nil
  defp normalize_response_profile!("default"), do: nil

  defp normalize_response_profile!(profile)
       when profile in [:json_api, :jsonapi, "json_api", "jsonapi"],
       do: :json_api

  defp normalize_response_profile!(profile) do
    raise ArgumentError,
          "invalid response profile #{inspect(profile)}. Use :json_api or omit :profile."
  end

  defp json_api_response_options!(nil, _opts, _data), do: []

  defp json_api_response_options!(:json_api, opts, data) do
    if length(data) != 1 do
      raise ArgumentError,
            "JSON:API response profile requires exactly one data field, got #{length(data)}"
    end

    json_api =
      opts
      |> NbJson.JsonApi.normalize_options!()
      |> Keyword.put_new(:type, data |> hd() |> Map.fetch!(:name) |> Atom.to_string())

    NbJson.JsonApi.validate_options!(json_api)
    json_api
  end

  @doc false
  def ensure_response_context!(module, macro_name) do
    unless Module.get_attribute(module, :nb_json_current_context) == :response do
      raise ArgumentError, "#{macro_name}/2 and #{macro_name}/3 must be used inside response/2"
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    endpoints = Module.get_attribute(env.module, :nb_json_endpoints) || %{}
    validate_actions? = Module.get_attribute(env.module, :nb_json_validate_actions) || false

    if validate_actions? do
      validate_controller_actions!(env.module, endpoints)
    end

    quote do
      @doc "Returns JSON endpoint contracts declared in this controller."
      def __nb_json_endpoints__, do: unquote(Macro.escape(endpoints))
    end
  end

  @doc """
  Builds a response payload for an endpoint.
  """
  @spec build_json(module(), atom(), map() | keyword(), keyword()) :: map()
  def build_json(controller, endpoint, assigns, opts \\ []) do
    Response.success(assigns, response_render_options(controller, endpoint, opts))
  end

  @doc """
  Builds and sends a JSON response.
  """
  @spec render_json(module(), Plug.Conn.t(), atom(), map() | keyword(), keyword()) ::
          Plug.Conn.t()
  def render_json(controller, conn, endpoint, assigns, opts \\ []) do
    status = Keyword.get(opts, :status) || default_success_status(controller, endpoint)
    payload = build_json(controller, endpoint, assigns, opts)

    send_json(conn, payload, status)
  end

  @doc """
  Sends a standard error response.
  """
  @spec render_error(Plug.Conn.t(), atom() | integer() | binary(), binary() | nil, keyword()) ::
          Plug.Conn.t()
  def render_error(conn, code_or_status, message \\ nil, opts \\ []) do
    status = Keyword.get(opts, :status) || status_from(code_or_status) || 500
    payload = Response.error(code_or_status, message, Keyword.put(opts, :status, status))

    send_json(conn, payload, status)
  end

  @doc """
  Sends a validation error response.
  """
  @spec render_validation_error(Plug.Conn.t(), term(), keyword()) :: Plug.Conn.t()
  def render_validation_error(conn, errors_or_changeset, opts \\ []) do
    status = Keyword.get(opts, :status, 422)
    payload = Response.validation_error(errors_or_changeset, Keyword.put(opts, :status, status))

    send_json(conn, payload, status)
  end

  defp response_render_options(controller, endpoint, opts) do
    case response_config_for_render(controller, endpoint, Keyword.get(opts, :status)) do
      %{profile: profile} = response when profile in [:json_api] ->
        apply_response_render_defaults(opts, response)

      _response ->
        opts
    end
  end

  defp response_config_for_render(controller, endpoint, status) do
    with {:ok, config} <- fetch_endpoint(controller, endpoint) do
      success_responses = Enum.filter(config.responses, &(&1.kind == :success))

      by_status =
        if is_integer(status) do
          Enum.find(success_responses, &(&1.status == status))
        end

      by_status || List.first(success_responses)
    else
      _error -> nil
    end
  end

  defp apply_response_render_defaults(opts, response) do
    profile =
      if Keyword.has_key?(opts, :profile) do
        normalize_response_profile!(Keyword.fetch!(opts, :profile))
      else
        response.profile
      end

    opts =
      if Keyword.has_key?(opts, :profile) do
        opts
      else
        Keyword.put(opts, :profile, profile)
      end

    if profile == :json_api do
      caller_json_api =
        NbJson.JsonApi.normalize_options!(json_api: Keyword.get(opts, :json_api, []))

      json_api = Keyword.merge(response.json_api || [], caller_json_api)

      Keyword.put(opts, :json_api, json_api)
    else
      opts
    end
  end

  @doc """
  Validates params for a declared endpoint.
  """
  @spec validate_json_params(module(), atom(), map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def validate_json_params(controller, endpoint, params, opts \\ []) do
    with {:ok, endpoint_config} <- fetch_endpoint(controller, endpoint) do
      NbJson.Validation.validate(endpoint_config, params, opts)
    end
  end

  @doc """
  Validates params for a declared endpoint and raises on failure.
  """
  @spec validate_json_params!(module(), atom(), map() | keyword(), keyword()) :: map()
  def validate_json_params!(controller, endpoint, params, opts \\ []) do
    case validate_json_params(controller, endpoint, params, opts) do
      {:ok, params} ->
        params

      {:error, errors} ->
        raise ArgumentError, "invalid JSON params for #{inspect(endpoint)}: #{inspect(errors)}"
    end
  end

  defp send_json(conn, payload, status) do
    cond do
      Code.ensure_loaded?(Phoenix.Controller) and function_exported?(Phoenix.Controller, :json, 2) ->
        conn
        |> maybe_put_status(status)
        |> then(&apply(Phoenix.Controller, :json, [&1, payload]))

      Code.ensure_loaded?(Plug.Conn) ->
        conn =
          conn
          |> apply_plug(:put_resp_content_type, ["application/json"])
          |> apply_plug(:send_resp, [status, Jason.encode!(payload)])

        conn

      true ->
        raise ArgumentError,
              "render_json/4 requires Phoenix.Controller or Plug.Conn to be available"
    end
  end

  defp maybe_put_status(conn, nil), do: conn

  defp maybe_put_status(conn, status) do
    if Code.ensure_loaded?(Plug.Conn) do
      apply(Plug.Conn, :put_status, [conn, status])
    else
      conn
    end
  end

  defp apply_plug(conn, function, args) do
    apply(Plug.Conn, function, [conn | args])
  end

  defp default_success_status(controller, endpoint) do
    with {:ok, config} <- fetch_endpoint(controller, endpoint),
         %{status: status} <- Enum.find(config.responses, &(&1.kind == :success)) do
      status
    else
      _ -> 200
    end
  end

  defp fetch_endpoint(controller, endpoint) do
    if function_exported?(controller, :__nb_json_endpoints__, 0) do
      case controller.__nb_json_endpoints__() do
        %{^endpoint => config} -> {:ok, config}
        _endpoints -> {:error, %{endpoint: ["is not declared"]}}
      end
    else
      {:error, %{controller: ["does not declare JSON endpoints"]}}
    end
  end

  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _value, false), do: map

  defp normalize_method(method) when is_atom(method),
    do: method |> Atom.to_string() |> String.downcase()

  defp normalize_method(method) when is_binary(method), do: String.downcase(method)

  defp default_param_location(%{location: nil} = field, method, path) do
    location =
      cond do
        path_param?(path, field.name) -> :path
        method in ["post", "put", "patch"] -> :body
        true -> :query
      end

    %{field | location: location}
  end

  defp default_param_location(field, _method, _path), do: field

  defp path_param?(path, name) when is_binary(path) do
    name = Atom.to_string(name)
    String.contains?(path, ":#{name}") or String.contains?(path, "{#{name}}")
  end

  defp path_param?(_path, _name), do: false

  defp status_from(status) when is_integer(status), do: status
  defp status_from(:validation_failed), do: 422
  defp status_from(:not_found), do: 404
  defp status_from(:unauthorized), do: 401
  defp status_from(:forbidden), do: 403
  defp status_from(_), do: nil

  defp validate_field_names!(fields, context, endpoint) do
    duplicates =
      fields
      |> Enum.map(& &1.name)
      |> duplicates()

    if duplicates != [] do
      raise ArgumentError,
            "duplicate #{context} field(s) #{format_duplicates(duplicates)} " <>
              "in json_endpoint #{inspect(endpoint)}"
    end
  end

  defp validate_param_locations!(params, endpoint) do
    invalid =
      params
      |> Enum.filter(&(&1.location not in [:query, :body, :path]))
      |> Enum.map(&{&1.name, &1.location})

    if invalid != [] do
      raise ArgumentError,
            "invalid param location(s) in json_endpoint #{inspect(endpoint)}: " <>
              Enum.map_join(invalid, ", ", fn {name, location} ->
                "#{inspect(name)} has #{inspect(location)}"
              end) <> ". Use :query, :body, or :path."
    end
  end

  defp validate_path_params!(nil, params, endpoint) do
    case Enum.filter(params, &(&1.location == :path)) do
      [] ->
        :ok

      fields ->
        raise ArgumentError,
              "json_endpoint #{inspect(endpoint)} declares path param field(s) " <>
                "#{format_duplicates(Enum.map(fields, & &1.name))} but has no :path option"
    end
  end

  defp validate_path_params!(path, params, endpoint) when is_binary(path) do
    placeholders = path_param_names(path)

    path_fields =
      params
      |> Enum.filter(&(&1.location == :path))
      |> Enum.map(& &1.name)

    missing_fields =
      placeholders
      |> Enum.reject(&(&1 in path_fields))

    extra_fields =
      path_fields
      |> Enum.reject(&(&1 in placeholders))

    cond do
      missing_fields != [] ->
        raise ArgumentError,
              "json_endpoint #{inspect(endpoint)} path #{inspect(path)} has placeholder(s) " <>
                "#{format_duplicates(missing_fields)} without matching path param field(s)"

      extra_fields != [] ->
        raise ArgumentError,
              "json_endpoint #{inspect(endpoint)} declares path param field(s) " <>
                "#{format_duplicates(extra_fields)} that do not appear in path #{inspect(path)}"

      true ->
        :ok
    end
  end

  defp validate_responses!(responses, endpoint) do
    if responses == [] do
      raise ArgumentError, "json_endpoint #{inspect(endpoint)} must declare at least one response"
    end

    unless Enum.any?(responses, &(&1.kind == :success)) do
      raise ArgumentError,
            "json_endpoint #{inspect(endpoint)} must declare at least one success response"
    end

    duplicate_statuses =
      responses
      |> Enum.map(& &1.status)
      |> duplicates()

    if duplicate_statuses != [] do
      raise ArgumentError,
            "duplicate response status(es) #{format_duplicates(duplicate_statuses)} " <>
              "in json_endpoint #{inspect(endpoint)}"
    end
  end

  defp validate_status!(status, context) do
    unless status in 100..599 do
      raise ArgumentError,
            "invalid #{context} status #{inspect(status)}. Use an HTTP status code from 100 to 599."
    end
  end

  defp validate_controller_actions!(module, endpoints) do
    missing =
      endpoints
      |> Map.keys()
      |> Enum.reject(&Module.defines?(module, {&1, 2}, :def))

    if missing != [] do
      raise ArgumentError,
            "#{inspect(module)} declares json_endpoint action(s) #{format_duplicates(missing)} " <>
              "but does not define matching controller action function(s) with arity 2"
    end
  end

  defp path_param_names(path) do
    ~r/:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\}/
    |> Regex.scan(path, capture: :all_but_first)
    |> Enum.map(fn captures ->
      captures
      |> Enum.find(&(&1 != ""))
      |> String.to_atom()
    end)
    |> Enum.uniq()
  end

  defp duplicates(values) do
    values
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.map(fn {value, _count} -> value end)
    |> Enum.sort()
  end

  defp format_duplicates(values) do
    values
    |> Enum.map_join(", ", &inspect/1)
  end
end

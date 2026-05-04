defmodule NbJson.Auth do
  @moduledoc """
  Authentication contract helpers and adapter behaviour for `nb_json`.

  `nb_json` does not own users, sessions, token storage, or password flows.
  Applications provide an auth adapter and `nb_json` calls it from plugs using
  endpoint metadata declared in the controller DSL.
  """

  @type auth_contract :: %{
          scheme: atom(),
          scopes: [String.t()],
          optional: boolean(),
          security_scheme: atom() | String.t(),
          open_api: map() | nil
        }

  @callback authenticate(Plug.Conn.t(), auth_contract(), keyword()) ::
              {:ok, subject :: term()}
              | {:ok, subject :: term(), claims :: map()}
              | {:error, reason :: atom() | map() | keyword()}

  @doc false
  @spec normalize!(nil | false | atom() | binary() | keyword() | map()) :: auth_contract() | nil
  def normalize!(nil), do: nil
  def normalize!(false), do: nil
  def normalize!(true), do: normalize!(:bearer)
  def normalize!(scheme) when is_atom(scheme) or is_binary(scheme), do: normalize!(scheme: scheme)

  def normalize!(%{} = opts), do: opts |> Map.to_list() |> normalize!()

  def normalize!(opts) when is_list(opts) do
    scheme = opts |> Keyword.get(:scheme, :bearer) |> normalize_scheme!()
    security_scheme = Keyword.get(opts, :security_scheme, default_security_scheme(scheme))

    %{
      scheme: scheme,
      scopes: normalize_scopes(Keyword.get(opts, :scopes, Keyword.get(opts, :scope, []))),
      optional: Keyword.get(opts, :optional, false),
      security_scheme: normalize_security_scheme_name!(security_scheme),
      open_api: normalize_open_api_scheme(scheme, opts),
      realm: Keyword.get(opts, :realm),
      name: Keyword.get(opts, :name),
      location: Keyword.get(opts, :in) || Keyword.get(opts, :location),
      description: Keyword.get(opts, :description)
    }
    |> drop_nil_values()
  end

  def normalize!(auth) do
    raise ArgumentError,
          "invalid auth contract #{inspect(auth)}. Use :bearer, false, nil, or keyword options."
  end

  @doc false
  def open_api_security(nil), do: nil

  def open_api_security(%{optional: true} = auth) do
    [%{}, %{auth.security_scheme => auth.scopes}]
  end

  def open_api_security(%{} = auth), do: [%{auth.security_scheme => auth.scopes}]

  @doc false
  def open_api_security_scheme(nil), do: nil
  def open_api_security_scheme(%{open_api: nil}), do: nil

  def open_api_security_scheme(%{security_scheme: name, open_api: open_api}) do
    {name, open_api}
  end

  @doc false
  def missing_reason?(reason) when reason in [:missing, :missing_credentials, :not_present],
    do: true

  def missing_reason?(%{reason: reason}), do: missing_reason?(reason)
  def missing_reason?(_reason), do: false

  @doc false
  def error_code(:missing), do: :missing_credentials
  def error_code(:missing_credentials), do: :missing_credentials
  def error_code(:not_present), do: :missing_credentials
  def error_code(:invalid), do: :invalid_credentials
  def error_code(:expired), do: :expired_credentials
  def error_code(reason) when is_atom(reason), do: reason
  def error_code(%{code: code}) when is_atom(code) or is_binary(code), do: code
  def error_code(_reason), do: :unauthorized

  @doc false
  def error_message(:missing), do: "Authentication required"
  def error_message(:missing_credentials), do: "Authentication required"
  def error_message(:not_present), do: "Authentication required"
  def error_message(:invalid), do: "Invalid credentials"
  def error_message(:invalid_credentials), do: "Invalid credentials"
  def error_message(:expired), do: "Credentials expired"
  def error_message(:expired_credentials), do: "Credentials expired"
  def error_message(%{message: message}) when is_binary(message), do: message
  def error_message(_reason), do: "Authentication failed"

  @doc false
  def authenticate(adapter, conn, auth, opts) when is_atom(adapter) do
    unless Code.ensure_loaded?(adapter) and function_exported?(adapter, :authenticate, 3) do
      raise ArgumentError,
            "auth adapter #{inspect(adapter)} must implement authenticate(conn, auth, opts)"
    end

    apply(adapter, :authenticate, [conn, auth, opts])
  end

  def authenticate(adapter, _conn, _auth, _opts) do
    raise ArgumentError,
          "auth adapter must be a module implementing NbJson.Auth, got: #{inspect(adapter)}"
  end

  defp normalize_scheme!(nil) do
    raise ArgumentError, "auth :scheme is required"
  end

  defp normalize_scheme!(scheme) when is_atom(scheme), do: scheme

  defp normalize_scheme!(scheme) when is_binary(scheme),
    do: scheme |> scheme_key() |> known_scheme!()

  defp normalize_scheme!(scheme) do
    raise ArgumentError, "auth :scheme must be an atom or string, got: #{inspect(scheme)}"
  end

  defp normalize_security_scheme_name!(name) when is_atom(name), do: name

  defp normalize_security_scheme_name!(name) when is_binary(name) do
    case String.trim(name) do
      "" -> raise ArgumentError, "auth :security_scheme cannot be blank"
      trimmed -> trimmed
    end
  end

  defp normalize_security_scheme_name!(name) do
    raise ArgumentError,
          "auth :security_scheme must be an atom or string, got: #{inspect(name)}"
  end

  defp default_security_scheme(:bearer), do: :bearerAuth
  defp default_security_scheme(:basic), do: :basicAuth
  defp default_security_scheme(:api_key), do: :apiKeyAuth
  defp default_security_scheme(:cookie), do: :cookieAuth
  defp default_security_scheme(scheme), do: scheme

  defp normalize_scopes(nil), do: []
  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
  defp normalize_scopes(scope), do: [to_string(scope)]

  defp normalize_open_api_scheme(scheme, opts) do
    case Keyword.fetch(opts, :open_api) do
      {:ok, nil} -> nil
      {:ok, open_api} -> stringify_open_api(open_api)
      :error -> default_open_api_scheme(scheme, opts)
    end
  end

  defp default_open_api_scheme(scheme, opts) when is_binary(scheme) do
    scheme
    |> normalize_scheme!()
    |> default_open_api_scheme(opts)
  end

  defp default_open_api_scheme(:bearer, opts) do
    %{"type" => "http", "scheme" => "bearer"}
    |> maybe_put("bearerFormat", Keyword.get(opts, :bearer_format))
    |> maybe_put("description", Keyword.get(opts, :description))
  end

  defp default_open_api_scheme(:basic, opts) do
    %{"type" => "http", "scheme" => "basic"}
    |> maybe_put("description", Keyword.get(opts, :description))
  end

  defp default_open_api_scheme(:api_key, opts) do
    %{
      "type" => "apiKey",
      "name" => Keyword.get(opts, :name, "x-api-key"),
      "in" => opts |> Keyword.get(:in, Keyword.get(opts, :location, "header")) |> to_string()
    }
    |> maybe_put("description", Keyword.get(opts, :description))
  end

  defp default_open_api_scheme(:cookie, opts) do
    %{
      "type" => "apiKey",
      "name" => Keyword.get(opts, :name, "_session"),
      "in" => "cookie"
    }
    |> maybe_put("description", Keyword.get(opts, :description))
  end

  defp default_open_api_scheme(scheme, _opts) do
    raise ArgumentError,
          "auth :open_api is required for custom auth scheme #{inspect(scheme)}. " <>
            "Pass an OpenAPI security scheme map, or pass open_api: nil and configure " <>
            ":security_schemes when generating OpenAPI."
  end

  defp scheme_key(scheme) do
    scheme
    |> String.trim()
    |> String.replace("-", "_")
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  defp known_scheme!("bearer"), do: :bearer
  defp known_scheme!("basic"), do: :basic
  defp known_scheme!("api_key"), do: :api_key
  defp known_scheme!("cookie"), do: :cookie

  defp known_scheme!(scheme) do
    raise ArgumentError,
          "auth :scheme string must be one of bearer, basic, api_key, or cookie. " <>
            "Use an atom for custom schemes, got: #{inspect(scheme)}"
  end

  defp stringify_open_api(%_struct{} = open_api),
    do: open_api |> Map.from_struct() |> stringify_open_api()

  defp stringify_open_api(%{} = open_api) do
    Map.new(open_api, fn {key, value} -> {open_api_key(key), stringify_open_api_value(value)} end)
  end

  defp stringify_open_api(open_api), do: open_api

  defp stringify_open_api_value(%_struct{} = value),
    do: value |> Map.from_struct() |> stringify_open_api_value()

  defp stringify_open_api_value(%{} = value),
    do:
      Map.new(value, fn {key, nested} -> {open_api_key(key), stringify_open_api_value(nested)} end)

  defp stringify_open_api_value(values) when is_list(values),
    do: Enum.map(values, &stringify_open_api_value/1)

  defp stringify_open_api_value(value), do: value

  defp open_api_key(:bearer_format), do: "bearerFormat"
  defp open_api_key(:open_id_connect_url), do: "openIdConnectUrl"
  defp open_api_key(key), do: to_string(key)

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

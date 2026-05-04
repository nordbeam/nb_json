defmodule NbJson.Authorization do
  @moduledoc """
  Authorization adapter behaviour for `nb_json`.

  Authentication answers "who is calling?". Authorization answers "may that
  subject perform this declared action?". Applications own the policy logic and
  `nb_json` invokes it with endpoint `authorize/1` requirements.
  """

  @type requirement :: map()

  @callback authorize(subject :: term(), requirement(), Plug.Conn.t(), keyword()) ::
              :ok | true | {:error, reason :: atom() | map() | keyword()} | false

  @doc false
  def normalize_requirement!(%{} = opts), do: Map.new(opts)

  def normalize_requirement!(opts) when is_list(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "authorize/1 expects a keyword list or map"
    end

    Map.new(opts)
  end

  def normalize_requirement!(opts) do
    raise ArgumentError, "authorize/1 expects a keyword list or map, got: #{inspect(opts)}"
  end

  @doc false
  def authorize(adapter, subject, requirement, conn, opts) when is_atom(adapter) do
    unless Code.ensure_loaded?(adapter) and function_exported?(adapter, :authorize, 4) do
      raise ArgumentError,
            "authorization adapter #{inspect(adapter)} must implement " <>
              "authorize(subject, requirement, conn, opts)"
    end

    apply(adapter, :authorize, [subject, requirement, conn, opts])
  end

  def authorize(adapter, _subject, _requirement, _conn, _opts) do
    raise ArgumentError,
          "authorization adapter must be a module implementing NbJson.Authorization, got: " <>
            inspect(adapter)
  end

  @doc false
  def error_code(:forbidden), do: :forbidden
  def error_code(:unauthorized), do: :unauthorized
  def error_code(reason) when is_atom(reason), do: reason
  def error_code(%{code: code}) when is_atom(code) or is_binary(code), do: code
  def error_code(false), do: :forbidden
  def error_code(_reason), do: :forbidden

  @doc false
  def error_message(:forbidden), do: "Forbidden"
  def error_message(:unauthorized), do: "Authentication required"
  def error_message(%{message: message}) when is_binary(message), do: message
  def error_message(false), do: "Forbidden"
  def error_message(_reason), do: "Forbidden"
end

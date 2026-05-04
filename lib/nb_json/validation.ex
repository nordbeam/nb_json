defmodule NbJson.Validation do
  @moduledoc """
  Runtime validation and coercion for `NbJson.Controller` parameter contracts.

  Validation is intentionally small and explicit. It accepts normal Phoenix
  params maps with string keys, returns atom-keyed validated params, and reports
  field-level errors that can be passed directly to `NbJson.Response.validation_error/2`.
  """

  @type endpoint :: map()
  @type params :: map() | keyword()
  @type errors :: %{optional(atom()) => [binary()]}

  @decimal Module.concat(["Decimal"])

  @doc """
  Validates params for an endpoint contract.

      {:ok, params} = NbJson.Validation.validate(endpoint, %{"page" => "2"})
      {:error, errors} = NbJson.Validation.validate(endpoint, %{})
  """
  @spec validate(endpoint(), params(), keyword()) :: {:ok, map()} | {:error, errors()}
  def validate(endpoint, params, opts \\ [])

  def validate(%{params: fields}, params, opts) when is_list(fields) do
    params = normalize_params(params)

    {validated, errors} =
      Enum.reduce(fields, {%{}, %{}}, fn field, {validated, errors} ->
        case validate_field(field, params, opts) do
          {:ok, :missing} ->
            {validated, errors}

          {:ok, value} ->
            {Map.put(validated, field.name, value), errors}

          {:error, messages} ->
            {validated, Map.put(errors, field.name, normalize_error(messages))}
        end
      end)

    if errors == %{}, do: {:ok, validated}, else: {:error, errors}
  end

  def validate(_endpoint, _params, _opts), do: {:error, %{params: ["has no contract"]}}

  defp normalize_error(%{} = messages), do: messages
  defp normalize_error(messages), do: List.wrap(messages)

  @doc """
  Validates params and raises on failure.
  """
  @spec validate!(endpoint(), params(), keyword()) :: map()
  def validate!(endpoint, params, opts \\ []) do
    case validate(endpoint, params, opts) do
      {:ok, params} -> params
      {:error, errors} -> raise ArgumentError, "invalid JSON params: #{inspect(errors)}"
    end
  end

  defp validate_field(field, params, _opts) do
    case fetch_param(params, field.name) do
      {:ok, value} when value in [nil, ""] ->
        handle_blank(field)

      {:ok, value} ->
        coerce(value, field.type)

      :error ->
        cond do
          Map.has_key?(field, :default) -> {:ok, field.default}
          field.optional -> {:ok, :missing}
          true -> {:error, "is required"}
        end
    end
  end

  defp handle_blank(%{type: {:nullable, _inner}}), do: {:ok, nil}
  defp handle_blank(%{optional: true}), do: {:ok, :missing}
  defp handle_blank(_field), do: {:error, "is required"}

  defp coerce(value, :any), do: {:ok, value}
  defp coerce(value, :string) when is_binary(value), do: {:ok, value}
  defp coerce(value, :string), do: {:ok, to_string(value)}

  defp coerce(value, :integer) when is_integer(value), do: {:ok, value}

  defp coerce(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, "must be an integer"}
    end
  end

  defp coerce(_value, :integer), do: {:error, "must be an integer"}

  defp coerce(value, type) when type in [:float, :number] and is_number(value), do: {:ok, value}

  defp coerce(value, type) when type in [:float, :number] and is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "must be a number"}
    end
  end

  defp coerce(_value, type) when type in [:float, :number], do: {:error, "must be a number"}

  defp coerce(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp coerce(value, :boolean) when value in ["true", "1", "yes", "on"], do: {:ok, true}
  defp coerce(value, :boolean) when value in ["false", "0", "no", "off"], do: {:ok, false}
  defp coerce(_value, :boolean), do: {:error, "must be a boolean"}

  defp coerce(value, :uuid) when is_binary(value) do
    if Regex.match?(
         ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
         value
       ) do
      {:ok, value}
    else
      {:error, "must be a UUID"}
    end
  end

  defp coerce(_value, :uuid), do: {:error, "must be a UUID"}

  defp coerce(value, :date) when is_struct(value, Date), do: {:ok, value}

  defp coerce(value, :date) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "must be an ISO8601 date"}
    end
  end

  defp coerce(_value, :date), do: {:error, "must be an ISO8601 date"}

  defp coerce(value, :datetime) when is_struct(value, DateTime), do: {:ok, value}

  defp coerce(value, :datetime) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> {:error, "must be an ISO8601 datetime"}
    end
  end

  defp coerce(_value, :datetime), do: {:error, "must be an ISO8601 datetime"}

  defp coerce(value, :decimal) do
    decimal = @decimal

    cond do
      Code.ensure_loaded?(decimal) and is_struct(value, decimal) ->
        {:ok, value}

      Code.ensure_loaded?(decimal) and
          (is_binary(value) or is_integer(value) or is_float(value)) ->
        {:ok, apply(decimal, :new, [to_string(value)])}

      is_binary(value) or is_integer(value) or is_float(value) ->
        {:ok, value}

      true ->
        {:error, "must be a decimal"}
    end
  rescue
    _error -> {:error, "must be a decimal"}
  end

  defp coerce(value, :map) when is_map(value), do: {:ok, value}
  defp coerce(_value, :map), do: {:error, "must be an object"}

  defp coerce(value, :list) when is_list(value), do: {:ok, value}
  defp coerce(_value, :list), do: {:error, "must be a list"}

  defp coerce(value, {:nullable, _inner}) when value in [nil, ""], do: {:ok, nil}
  defp coerce(value, {:nullable, inner}), do: coerce(value, inner)
  defp coerce(value, {:optional, inner}), do: coerce(value, inner)

  defp coerce(value, {:list, inner}) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case coerce(item, inner) do
        {:ok, coerced} -> {:cont, {:ok, [coerced | acc]}}
        {:error, message} -> {:halt, {:error, "item #{index} #{message}"}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, message} -> {:error, message}
    end
  end

  defp coerce(_value, {:list, _inner}), do: {:error, "must be a list"}

  defp coerce(value, {:enum, allowed}) do
    allowed
    |> Enum.find_value(fn allowed_value ->
      if enum_match?(value, allowed_value), do: {:ok, allowed_value}
    end)
    |> case do
      {:ok, allowed_value} -> {:ok, allowed_value}
      nil -> {:error, "must be one of: #{Enum.map_join(allowed, ", ", &to_string/1)}"}
    end
  end

  defp coerce(value, {:literal, literal}) do
    if enum_match?(value, literal),
      do: {:ok, literal},
      else: {:error, "must be #{inspect(literal)}"}
  end

  defp coerce(value, {:shape, fields}) when is_map(value) do
    endpoint = %{params: Enum.map(fields, fn {name, type} -> shape_field(name, type) end)}
    validate(endpoint, value)
  end

  defp coerce(_value, {:shape, _fields}), do: {:error, "must be an object"}

  defp coerce(value, {:union, types}) do
    Enum.reduce_while(types, {:error, "does not match any allowed type"}, fn type, _acc ->
      case coerce(value, type) do
        {:ok, coerced} -> {:halt, {:ok, coerced}}
        {:error, _message} -> {:cont, {:error, "does not match any allowed type"}}
      end
    end)
  end

  defp coerce(value, {:ref, _module}) when is_map(value), do: {:ok, value}
  defp coerce(_value, {:ref, _module}), do: {:error, "must be an object"}
  defp coerce(value, _type), do: {:ok, value}

  defp shape_field(name, {:optional, inner}) do
    %{name: name, type: inner, optional: true, location: :body}
  end

  defp shape_field(name, type) do
    %{name: name, type: type, optional: false, location: :body}
  end

  defp enum_match?(value, allowed) when is_atom(allowed),
    do: to_string(allowed) == to_string(value)

  defp enum_match?(value, allowed), do: value == allowed or to_string(value) == to_string(allowed)

  defp fetch_param(params, name) do
    cond do
      Map.has_key?(params, name) ->
        {:ok, Map.fetch!(params, name)}

      Map.has_key?(params, Atom.to_string(name)) ->
        {:ok, Map.fetch!(params, Atom.to_string(name))}

      true ->
        :error
    end
  end

  defp normalize_params(params) when is_list(params), do: Map.new(params)
  defp normalize_params(params) when is_map(params), do: params

  defp normalize_params(params) do
    raise ArgumentError, "params must be a map or keyword list, got: #{inspect(params)}"
  end
end

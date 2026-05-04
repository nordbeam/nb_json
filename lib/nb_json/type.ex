defmodule NbJson.Type do
  @moduledoc """
  Elixir-native type helpers for JSON API contracts.

  The helpers return plain tuples so endpoint metadata stays inspectable at
  compile time and easy to consume from OpenAPI or TypeScript generators.
  """

  @primitive_types [
    :string,
    :integer,
    :float,
    :number,
    :boolean,
    :map,
    :list,
    :any,
    :date,
    :datetime,
    :uuid,
    :decimal
  ]

  @native_type_tags [:ref, :list, :enum, :literal, :union, :nullable, :optional, :shape]

  defmacro ref(module) do
    expanded_module = Macro.expand(module, __CALLER__)

    quote do
      {:ref, unquote(expanded_module)}
    end
  end

  defmacro list_of(inner) do
    quote do
      {:list, unquote(inner)}
    end
  end

  defmacro enum(values) do
    quote do
      {:enum, unquote(values)}
    end
  end

  defmacro literal(value) do
    quote do
      {:literal, unquote(value)}
    end
  end

  defmacro union(types) do
    quote do
      {:union, unquote(types)}
    end
  end

  defmacro nullable(inner) do
    quote do
      {:nullable, unquote(inner)}
    end
  end

  defmacro optional(inner) do
    quote do
      {:optional, unquote(inner)}
    end
  end

  defmacro shape(fields) do
    quote do
      {:shape, unquote(fields)}
    end
  end

  @doc false
  def primitive_types, do: @primitive_types

  @doc false
  def primitive_type?(type), do: type in @primitive_types

  @doc false
  def native_type_descriptor?({tag, _value}) when tag in @native_type_tags, do: true
  def native_type_descriptor?(_value), do: false

  @doc false
  def validated_typescript_type?({:typescript_validated, ts_string}) when is_binary(ts_string),
    do: true

  def validated_typescript_type?(_value), do: false

  @doc false
  def normalize_type!(:any), do: :any

  def normalize_type!(type) when is_atom(type) do
    cond do
      primitive_type?(type) -> type
      module_atom?(type) -> {:ref, type}
      true -> type
    end
  end

  def normalize_type!({:ref, module}) when is_atom(module), do: {:ref, module}

  def normalize_type!({:list, inner}) do
    {:list, normalize_type!(inner)}
  end

  def normalize_type!({:enum, values}) when is_list(values), do: {:enum, values}
  def normalize_type!({:literal, value}), do: {:literal, value}

  def normalize_type!({:union, types}) when is_list(types) do
    {:union, Enum.map(types, &normalize_type!/1)}
  end

  def normalize_type!({:nullable, inner}), do: {:nullable, normalize_type!(inner)}
  def normalize_type!({:optional, inner}), do: {:optional, normalize_type!(inner)}

  def normalize_type!({:shape, fields}) when is_list(fields) do
    validate_unique_shape_fields!(fields)

    {:shape, Enum.map(fields, fn {name, type} -> {name, normalize_type!(type)} end)}
  end

  def normalize_type!({:typescript_validated, ts_string} = type) when is_binary(ts_string),
    do: type

  def normalize_type!(type) when is_binary(type), do: type

  def normalize_type!(type) do
    raise ArgumentError,
          "unsupported JSON contract type: #{inspect(type)}. " <>
            "Use a primitive atom, ref(Module), list_of/1, enum/1, shape/1, union/1, " <>
            "nullable/1, optional/1, literal/1, or a validated TypeScript type."
  end

  @doc false
  def validate_type!(type) do
    type = normalize_type!(type)
    do_validate_type!(type)
    type
  end

  defp do_validate_type!(type) when type in @primitive_types, do: :ok
  defp do_validate_type!({:ref, module}) when is_atom(module), do: :ok
  defp do_validate_type!({:enum, values}) when is_list(values), do: :ok
  defp do_validate_type!({:literal, _value}), do: :ok
  defp do_validate_type!({:typescript_validated, ts_string}) when is_binary(ts_string), do: :ok
  defp do_validate_type!(type) when is_binary(type), do: :ok

  defp do_validate_type!({:list, inner}), do: do_validate_type!(inner)
  defp do_validate_type!({:nullable, inner}), do: do_validate_type!(inner)
  defp do_validate_type!({:optional, inner}), do: do_validate_type!(inner)

  defp do_validate_type!({:union, types}) when is_list(types),
    do: Enum.each(types, &do_validate_type!/1)

  defp do_validate_type!({:shape, fields}) when is_list(fields) do
    Enum.each(fields, fn
      {name, type} when is_atom(name) -> do_validate_type!(type)
      other -> raise ArgumentError, "invalid shape field: #{inspect(other)}"
    end)
  end

  defp do_validate_type!(type),
    do: raise(ArgumentError, "invalid JSON contract type: #{inspect(type)}")

  defp module_atom?(atom) do
    atom
    |> Atom.to_string()
    |> String.contains?(".")
  end

  defp validate_unique_shape_fields!(fields) do
    duplicates =
      fields
      |> Enum.map(fn
        {name, _type} -> name
        other -> other
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)
      |> Enum.sort()

    if duplicates != [] do
      raise ArgumentError,
            "duplicate shape field(s): #{Enum.map_join(duplicates, ", ", &inspect/1)}"
    end
  end
end

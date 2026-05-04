defmodule NbJson.Serializer do
  @moduledoc false

  def materialize(value, opts \\ [])

  def materialize({serializer, data}, opts) when is_atom(serializer) do
    materialize({serializer, data, []}, opts)
  end

  def materialize({serializer, data, serializer_opts}, _opts)
      when is_atom(serializer) and is_list(serializer_opts) do
    cond do
      Code.ensure_loaded?(serializer) and function_exported?(serializer, :serialize, 2) ->
        serialize_with_module(serializer, data, serializer_opts)

      Code.ensure_loaded?(NbSerializer) and function_exported?(NbSerializer, :serialize, 3) ->
        case apply(NbSerializer, :serialize, [serializer, data, serializer_opts]) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise ArgumentError, "failed to serialize JSON response: #{inspect(reason)}"

          result ->
            result
        end

      true ->
        data
    end
  end

  def materialize(value, opts) when is_list(value) do
    Enum.map(value, &materialize(&1, opts))
  end

  def materialize(%{} = value, opts) do
    if struct?(value) do
      value
    else
      Map.new(value, fn {key, nested} -> {key, materialize(nested, opts)} end)
    end
  end

  def materialize(value, _opts), do: value

  defp serialize_with_module(serializer, data, opts) when is_list(data) do
    Enum.map(data, &serialize_with_module(serializer, &1, opts))
  end

  defp serialize_with_module(serializer, data, opts) do
    apply(serializer, :serialize, [data, opts])
  end

  defp struct?(%{__struct__: _}), do: true
  defp struct?(_value), do: false
end

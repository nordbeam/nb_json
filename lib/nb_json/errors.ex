defmodule NbJson.Errors do
  @moduledoc """
  Error normalization helpers for JSON API responses.
  """

  @doc """
  Converts Ecto changesets, plain maps, or keyword lists into validation details.
  """
  @spec to_details(term()) :: term()
  def to_details(%{errors: _errors} = changeset) do
    if Code.ensure_loaded?(Ecto.Changeset) and
         function_exported?(Ecto.Changeset, :traverse_errors, 2) do
      apply(Ecto.Changeset, :traverse_errors, [changeset, &translate_error/1])
    else
      Map.get(changeset, :errors, %{})
    end
  end

  def to_details(errors) when is_list(errors), do: Map.new(errors)
  def to_details(%{} = errors), do: errors
  def to_details(errors), do: errors

  @doc """
  Interpolates an Ecto changeset error tuple.
  """
  @spec translate_error({binary(), keyword()} | binary()) :: binary()
  def translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  def translate_error(msg) when is_binary(msg), do: msg
end

defmodule NbJson.Response do
  @moduledoc """
  Response envelope helpers for JSON APIs.

  The default success shape is:

      %{
        data: %{...},
        meta: %{...},
        links: %{...}
      }

  `:meta`, `:links`, and `:included` assigns are lifted to top-level envelope
  keys; all remaining assigns are nested under `:data`.
  """

  alias NbJson.Serializer

  @type assigns :: map() | keyword()
  @type payload :: map()

  @doc """
  Builds a success payload.
  """
  @spec success(assigns(), keyword()) :: payload()
  def success(assigns, opts \\ []) do
    assigns = normalize_assigns(assigns)
    envelope? = Keyword.get(opts, :envelope, true)
    assigns = Serializer.materialize(assigns, opts)

    if envelope? do
      {meta, assigns} = Map.pop(assigns, :meta)
      {links, assigns} = Map.pop(assigns, :links)
      {included, data} = Map.pop(assigns, :included)

      %{data: data}
      |> maybe_put(:meta, meta)
      |> maybe_put(:links, links)
      |> maybe_put(:included, included)
    else
      assigns
    end
  end

  @doc """
  Builds a standard error payload.
  """
  @spec error(atom() | integer() | binary(), binary() | nil, keyword()) :: payload()
  def error(code_or_status, message \\ nil, opts \\ []) do
    status = Keyword.get(opts, :status, status_from(code_or_status))
    code = Keyword.get(opts, :code, code_from(code_or_status))
    details = Keyword.get(opts, :details)

    error =
      %{
        code: to_string(code),
        message: message || default_message(status, code)
      }
      |> maybe_put(:status, status)
      |> maybe_put(:details, details)

    %{error: error}
  end

  @doc """
  Builds a validation error payload from an Ecto changeset or plain error map.
  """
  @spec validation_error(term(), keyword()) :: payload()
  def validation_error(errors_or_changeset, opts \\ []) do
    details = NbJson.Errors.to_details(errors_or_changeset)

    error(:validation_failed, Keyword.get(opts, :message, "Validation failed"),
      status: Keyword.get(opts, :status, 422),
      details: details
    )
  end

  defp normalize_assigns(assigns) when is_list(assigns), do: Map.new(assigns)
  defp normalize_assigns(assigns) when is_map(assigns), do: assigns

  defp normalize_assigns(assigns) do
    raise ArgumentError,
          "JSON response assigns must be a map or keyword list, got: #{inspect(assigns)}"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp status_from(status) when is_integer(status), do: status
  defp status_from(:not_found), do: 404
  defp status_from(:unauthorized), do: 401
  defp status_from(:forbidden), do: 403
  defp status_from(:validation_failed), do: 422
  defp status_from(:conflict), do: 409
  defp status_from(:rate_limited), do: 429
  defp status_from(_code), do: nil

  defp code_from(status) when is_integer(status),
    do: NbJson.PlugStatus.reason_atom(status) || status

  defp code_from(code), do: code

  defp default_message(status, code) when is_integer(status) do
    NbJson.PlugStatus.reason_phrase(status) || humanize_code(code)
  end

  defp default_message(_status, code), do: humanize_code(code)

  defp humanize_code(code) do
    code
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end

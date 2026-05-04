defmodule NbJson.Flop do
  @moduledoc """
  Contract helpers for Flop-style pagination, sorting, and filtering params.

  This module intentionally emits plain `nb_json` type descriptors so it works
  whether or not the `nb_flop` package is installed. Apps that use `nb_flop`
  can pass the validated params directly into their Flop query layer.
  """

  @directions [
    :asc,
    :desc,
    :asc_nulls_first,
    :asc_nulls_last,
    :desc_nulls_first,
    :desc_nulls_last
  ]

  @doc false
  def param_specs(opts \\ []) do
    pagination = Keyword.get(opts, :pagination, :page)
    sorting? = Keyword.get(opts, :sorting, true)
    filters? = Keyword.get(opts, :filters, true)

    []
    |> add_pagination_specs(pagination)
    |> maybe_add(sorting?, sorting_specs())
    |> maybe_add(filters?, filter_specs())
    |> Enum.reverse()
  end

  @doc false
  def meta_type(_opts \\ []) do
    {:shape,
     [
       current_page: :integer,
       current_offset: {:optional, :integer},
       end_cursor: {:optional, :string},
       has_next_page: :boolean,
       has_previous_page: :boolean,
       next_offset: {:optional, :integer},
       page_size: :integer,
       previous_offset: {:optional, :integer},
       start_cursor: {:optional, :string},
       total_count: {:optional, :integer},
       total_pages: {:optional, :integer}
     ]}
  end

  defp add_pagination_specs(specs, false), do: specs
  defp add_pagination_specs(specs, :none), do: specs

  defp add_pagination_specs(specs, :page) do
    [
      {:page, :integer},
      {:page_size, :integer}
      | specs
    ]
  end

  defp add_pagination_specs(specs, :offset) do
    [
      {:limit, :integer},
      {:offset, :integer}
      | specs
    ]
  end

  defp add_pagination_specs(specs, :cursor) do
    [
      {:first, :integer},
      {:last, :integer},
      {:after, :string},
      {:before, :string}
      | specs
    ]
  end

  defp add_pagination_specs(specs, :all) do
    specs
    |> add_pagination_specs(:page)
    |> add_pagination_specs(:offset)
    |> add_pagination_specs(:cursor)
  end

  defp add_pagination_specs(_specs, pagination) do
    raise ArgumentError,
          "unsupported flop pagination mode #{inspect(pagination)}. " <>
            "Use :page, :offset, :cursor, :all, false, or :none."
  end

  defp sorting_specs do
    [
      {:order_by, {:union, [{:list, :string}, :string]}},
      {:order_directions, {:union, [{:list, {:enum, @directions}}, {:enum, @directions}]}}
    ]
  end

  defp filter_specs do
    [
      {:filters,
       {:list,
        {:shape,
         [
           field: :string,
           op: {:optional, :string},
           value: :any
         ]}}}
    ]
  end

  defp maybe_add(specs, true, additions), do: Enum.reverse(additions) ++ specs
  defp maybe_add(specs, _false, _additions), do: specs
end

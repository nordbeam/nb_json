defmodule NbJson.JsonApi do
  @moduledoc """
  JSON:API document helpers.

  The helpers intentionally cover the common Phoenix API response shape without
  forcing the rest of `nb_json` to become JSON:API-only. A JSON:API response has
  one primary data assign plus optional top-level `:meta`, `:links`, and
  `:included` assigns.
  """

  @reserved_resource_keys [
    :id,
    "id",
    :type,
    "type",
    :attributes,
    "attributes",
    :relationships,
    "relationships",
    :links,
    "links",
    :meta,
    "meta",
    :__struct__,
    :__meta__
  ]

  @json_api_option_keys [
    :attributes,
    :id_key,
    :included_type,
    :included_types,
    :jsonapi,
    :primary,
    :relationships,
    :type,
    :version
  ]

  @type assigns :: map()
  @type payload :: map()

  @doc """
  Builds a JSON:API document from materialized response assigns.

  ## Options

    * `:type` - primary resource type. Defaults to the single data assign name.
    * `:primary` - selects the primary data key when the assign map has more
      than one non-reserved key.
    * `:attributes` - list of attributes to include, or `false` to omit
      attributes.
    * `:relationships` - relationship definitions, e.g.
      `[author: [type: "people"], comments: "comments"]`.
    * `:id_key` - resource id key. Defaults to `:id`.
    * `:included_types` - type overrides for keyword-style included data.
    * `:version` or `:jsonapi` - optional top-level JSON:API object.
  """
  @spec document(assigns(), keyword()) :: payload()
  def document(assigns, opts \\ []) when is_map(assigns) do
    opts = normalize_options!(opts)

    {meta, assigns} = pop_any(assigns, :meta)
    {links, assigns} = pop_any(assigns, :links)
    {included, assigns} = pop_any(assigns, :included)
    {data_key, data} = primary_data!(assigns, opts)

    data_opts =
      opts
      |> Keyword.put_new(:fallback_type, key_to_string(data_key))

    %{data: resource_data(data, data_opts)}
    |> maybe_put(:meta, meta)
    |> maybe_put(:links, links)
    |> maybe_put(:included, included_data(included, opts))
    |> maybe_put(:jsonapi, jsonapi_object(opts))
  end

  @doc false
  def normalize_options!(opts) when is_list(opts) do
    nested =
      opts
      |> Keyword.get(:json_api, [])
      |> normalize_option_container!(:json_api)

    top_level =
      opts
      |> Keyword.take(@json_api_option_keys)
      |> normalize_option_container!(:json_api)

    nested
    |> Keyword.merge(top_level)
    |> normalize_relationship_options!()
  end

  def normalize_options!(opts) do
    raise ArgumentError, "JSON:API options must be a keyword list, got: #{inspect(opts)}"
  end

  @doc false
  def validate_options!(opts) do
    opts = normalize_options!(opts)

    validate_attributes_option!(Keyword.get(opts, :attributes, :all))
    validate_config_container!(Keyword.get(opts, :included_types, []), :included_types)
    validate_jsonapi_option!(Keyword.get(opts, :jsonapi))
    :ok
  end

  defp validate_attributes_option!(attributes)
       when attributes in [:all, false] or is_list(attributes),
       do: :ok

  defp validate_attributes_option!(attributes) do
    raise ArgumentError,
          "JSON:API :attributes must be :all, false, or a list, got: #{inspect(attributes)}"
  end

  defp validate_config_container!(nil, _name), do: :ok
  defp validate_config_container!(config, _name) when is_map(config), do: :ok

  defp validate_config_container!(config, name) when is_list(config) do
    unless Keyword.keyword?(config) do
      raise ArgumentError, "JSON:API :#{name} must be a keyword list or map"
    end
  end

  defp validate_config_container!(config, name) do
    raise ArgumentError,
          "JSON:API :#{name} must be a keyword list or map, got: #{inspect(config)}"
  end

  defp validate_jsonapi_option!(nil), do: :ok
  defp validate_jsonapi_option!(jsonapi) when is_map(jsonapi), do: :ok

  defp validate_jsonapi_option!(jsonapi) when is_list(jsonapi) do
    unless Keyword.keyword?(jsonapi) do
      raise ArgumentError, "JSON:API :jsonapi must be a keyword list or map"
    end
  end

  defp validate_jsonapi_option!(jsonapi) do
    raise ArgumentError,
          "JSON:API :jsonapi must be a keyword list or map, got: #{inspect(jsonapi)}"
  end

  defp normalize_option_container!(nil, _name), do: []
  defp normalize_option_container!(opts, _name) when is_list(opts), do: opts
  defp normalize_option_container!(%{} = opts, _name), do: Map.to_list(opts)

  defp normalize_option_container!(opts, name) do
    raise ArgumentError, "#{name} options must be a keyword list or map, got: #{inspect(opts)}"
  end

  defp normalize_relationship_options!(opts) do
    case Keyword.fetch(opts, :relationships) do
      {:ok, relationships} ->
        Keyword.put(opts, :relationships, normalize_relationships!(relationships))

      :error ->
        opts
    end
  end

  defp primary_data!(assigns, opts) do
    case Keyword.get(opts, :primary) do
      nil ->
        single_primary_data!(assigns)

      primary ->
        {value, rest} = pop_any(assigns, primary)

        cond do
          value == nil and not has_any_key?(assigns, primary) ->
            raise ArgumentError,
                  "JSON:API primary data key #{inspect(primary)} was not found in assigns"

          map_size(rest) > 0 ->
            raise_multiple_primary_data!(Map.keys(rest))

          true ->
            {primary, value}
        end
    end
  end

  defp single_primary_data!(assigns) when map_size(assigns) == 0, do: {nil, nil}

  defp single_primary_data!(assigns) do
    case Map.to_list(assigns) do
      [{key, value}] ->
        {key, value}

      many ->
        many
        |> Enum.map(fn {key, _value} -> key end)
        |> raise_multiple_primary_data!()
    end
  end

  defp raise_multiple_primary_data!(keys) do
    raise ArgumentError,
          "JSON:API responses require one primary data assign, got: " <>
            Enum.map_join(keys, ", ", &inspect/1)
  end

  defp resource_data(nil, _opts), do: nil
  defp resource_data([], _opts), do: []

  defp resource_data(value, opts) when is_list(value) do
    if Keyword.keyword?(value) do
      resource_object(value, opts)
    else
      Enum.map(value, &resource_object(&1, opts))
    end
  end

  defp resource_data(value, opts), do: resource_object(value, opts)

  defp resource_object(value, opts) do
    resource = resource_map!(value, "JSON:API resource data")

    if preformatted_resource?(resource) do
      resource
      |> stringify_id()
      |> maybe_put_preformatted_type(opts)
    else
      relationship_configs = relationship_configs(opts)
      relationship_names = Enum.map(relationship_configs, fn {name, _config} -> name end)
      attributes = attributes(resource, opts, relationship_names)
      relationships = relationships(resource, relationship_configs)

      %{type: resource_type!(resource, opts)}
      |> maybe_put(:id, resource_id(resource, opts))
      |> maybe_put(:attributes, empty_to_nil(attributes))
      |> maybe_put(:relationships, empty_to_nil(relationships))
      |> maybe_put(:links, fetch_optional(resource, :links))
      |> maybe_put(:meta, fetch_optional(resource, :meta))
    end
  end

  defp resource_map!(value, context) when is_list(value) and value != [] do
    if Keyword.keyword?(value) do
      Map.new(value)
    else
      raise ArgumentError, "#{context} must be a map or keyword list, got: #{inspect(value)}"
    end
  end

  defp resource_map!(%{__struct__: _} = value, _context), do: Map.from_struct(value)
  defp resource_map!(%{} = value, _context), do: value

  defp resource_map!(value, context) do
    raise ArgumentError, "#{context} must be a map or keyword list, got: #{inspect(value)}"
  end

  defp preformatted_resource?(resource) do
    has_any_key?(resource, :type) and
      (has_any_key?(resource, :attributes) or has_any_key?(resource, :relationships))
  end

  defp maybe_put_preformatted_type(resource, opts) do
    if has_any_key?(resource, :type) do
      resource
    else
      Map.put(resource, :type, resource_type!(resource, opts))
    end
  end

  defp stringify_id(resource) do
    case fetch_any(resource, :id) do
      {:ok, nil} ->
        resource

      {:ok, id} ->
        resource
        |> delete_any(:id)
        |> Map.put(:id, to_string(id))

      :error ->
        resource
    end
  end

  defp resource_type!(resource, opts) do
    type =
      Keyword.get(opts, :type) ||
        fetch_optional(resource, :type) ||
        Keyword.get(opts, :fallback_type)

    case type do
      nil ->
        raise ArgumentError,
              "JSON:API resource type is required. Pass :type or include a :type field."

      type ->
        to_string(type)
    end
  end

  defp resource_id(resource, opts) do
    id_key = Keyword.get(opts, :id_key, :id)

    case fetch_any(resource, id_key) do
      {:ok, nil} -> nil
      {:ok, id} -> to_string(id)
      :error -> nil
    end
  end

  defp attributes(resource, opts, relationship_names) do
    id_key = Keyword.get(opts, :id_key, :id)

    case Keyword.get(opts, :attributes, :all) do
      false ->
        %{}

      :all ->
        resource
        |> Map.drop(
          @reserved_resource_keys ++ key_variants(id_key) ++ key_variants(relationship_names)
        )

      keys when is_list(keys) ->
        keys
        |> Enum.reduce(%{}, fn key, acc ->
          case fetch_any(resource, key) do
            {:ok, value} -> Map.put(acc, key, value)
            :error -> acc
          end
        end)
        |> Map.drop(key_variants(relationship_names))

      other ->
        raise ArgumentError,
              "JSON:API :attributes must be :all, false, or a list, got: #{inspect(other)}"
    end
  end

  defp relationship_configs(opts) do
    opts
    |> Keyword.get(:relationships, [])
    |> normalize_relationships!()
  end

  defp normalize_relationships!(nil), do: []

  defp normalize_relationships!(relationships) when is_list(relationships) do
    cond do
      relationships == [] ->
        []

      relationship_pairs?(relationships) ->
        Enum.map(relationships, fn {name, config} ->
          {name, normalize_relationship_config!(name, config)}
        end)

      Enum.all?(relationships, &(is_atom(&1) or is_binary(&1))) ->
        Enum.map(relationships, fn name -> {name, normalize_relationship_config!(name, [])} end)

      true ->
        raise ArgumentError,
              "JSON:API :relationships must be a keyword list, map, or list of names"
    end
  end

  defp normalize_relationships!(%{} = relationships) do
    relationships
    |> Map.to_list()
    |> Enum.map(fn {name, config} -> {name, normalize_relationship_config!(name, config)} end)
  end

  defp normalize_relationships!(other) do
    raise ArgumentError,
          "JSON:API :relationships must be a keyword list, map, or list of names, got: " <>
            inspect(other)
  end

  defp relationship_pairs?(relationships) do
    Enum.all?(relationships, fn
      {name, _config} when is_atom(name) or is_binary(name) -> true
      _other -> false
    end)
  end

  defp normalize_relationship_config!(name, nil), do: normalize_relationship_config!(name, [])

  defp normalize_relationship_config!(name, type) when is_binary(type) or is_atom(type) do
    %{type: to_string(type), fallback_type: key_to_string(name)}
  end

  defp normalize_relationship_config!(name, config) when is_list(config) do
    if Keyword.keyword?(config) do
      name
      |> normalize_relationship_config!(Map.new(config))
      |> Map.put_new(:fallback_type, key_to_string(name))
    else
      raise ArgumentError,
            "JSON:API relationship #{inspect(name)} config must be a keyword list or map"
    end
  end

  defp normalize_relationship_config!(name, %{} = config) do
    config
    |> normalize_known_config_key(:type)
    |> normalize_known_config_key(:links)
    |> normalize_known_config_key(:meta)
    |> normalize_known_config_key(:optional)
    |> normalize_known_config_key(:id_key)
    |> Map.update(:type, nil, &to_string/1)
    |> Map.put_new(:fallback_type, key_to_string(name))
  end

  defp normalize_relationship_config!(name, other) do
    raise ArgumentError,
          "JSON:API relationship #{inspect(name)} config must be a keyword list, map, " <>
            "atom type, or string type, got: #{inspect(other)}"
  end

  defp normalize_known_config_key(config, key) do
    string_key = Atom.to_string(key)

    if Map.has_key?(config, string_key) and not Map.has_key?(config, key) do
      config
      |> Map.put(key, Map.fetch!(config, string_key))
      |> Map.delete(string_key)
    else
      config
    end
  end

  defp relationships(resource, relationship_configs) do
    Enum.reduce(relationship_configs, %{}, fn {name, config}, acc ->
      case fetch_any(resource, name) do
        {:ok, value} ->
          Map.put(acc, name, relationship_object(value, config))

        :error ->
          if Map.get(config, :optional, false) do
            acc
          else
            raise ArgumentError,
                  "JSON:API relationship #{inspect(name)} is configured but missing from resource"
          end
      end
    end)
  end

  defp relationship_object(value, config) do
    %{data: relationship_data(value, config)}
    |> maybe_put(:links, Map.get(config, :links))
    |> maybe_put(:meta, Map.get(config, :meta))
  end

  defp relationship_data(nil, _config), do: nil
  defp relationship_data([], _config), do: []

  defp relationship_data(value, config) when is_list(value) do
    if Keyword.keyword?(value) do
      relationship_identifier(value, config)
    else
      Enum.map(value, &relationship_identifier(&1, config))
    end
  end

  defp relationship_data(value, config), do: relationship_identifier(value, config)

  defp relationship_identifier(value, config) when is_binary(value) or is_integer(value) do
    %{type: relationship_type!(%{}, config), id: to_string(value)}
  end

  defp relationship_identifier(value, config) do
    resource = resource_map!(value, "JSON:API relationship data")
    id_key = Map.get(config, :id_key, :id)

    id =
      case fetch_any(resource, id_key) do
        {:ok, nil} -> nil
        {:ok, value} -> to_string(value)
        :error -> nil
      end

    if id in [nil, ""] do
      raise ArgumentError,
            "JSON:API relationship data requires an id field for type " <>
              inspect(relationship_type!(resource, config))
    end

    %{type: relationship_type!(resource, config), id: id}
  end

  defp relationship_type!(resource, config) do
    type =
      Map.get(config, :type) || fetch_optional(resource, :type) || Map.get(config, :fallback_type)

    case type do
      nil -> raise ArgumentError, "JSON:API relationship type is required"
      type -> to_string(type)
    end
  end

  defp included_data(nil, _opts), do: nil
  defp included_data([], _opts), do: []

  defp included_data(included, opts) when is_list(included) do
    if Keyword.keyword?(included) do
      Enum.flat_map(included, fn {name, value} ->
        value
        |> included_values()
        |> Enum.map(&resource_object(&1, included_opts(name, opts)))
      end)
    else
      Enum.map(included, &resource_object(&1, included_opts(nil, opts)))
    end
  end

  defp included_data(included, opts), do: [resource_object(included, included_opts(nil, opts))]

  defp included_values(value) when is_list(value) do
    cond do
      value == [] -> []
      Keyword.keyword?(value) -> [value]
      true -> value
    end
  end

  defp included_values(value), do: [value]

  defp included_opts(name, opts) do
    included_types = Keyword.get(opts, :included_types, [])
    type = fetch_config_value(included_types, name)

    []
    |> maybe_keyword_put(:type, type || Keyword.get(opts, :included_type))
    |> maybe_keyword_put(:fallback_type, if(name, do: key_to_string(name)))
  end

  defp jsonapi_object(opts) do
    cond do
      is_map(Keyword.get(opts, :jsonapi)) ->
        Keyword.get(opts, :jsonapi)

      is_list(Keyword.get(opts, :jsonapi)) ->
        Map.new(Keyword.get(opts, :jsonapi))

      version = Keyword.get(opts, :version) ->
        %{version: to_string(version)}

      true ->
        nil
    end
  end

  defp fetch_config_value(nil, _key), do: nil

  defp fetch_config_value(config, key) when is_list(config) do
    cond do
      key == nil -> nil
      Keyword.keyword?(config) -> Keyword.get(config, key)
      true -> nil
    end
  end

  defp fetch_config_value(%{} = config, key) do
    cond do
      key == nil -> nil
      Map.has_key?(config, key) -> Map.fetch!(config, key)
      Map.has_key?(config, key_to_string(key)) -> Map.fetch!(config, key_to_string(key))
      true -> nil
    end
  end

  defp fetch_config_value(_config, _key), do: nil

  defp fetch_optional(resource, key) do
    case fetch_any(resource, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fetch_any(map, keys) when is_list(keys) do
    Enum.reduce_while(keys, :error, fn key, :error ->
      case fetch_any(map, key) do
        {:ok, value} -> {:halt, {:ok, value}}
        :error -> {:cont, :error}
      end
    end)
  end

  defp fetch_any(map, key) do
    key
    |> key_variants()
    |> Enum.reduce_while(:error, fn variant, :error ->
      if Map.has_key?(map, variant) do
        {:halt, {:ok, Map.fetch!(map, variant)}}
      else
        {:cont, :error}
      end
    end)
  end

  defp pop_any(map, key) do
    key
    |> key_variants()
    |> Enum.reduce_while({nil, map}, fn variant, {_value, current} ->
      if Map.has_key?(current, variant) do
        {:halt, {Map.fetch!(current, variant), Map.delete(current, variant)}}
      else
        {:cont, {nil, current}}
      end
    end)
  end

  defp delete_any(map, key), do: Map.drop(map, key_variants(key))

  defp has_any_key?(map, key) do
    Enum.any?(key_variants(key), &Map.has_key?(map, &1))
  end

  defp key_variants(keys) when is_list(keys), do: Enum.flat_map(keys, &key_variants/1)
  defp key_variants(nil), do: []
  defp key_variants(key) when is_atom(key), do: [key, Atom.to_string(key)]

  defp key_variants(key) when is_binary(key) do
    case string_to_existing_atom(key) do
      nil -> [key]
      atom -> [key, atom]
    end
  end

  defp key_variants(key), do: [key]

  defp string_to_existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp key_to_string(nil), do: nil
  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key), do: to_string(key)

  defp empty_to_nil(value) when value == %{}, do: nil
  defp empty_to_nil(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_keyword_put(keyword, _key, nil), do: keyword
  defp maybe_keyword_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end

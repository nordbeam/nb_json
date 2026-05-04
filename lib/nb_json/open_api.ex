defmodule NbJson.OpenApi do
  @moduledoc """
  Generates OpenAPI metadata from `NbJson.Controller` declarations.

  The map output is dependency-light and can be encoded directly as JSON.
  When `open_api_spex` is installed, `to_open_api_spex/2` converts the same
  document into an `%OpenApiSpex.OpenApi{}` struct for serving, request
  validation, and response validation.

  Serializer refs that expose `nb_serializer` metadata are expanded into
  reusable component schemas.
  """

  @open_api_decode Module.concat(["OpenApiSpex", "OpenApi", "Decode"])
  @serializer_config Module.concat(["NbSerializer", "Config"])

  @doc """
  Builds an OpenAPI 3.0.3 document from controller modules.
  """
  @spec to_map([module()] | module(), keyword()) :: map()
  def to_map(modules, opts \\ [])

  def to_map(module, opts) when is_atom(module), do: to_map([module], opts)

  def to_map(modules, opts) when is_list(modules) do
    endpoints = Enum.flat_map(modules, &module_endpoints/1)

    %{
      "openapi" => Keyword.get(opts, :openapi, "3.0.3"),
      "info" => %{
        "title" => Keyword.get(opts, :title, "JSON API"),
        "version" => Keyword.get(opts, :version, "0.1.0")
      },
      "paths" => build_paths(endpoints),
      "components" => build_components(endpoints, opts)
    }
    |> maybe_put("servers", normalize_servers(Keyword.get(opts, :servers)))
    |> maybe_put("security", normalize_security(Keyword.get(opts, :security)))
    |> maybe_put("tags", Keyword.get(opts, :tags))
    |> drop_nil_values()
  end

  @doc """
  Encodes the OpenAPI document as JSON.
  """
  @spec to_json!([module()] | module(), keyword()) :: binary()
  def to_json!(modules, opts \\ []) do
    modules
    |> to_map(opts)
    |> Jason.encode!(pretty: Keyword.get(opts, :pretty, true))
  end

  @doc """
  Builds an `%OpenApiSpex.OpenApi{}` struct when `open_api_spex` is available.

  `open_api_spex` currently targets OpenAPI 3.0.x, so `nb_json` defaults to
  `3.0.3`.
  """
  @spec to_open_api_spex([module()] | module(), keyword()) :: struct()
  def to_open_api_spex(modules, opts \\ []) do
    decoder = @open_api_decode

    if Code.ensure_loaded?(decoder) and function_exported?(decoder, :decode, 1) do
      modules
      |> to_map(Keyword.put_new(opts, :openapi, "3.0.3"))
      |> then(&apply(decoder, :decode, [&1]))
    else
      raise ArgumentError,
            "open_api_spex is not available. Add {:open_api_spex, \"~> 3.22\"} " <>
              "to your application dependencies or use NbJson.OpenApi.to_map/2."
    end
  end

  @doc """
  Builds an `%OpenApiSpex.Operation{}` for a controller action.

  This lets `OpenApiSpex.Plug.CastAndValidate` infer operations from Phoenix
  controller/action metadata while keeping `nb_json` as the authoring DSL.
  """
  @spec open_api_operation(module(), atom(), keyword()) :: struct()
  def open_api_operation(controller, action, opts \\ [])
      when is_atom(controller) and is_atom(action) do
    with {:ok, endpoint} <- fetch_endpoint(controller, action) do
      spec = to_open_api_spex([controller], opts)
      operation_id = operation_id(controller, endpoint)

      spec.paths
      |> Map.values()
      |> Enum.flat_map(&path_item_operations/1)
      |> Enum.find(&(&1.operationId == operation_id))
      |> case do
        nil ->
          raise ArgumentError,
                "could not find OpenApiSpex operation #{inspect(operation_id)} for " <>
                  "#{inspect(controller)}.#{action}"

        operation ->
          operation
      end
    else
      {:error, reason} ->
        raise ArgumentError,
              "could not build OpenApiSpex operation for #{inspect(controller)}.#{action}: " <>
                inspect(reason)
    end
  end

  defp build_paths(endpoints) do
    endpoints
    |> Enum.reduce(%{}, fn {module, endpoint}, paths ->
      path = endpoint.path || "/#{endpoint.name}"
      method = endpoint.method

      Map.update(paths, path, %{method => operation(module, endpoint)}, fn existing ->
        Map.put(existing, method, operation(module, endpoint))
      end)
    end)
  end

  defp module_endpoints(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__nb_json_endpoints__, 0) do
      module.__nb_json_endpoints__()
      |> Map.values()
      |> Enum.map(&{module, &1})
    else
      []
    end
  end

  defp fetch_endpoint(controller, action) do
    if Code.ensure_loaded?(controller) and
         function_exported?(controller, :__nb_json_endpoints__, 0) do
      case controller.__nb_json_endpoints__() do
        %{^action => endpoint} -> {:ok, endpoint}
        _endpoints -> {:error, %{endpoint: ["is not declared"]}}
      end
    else
      {:error, %{controller: ["does not declare JSON endpoints"]}}
    end
  end

  defp build_components(endpoints, opts) do
    %{"schemas" => serializer_components(endpoints, opts)}
    |> maybe_put(
      "securitySchemes",
      normalize_security_schemes(Keyword.get(opts, :security_schemes))
    )
  end

  defp serializer_components(endpoints, opts) do
    endpoints
    |> endpoint_serializer_refs()
    |> collect_serializer_modules()
    |> Enum.reduce(%{}, fn module, components ->
      name = schema_name(module)

      if Map.has_key?(components, name) do
        raise ArgumentError,
              "duplicate OpenAPI schema name #{inspect(name)} from #{inspect(module)}. " <>
                "Set a unique nb_serializer typescript_name/1 or namespace/1."
      end

      Map.put(components, name, serializer_schema(module, opts))
    end)
  end

  defp endpoint_serializer_refs(endpoints) do
    Enum.flat_map(endpoints, fn {_module, endpoint} ->
      param_types = Enum.map(endpoint.params, & &1.type)

      response_types =
        Enum.flat_map(endpoint.responses, fn
          %{kind: :success} = response ->
            Enum.map(response.data ++ response.meta, & &1.type)

          %{kind: :error} = response ->
            [response.details]
        end)

      Enum.flat_map(param_types ++ response_types, &serializer_refs_from_type/1)
    end)
  end

  defp collect_serializer_modules(modules) do
    modules
    |> Enum.uniq()
    |> do_collect_serializer_modules(MapSet.new(), [])
  end

  defp do_collect_serializer_modules([], _seen, acc), do: Enum.reverse(acc)

  defp do_collect_serializer_modules([module | rest], seen, acc) do
    cond do
      MapSet.member?(seen, module) ->
        do_collect_serializer_modules(rest, seen, acc)

      not serializer_module?(module) ->
        do_collect_serializer_modules(rest, MapSet.put(seen, module), acc)

      true ->
        nested =
          module
          |> serializer_metadata_fields()
          |> Enum.flat_map(fn {_name, type_info} -> serializer_refs_from_type_info(type_info) end)

        do_collect_serializer_modules(
          rest ++ nested,
          MapSet.put(seen, module),
          [module | acc]
        )
    end
  end

  defp operation(module, endpoint) do
    parameters =
      endpoint.params
      |> Enum.reject(&((&1.location || :query) == :body))
      |> Enum.map(&parameter/1)

    body_fields = Enum.filter(endpoint.params, &((&1.location || :query) == :body))

    %{
      "operationId" => operation_id(module, endpoint),
      "summary" => endpoint.summary,
      "description" => endpoint.description,
      "tags" => blank_to_nil(endpoint.tags),
      "deprecated" => true_or_nil(endpoint.deprecated),
      "security" => normalize_security(endpoint.security),
      "servers" => normalize_servers(endpoint.servers),
      "parameters" => parameters,
      "requestBody" => request_body(body_fields, endpoint),
      "responses" => responses(endpoint.responses)
    }
    |> drop_nil_values()
  end

  defp parameter(field) do
    %{
      "name" => Atom.to_string(field.name),
      "in" => to_string(field.location || :query),
      "required" => (field.location || :query) == :path or !field.optional,
      "description" => field.description,
      "example" => field.example,
      "schema" => schema(field.type)
    }
    |> drop_nil_values()
  end

  defp request_body([], _endpoint), do: nil

  defp request_body(fields, endpoint) do
    %{
      "description" => endpoint.request_body_description,
      "required" => Enum.any?(fields, &(!&1.optional)),
      "content" => json_content(object_schema(fields))
    }
    |> drop_nil_values()
  end

  defp responses(responses) do
    Map.new(responses, fn response ->
      {to_string(response.status), response_body(response)}
    end)
  end

  defp response_body(%{kind: :success} = response) do
    schema =
      if Map.get(response, :profile) == :json_api do
        json_api_response_schema(response)
      else
        %{
          "type" => "object",
          "properties" =>
            %{
              "data" => object_schema(response.data)
            }
            |> maybe_put("meta", object_schema(response.meta, omit_when_empty: true))
        }
      end

    %{
      "description" =>
        response.description || NbJson.PlugStatus.reason_phrase(response.status) || "Success",
      "content" => json_content(schema)
    }
  end

  defp response_body(%{kind: :error} = response) do
    %{
      "description" =>
        response.description || NbJson.PlugStatus.reason_phrase(response.status) || "Error",
      "content" => json_content(error_schema(response))
    }
  end

  defp json_content(schema) do
    %{
      "application/json" => %{
        "schema" => schema
      }
    }
  end

  defp json_api_response_schema(response) do
    json_api = Map.get(response, :json_api, [])
    data_field = List.first(response.data)

    properties =
      %{
        "data" => json_api_data_schema(data_field.type, json_api)
      }
      |> maybe_put("meta", object_schema(response.meta, omit_when_empty: true))
      |> maybe_put("links", %{"type" => "object", "additionalProperties" => true})
      |> maybe_put("included", %{
        "type" => "array",
        "items" => json_api_resource_schema(:map, [])
      })

    %{
      "type" => "object",
      "properties" => properties,
      "required" => ["data"]
    }
  end

  defp json_api_data_schema({:list, inner}, json_api) do
    %{"type" => "array", "items" => json_api_resource_schema(inner, json_api)}
  end

  defp json_api_data_schema(:list, json_api) do
    %{"type" => "array", "items" => json_api_resource_schema(:map, json_api)}
  end

  defp json_api_data_schema(type, json_api), do: json_api_resource_schema(type, json_api)

  defp json_api_resource_schema(type, json_api) do
    relationships = json_api_relationships_schema(Keyword.get(json_api, :relationships, []))
    resource_type = Keyword.get(json_api, :type)

    properties =
      %{
        "type" => %{"type" => "string"},
        "id" => %{"type" => "string"},
        "attributes" => json_api_attributes_schema(type),
        "links" => %{"type" => "object", "additionalProperties" => true},
        "meta" => %{"type" => "object", "additionalProperties" => true}
      }
      |> maybe_put("relationships", relationships)

    properties =
      if resource_type do
        update_in(properties, ["type"], &Map.put(&1, "example", to_string(resource_type)))
      else
        properties
      end

    %{
      "type" => "object",
      "properties" => properties,
      "required" => ["type"]
    }
  end

  defp json_api_attributes_schema({:list, inner}), do: json_api_attributes_schema(inner)

  defp json_api_attributes_schema(:list),
    do: %{"type" => "object", "additionalProperties" => true}

  defp json_api_attributes_schema(type), do: schema(type)

  defp json_api_relationships_schema([]), do: nil
  defp json_api_relationships_schema(nil), do: nil

  defp json_api_relationships_schema(relationships) when is_map(relationships) do
    relationships
    |> Map.to_list()
    |> json_api_relationships_schema()
  end

  defp json_api_relationships_schema(relationships) when is_list(relationships) do
    if json_api_relationship_pairs?(relationships) do
      %{
        "type" => "object",
        "properties" =>
          relationships
          |> Enum.map(fn {name, _config} -> {to_string(name), json_api_relationship_schema()} end)
          |> Map.new()
      }
    end
  end

  defp json_api_relationship_pairs?(relationships) do
    Enum.all?(relationships, fn
      {name, _config} when is_atom(name) or is_binary(name) -> true
      _other -> false
    end)
  end

  defp json_api_relationship_schema do
    %{
      "type" => "object",
      "properties" => %{
        "data" => %{
          "oneOf" => [
            json_api_identifier_schema(),
            %{"type" => "array", "items" => json_api_identifier_schema()},
            %{"type" => "object", "nullable" => true}
          ]
        },
        "links" => %{"type" => "object", "additionalProperties" => true},
        "meta" => %{"type" => "object", "additionalProperties" => true}
      },
      "required" => ["data"]
    }
  end

  defp json_api_identifier_schema do
    %{
      "type" => "object",
      "properties" => %{
        "type" => %{"type" => "string"},
        "id" => %{"type" => "string"}
      },
      "required" => ["type", "id"]
    }
  end

  defp object_schema(fields, opts \\ []) do
    properties =
      fields
      |> Enum.map(fn field -> {Atom.to_string(field.name), schema(field.type)} end)
      |> Map.new()

    required =
      fields
      |> Enum.reject(& &1.optional)
      |> Enum.map(&Atom.to_string(&1.name))

    schema =
      %{
        "type" => "object",
        "properties" => properties,
        "required" => required
      }

    cond do
      properties == %{} and Keyword.get(opts, :omit_when_empty, false) -> nil
      required == [] -> Map.delete(schema, "required")
      true -> schema
    end
  end

  defp error_schema(response) do
    %{
      "type" => "object",
      "properties" => %{
        "error" => %{
          "type" => "object",
          "properties" => %{
            "code" => %{"type" => "string", "example" => to_string(response.code)},
            "message" => %{"type" => "string"},
            "status" => %{"type" => "integer", "example" => response.status},
            "details" => schema(response.details)
          },
          "required" => ["code", "message"]
        }
      },
      "required" => ["error"]
    }
  end

  defp serializer_schema(module, opts) do
    key_overrides = serializer_key_overrides(module)

    fields =
      module
      |> serializer_metadata_fields()
      |> Enum.map(fn {name, type_info} ->
        {name, type_info, serializer_property_name(module, name, key_overrides, opts)}
      end)
      |> Enum.sort_by(fn {_name, _type_info, property_name} -> property_name end)

    properties =
      fields
      |> Enum.map(fn {_name, type_info, property_name} ->
        {property_name, serializer_type_schema(type_info)}
      end)
      |> Map.new()

    required =
      fields
      |> Enum.reject(fn {_name, type_info, _property_name} ->
        Map.get(type_info, :optional, false)
      end)
      |> Enum.map(fn {_name, _type_info, property_name} -> property_name end)

    schema = %{"type" => "object", "properties" => properties}

    if required == [] do
      schema
    else
      Map.put(schema, "required", required)
    end
  end

  defp serializer_metadata_fields(module) do
    metadata =
      module.__nb_serializer_type_metadata__()
      |> normalize_serializer_metadata()

    field_overrides = serializer_field_type_overrides(module)
    relationship_overrides = serializer_relationship_type_overrides(module)

    Enum.map(metadata, fn {name, type_info} ->
      type_info =
        type_info
        |> normalize_type_info()
        |> Map.merge(Map.get(field_overrides, name, %{}))
        |> Map.merge(Map.get(relationship_overrides, name, %{}))

      {name, type_info}
    end)
  end

  defp normalize_serializer_metadata(%{fields: field_list}) when is_list(field_list) do
    Enum.map(field_list, fn field_spec ->
      opts = Map.get(field_spec, :opts, [])

      type_info = %{
        type: field_spec_option(field_spec, opts, :type),
        enum: field_spec_option(field_spec, opts, :enum),
        list: field_spec_option(field_spec, opts, :list, false),
        nullable: field_spec_option(field_spec, opts, :nullable, false),
        optional: field_spec_option(field_spec, opts, :optional, false),
        serializer: field_spec_option(field_spec, opts, :serializer),
        polymorphic: field_spec_option(field_spec, opts, :polymorphic),
        custom: field_spec_option(field_spec, opts, :custom, false)
      }

      {Map.fetch!(field_spec, :name), type_info}
    end)
  end

  defp normalize_serializer_metadata(metadata) when is_map(metadata), do: Enum.to_list(metadata)
  defp normalize_serializer_metadata(_metadata), do: []

  defp field_spec_option(field_spec, opts, key, default \\ nil) do
    cond do
      Map.has_key?(field_spec, key) -> Map.get(field_spec, key)
      Keyword.has_key?(opts, key) -> Keyword.get(opts, key)
      true -> default
    end
  end

  defp normalize_type_info(type_info) when is_map(type_info), do: type_info
  defp normalize_type_info(type_info) when is_list(type_info), do: Map.new(type_info)
  defp normalize_type_info(type), do: %{type: type}

  defp serializer_field_type_overrides(module) do
    if function_exported?(module, :__nb_serializer_fields__, 0) do
      module.__nb_serializer_fields__()
      |> Enum.map(fn {name, opts} ->
        optional? =
          Keyword.get(opts, :optional, false) or Keyword.has_key?(opts, :if) or
            Keyword.has_key?(opts, :unless)

        {name, %{optional: optional?}}
      end)
      |> Map.new()
    else
      %{}
    end
  end

  defp serializer_relationship_type_overrides(module) do
    if function_exported?(module, :__nb_serializer_relationships__, 0) do
      module.__nb_serializer_relationships__()
      |> Enum.map(fn {kind, name, opts} ->
        override =
          %{}
          |> maybe_put_atom(:serializer, Keyword.get(opts, :serializer))
          |> maybe_put_atom(:polymorphic, Keyword.get(opts, :polymorphic))
          |> maybe_put_atom(:list, if(kind == :has_many, do: true, else: nil))

        {name, override}
      end)
      |> Map.new()
    else
      %{}
    end
  end

  defp serializer_key_overrides(module) do
    if function_exported?(module, :__nb_serializer_relationships__, 0) do
      module.__nb_serializer_relationships__()
      |> Enum.flat_map(fn {_kind, name, opts} ->
        case Keyword.get(opts, :key) do
          nil -> []
          key -> [{name, key}]
        end
      end)
      |> Map.new()
    else
      %{}
    end
  end

  defp serializer_type_schema(type_info) do
    type_info = normalize_type_info(type_info)

    base_schema =
      cond do
        polymorphic = Map.get(type_info, :polymorphic) ->
          polymorphic
          |> polymorphic_schema()
          |> maybe_array_schema(type_info)

        serializer = Map.get(type_info, :serializer) ->
          serializer
          |> schema_ref()
          |> maybe_array_schema(type_info)

        list_type?(Map.get(type_info, :list)) ->
          %{"type" => "array", "items" => serializer_list_items_schema(type_info)}

        enum = Map.get(type_info, :enum) ->
          schema({:enum, enum})

        Map.get(type_info, :custom) && is_binary(Map.get(type_info, :type)) ->
          %{"x-typescript-type" => Map.fetch!(type_info, :type)}

        true ->
          schema(Map.get(type_info, :type, :any))
      end

    nullable_schema(base_schema, Map.get(type_info, :nullable, false))
  end

  defp maybe_array_schema(schema, type_info) do
    if list_type?(Map.get(type_info, :list)) do
      %{"type" => "array", "items" => schema}
    else
      schema
    end
  end

  defp serializer_list_items_schema(type_info) do
    case Map.get(type_info, :list) do
      true ->
        schema(Map.get(type_info, :type, :any))

      module when is_atom(module) ->
        if module_atom?(module), do: schema_ref(module), else: schema(module)

      list when is_list(list) ->
        cond do
          Keyword.has_key?(list, :enum) -> schema({:enum, Keyword.fetch!(list, :enum)})
          Keyword.has_key?(list, :type) -> schema(Keyword.fetch!(list, :type))
          true -> %{}
        end

      _other ->
        %{}
    end
  end

  defp polymorphic_schema(polymorphic) do
    refs =
      polymorphic
      |> polymorphic_serializer_refs()
      |> Enum.map(&schema_ref/1)

    case refs do
      [] -> %{}
      refs -> %{"oneOf" => refs}
    end
  end

  defp polymorphic_serializer_refs(polymorphic) when is_list(polymorphic) do
    Enum.flat_map(polymorphic, fn
      {_struct_module, serializer} when is_atom(serializer) -> [serializer]
      serializer when is_atom(serializer) -> [serializer]
      _other -> []
    end)
  end

  defp polymorphic_serializer_refs(_polymorphic), do: []

  defp schema(:string), do: %{"type" => "string"}
  defp schema(:uuid), do: %{"type" => "string", "format" => "uuid"}
  defp schema(:integer), do: %{"type" => "integer"}
  defp schema(:float), do: %{"type" => "number", "format" => "float"}
  defp schema(:number), do: %{"type" => "number"}
  defp schema(:decimal), do: %{"type" => "string", "format" => "decimal"}
  defp schema(:boolean), do: %{"type" => "boolean"}
  defp schema(:date), do: %{"type" => "string", "format" => "date"}
  defp schema(:datetime), do: %{"type" => "string", "format" => "date-time"}
  defp schema(:map), do: %{"type" => "object", "additionalProperties" => true}
  defp schema(:list), do: %{"type" => "array", "items" => %{}}
  defp schema(:any), do: %{}
  defp schema({:list, inner}), do: %{"type" => "array", "items" => schema(inner)}
  defp schema({:enum, values}), do: %{"enum" => Enum.map(values, &to_string/1)}
  defp schema({:literal, value}), do: %{"const" => value}
  defp schema({:nullable, inner}), do: nullable_schema(schema(inner), true)
  defp schema({:optional, inner}), do: schema(inner)
  defp schema({:union, types}), do: %{"oneOf" => Enum.map(types, &schema/1)}
  defp schema({:typescript_validated, ts_string}), do: %{"x-typescript-type" => ts_string}
  defp schema(type) when is_binary(type), do: %{"x-typescript-type" => type}

  defp schema({:shape, fields}) do
    object_schema(
      Enum.map(fields, fn {name, type} -> %{name: name, type: type, optional: optional?(type)} end)
    )
  end

  defp schema({:ref, module}) do
    schema_ref(module)
  end

  defp schema(_unknown), do: %{}

  defp optional?({:optional, _inner}), do: true
  defp optional?(_type), do: false

  defp nullable_schema(%{"$ref" => _ref} = schema, true),
    do: %{"allOf" => [schema], "nullable" => true}

  defp nullable_schema(schema, true), do: Map.put(schema, "nullable", true)
  defp nullable_schema(schema, _false), do: schema

  defp schema_ref(module), do: %{"$ref" => "#/components/schemas/#{schema_name(module)}"}

  defp operation_id(_module, %{operation_id: operation_id}) when is_binary(operation_id),
    do: operation_id

  defp operation_id(module, endpoint), do: "#{inspect(module)}.#{endpoint.name}"

  defp serializer_refs_from_type({:ref, module}), do: [module]
  defp serializer_refs_from_type({:list, inner}), do: serializer_refs_from_type(inner)
  defp serializer_refs_from_type({:nullable, inner}), do: serializer_refs_from_type(inner)
  defp serializer_refs_from_type({:optional, inner}), do: serializer_refs_from_type(inner)

  defp serializer_refs_from_type({:union, types}),
    do: Enum.flat_map(types, &serializer_refs_from_type/1)

  defp serializer_refs_from_type({:shape, fields}) do
    Enum.flat_map(fields, fn {_name, type} -> serializer_refs_from_type(type) end)
  end

  defp serializer_refs_from_type(_type), do: []

  defp serializer_refs_from_type_info(type_info) do
    type_info = normalize_type_info(type_info)

    []
    |> maybe_add_module_ref(Map.get(type_info, :serializer))
    |> maybe_add_list_ref(Map.get(type_info, :list))
    |> Kernel.++(polymorphic_serializer_refs(Map.get(type_info, :polymorphic)))
  end

  defp maybe_add_module_ref(refs, module) when is_atom(module) do
    if module_atom?(module), do: [module | refs], else: refs
  end

  defp maybe_add_module_ref(refs, _module), do: refs

  defp maybe_add_list_ref(refs, module) when is_atom(module) do
    if module_atom?(module), do: [module | refs], else: refs
  end

  defp maybe_add_list_ref(refs, _list), do: refs

  defp serializer_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__nb_serializer_type_metadata__, 0)
  end

  defp serializer_module?(_module), do: false

  defp list_type?(value), do: value not in [nil, false]

  defp module_atom?(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  defp module_atom?(_value), do: false

  defp schema_name(module) do
    Code.ensure_loaded?(module)

    custom_name =
      if function_exported?(module, :__nb_serializer_typescript_name__, 0) do
        module.__nb_serializer_typescript_name__()
      end

    namespace =
      if function_exported?(module, :__nb_serializer_typescript_namespace__, 0) do
        module.__nb_serializer_typescript_namespace__()
      end

    cond do
      is_binary(custom_name) -> custom_name
      is_binary(namespace) -> namespace <> default_schema_name(module)
      true -> default_schema_name(module)
    end
  end

  defp default_schema_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.replace_suffix("Serializer", "")
  end

  defp serializer_property_name(module, name, key_overrides, opts) do
    key = Map.get(key_overrides, name, name)

    if serializer_camelize?(module, opts) do
      key
      |> to_string()
      |> camelize()
    else
      to_string(key)
    end
  end

  defp serializer_camelize?(module, opts) do
    serializer_config = @serializer_config

    cond do
      serializer_snake_case?(module) ->
        false

      Keyword.has_key?(opts, :camelize) ->
        Keyword.fetch!(opts, :camelize)

      Keyword.has_key?(opts, :camelize_props) ->
        Keyword.fetch!(opts, :camelize_props)

      Code.ensure_loaded?(serializer_config) and
          function_exported?(serializer_config, :camelize_props?, 0) ->
        apply(serializer_config, :camelize_props?, [])

      true ->
        true
    end
  end

  defp serializer_snake_case?(module) do
    function_exported?(module, :__nb_serializer_snake_case_ts__, 0) and
      module.__nb_serializer_snake_case_ts__()
  end

  defp camelize(value) do
    value
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {word, 0} -> word
      {word, _index} -> String.capitalize(word)
    end)
  end

  defp normalize_servers(nil), do: nil
  defp normalize_servers([]), do: nil

  defp normalize_servers(servers) when is_list(servers) do
    Enum.map(servers, &normalize_server/1)
  end

  defp normalize_server(url) when is_binary(url), do: %{"url" => url}

  defp normalize_server(%_struct{} = server) do
    server
    |> Map.from_struct()
    |> normalize_server()
  end

  defp normalize_server(%{} = server) do
    server
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), normalize_server_value(value)} end)
  end

  defp normalize_server(server), do: server

  defp normalize_server_value(%_struct{} = value),
    do: value |> Map.from_struct() |> normalize_server_value()

  defp normalize_server_value(%{} = value) do
    Map.new(value, fn {key, nested} -> {to_string(key), normalize_server_value(nested)} end)
  end

  defp normalize_server_value(values) when is_list(values),
    do: Enum.map(values, &normalize_server_value/1)

  defp normalize_server_value(value), do: value

  defp normalize_security_schemes(nil), do: nil

  defp normalize_security_schemes(schemes) when is_list(schemes) do
    schemes
    |> Enum.map(fn {name, scheme} -> {to_string(name), normalize_security_scheme(scheme)} end)
    |> Map.new()
  end

  defp normalize_security_schemes(%{} = schemes) do
    schemes
    |> Enum.map(fn {name, scheme} -> {to_string(name), normalize_security_scheme(scheme)} end)
    |> Map.new()
  end

  defp normalize_security_scheme(:bearer), do: %{"type" => "http", "scheme" => "bearer"}

  defp normalize_security_scheme(:api_key),
    do: %{"type" => "apiKey", "name" => "x-api-key", "in" => "header"}

  defp normalize_security_scheme(%_struct{} = scheme) do
    scheme
    |> Map.from_struct()
    |> normalize_security_scheme()
  end

  defp normalize_security_scheme(%{} = scheme) do
    scheme
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_open_api_key(key), normalize_server_value(value)} end)
  end

  defp normalize_security_scheme(scheme), do: scheme

  defp normalize_security(nil), do: nil
  defp normalize_security([]), do: nil

  defp normalize_security(security) when is_list(security) do
    if Keyword.keyword?(security) do
      [normalize_security_requirement(security)]
    else
      Enum.map(security, &normalize_security_requirement/1)
    end
  end

  defp normalize_security(%{} = requirement), do: [normalize_security_requirement(requirement)]

  defp normalize_security_requirement(requirement) when is_list(requirement) do
    requirement
    |> Enum.map(fn {name, scopes} -> {to_string(name), normalize_scopes(scopes)} end)
    |> Map.new()
  end

  defp normalize_security_requirement(%{} = requirement) do
    requirement
    |> Enum.map(fn {name, scopes} -> {to_string(name), normalize_scopes(scopes)} end)
    |> Map.new()
  end

  defp normalize_scopes(nil), do: []
  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
  defp normalize_scopes(scope), do: [to_string(scope)]

  defp path_item_operations(%_struct{} = path_item),
    do: path_item |> Map.from_struct() |> path_item_operations()

  defp path_item_operations(%{} = path_item) do
    path_item
    |> Map.take([:get, :put, :post, :delete, :options, :head, :patch, :trace])
    |> Map.values()
    |> Enum.reject(&is_nil/1)
  end

  defp to_open_api_key(:bearer_format), do: "bearerFormat"
  defp to_open_api_key(:open_id_connect_url), do: "openIdConnectUrl"
  defp to_open_api_key(key), do: to_string(key)

  defp blank_to_nil([]), do: nil
  defp blank_to_nil(value), do: value

  defp true_or_nil(true), do: true
  defp true_or_nil(_value), do: nil

  defp maybe_put_atom(map, _key, nil), do: map
  defp maybe_put_atom(map, key, value), do: Map.put(map, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end

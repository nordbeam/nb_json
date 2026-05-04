defmodule NbJson.ValidationTest do
  use ExUnit.Case

  defmodule ApiController do
    use NbJson.Controller

    json_endpoint :create, method: :post, path: "/api/users" do
      params do
        field(:name, :string)
        field(:age, :integer, optional: true)
        field(:active, :boolean, default: true)
        field(:status, enum([:draft, :published]))
        field(:tags, list_of(:integer), optional: true)
        field(:profile, shape(timezone: :string, locale: optional(:string)), optional: true)
        field(:deleted_at, nullable(:datetime), optional: true)
      end

      response 201 do
        data(:id, :uuid)
      end
    end
  end

  test "validates and coerces declared endpoint params" do
    assert {:ok,
            %{
              name: "Ada",
              age: 42,
              active: true,
              status: :published,
              tags: [1, 2],
              profile: %{timezone: "UTC"},
              deleted_at: nil
            }} =
             ApiController.validate_json_params(:create, %{
               "name" => "Ada",
               "age" => "42",
               "status" => "published",
               "tags" => ["1", 2],
               "profile" => %{"timezone" => "UTC"},
               "deleted_at" => ""
             })
  end

  test "returns field-level validation errors" do
    assert {:error,
            %{
              name: ["is required"],
              age: ["must be an integer"],
              status: ["must be one of: draft, published"],
              tags: ["item 1 must be an integer"],
              profile: %{timezone: ["is required"]}
            }} =
             ApiController.validate_json_params(:create, %{
               "age" => "old",
               "status" => "archived",
               "tags" => ["1", "two"],
               "profile" => %{}
             })
  end

  test "reports undeclared endpoints" do
    assert {:error, %{endpoint: ["is not declared"]}} =
             ApiController.validate_json_params(:missing, %{})
  end
end

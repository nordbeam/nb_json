defmodule NbJson.FlopTest do
  use ExUnit.Case

  defmodule UsersController do
    use NbJson.Controller

    json_endpoint :index, method: :get, path: "/api/users" do
      params do
        flop_params(pagination: :all)
      end

      response 200 do
        data(:users, :list)
        flop_meta()
      end
    end
  end

  test "flop_params declares standard query params" do
    endpoint = UsersController.__nb_json_endpoints__().index

    names = Enum.map(endpoint.params, & &1.name)

    assert :page in names
    assert :page_size in names
    assert :limit in names
    assert :offset in names
    assert :first in names
    assert :last in names
    assert :after in names
    assert :before in names
    assert :order_by in names
    assert :order_directions in names
    assert :filters in names
    assert Enum.all?(endpoint.params, &(&1.optional and &1.location == :query))
  end

  test "validates and coerces Flop-compatible params" do
    assert {:ok,
            %{
              page: 2,
              page_size: 25,
              order_by: ["name", "inserted_at"],
              order_directions: [:asc, :desc],
              filters: [%{field: "status", op: "==", value: "active"}]
            }} =
             UsersController.validate_json_params(:index, %{
               "page" => "2",
               "page_size" => "25",
               "order_by" => ["name", "inserted_at"],
               "order_directions" => ["asc", "desc"],
               "filters" => [%{"field" => "status", "op" => "==", "value" => "active"}]
             })
  end

  test "flop_meta declares pagination response metadata" do
    endpoint = UsersController.__nb_json_endpoints__().index
    response = Enum.find(endpoint.responses, &(&1.status == 200))

    assert [%{name: :pagination, optional: true, type: {:shape, fields}}] = response.meta
    assert Keyword.fetch!(fields, :current_page) == :integer
    assert Keyword.fetch!(fields, :has_next_page) == :boolean
    assert Keyword.fetch!(fields, :total_count) == {:optional, :integer}
  end
end

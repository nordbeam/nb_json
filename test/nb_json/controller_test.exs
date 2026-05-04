defmodule NbJson.ControllerTest do
  use ExUnit.Case

  defmodule UserSerializer do
    def serialize(user, _opts) when is_map(user) do
      Map.take(user, [:id, :name])
    end
  end

  defmodule UsersController do
    use NbJson.Controller

    json_endpoint :index, method: :get, path: "/api/users", summary: "List users" do
      params do
        field(:page, :integer, optional: true)
        field(:search, :string, optional: true)
      end

      response 200, description: "Users response" do
        data(:users, list_of(ref(UserSerializer)))
        meta(:pagination, shape(page: :integer, total: :integer))
      end

      error(422, code: :validation_failed)
    end
  end

  test "captures endpoint contracts at compile time" do
    assert %{
             index: %{
               method: "get",
               path: "/api/users",
               params: params,
               responses: responses
             }
           } = UsersController.__nb_json_endpoints__()

    assert Enum.map(params, & &1.name) == [:page, :search]

    assert [
             %{
               kind: :success,
               status: 200,
               data: [%{name: :users}],
               meta: [%{name: :pagination}]
             },
             %{kind: :error, status: 422, code: :validation_failed}
           ] = responses
  end

  test "build_json materializes serializer tuples" do
    payload =
      UsersController.build_json(:index,
        users: {UserSerializer, [%{id: 1, name: "Ada", ignored: true}]},
        meta: %{pagination: %{page: 1, total: 1}}
      )

    assert payload == %{
             data: %{users: [%{id: 1, name: "Ada"}]},
             meta: %{pagination: %{page: 1, total: 1}}
           }
  end
end

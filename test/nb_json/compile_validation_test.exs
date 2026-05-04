defmodule NbJson.CompileValidationTest do
  use ExUnit.Case

  test "duplicate endpoint declarations fail at compile time" do
    assert_compile_error("duplicate json_endpoint :index", """
    json_endpoint :index do
      response 200 do
        data :ok, :boolean
      end
    end

    json_endpoint :index do
      response 200 do
        data :ok, :boolean
      end
    end
    """)
  end

  test "duplicate request params fail at compile time" do
    assert_compile_error("duplicate params field(s) :page", """
    json_endpoint :index do
      params do
        field :page, :integer
        field :page, :string
      end

      response 200 do
        data :ok, :boolean
      end
    end
    """)
  end

  test "path placeholders must have matching path params" do
    assert_compile_error("path \"/api/users/:id\" has placeholder(s) :id", """
    json_endpoint :show, path: "/api/users/:id" do
      response 200 do
        data :ok, :boolean
      end
    end
    """)
  end

  test "path params must appear in the endpoint path" do
    assert_compile_error("declares path param field(s) :user_id", """
    json_endpoint :show, path: "/api/users" do
      params do
        field :user_id, :uuid, location: :path
      end

      response 200 do
        data :ok, :boolean
      end
    end
    """)
  end

  test "invalid param locations fail at compile time" do
    assert_compile_error(":page has :cookie", """
    json_endpoint :index do
      params do
        field :page, :integer, location: :cookie
      end

      response 200 do
        data :ok, :boolean
      end
    end
    """)
  end

  test "duplicate response data and meta fields fail at compile time" do
    assert_compile_error("duplicate response 200 data field(s) :user", """
    json_endpoint :show do
      response 200 do
        data :user, :map
        data :user, :map
      end
    end
    """)

    assert_compile_error("duplicate response 200 meta field(s) :pagination", """
    json_endpoint :index do
      response 200 do
        data :users, :list
        meta :pagination, :map
        meta :pagination, :map
      end
    end
    """)
  end

  test "duplicate response statuses fail at compile time" do
    assert_compile_error("duplicate response status(es) 200", """
    json_endpoint :index do
      response 200 do
        data :users, :list
      end

      response 200 do
        data :users, :list
      end
    end
    """)
  end

  test "endpoints must declare a success response" do
    assert_compile_error("must declare at least one success response", """
    json_endpoint :index do
      error 422
    end
    """)

    assert_compile_error("must declare at least one response", """
    json_endpoint :index do
      params do
        field :page, :integer, optional: true
      end
    end
    """)
  end

  test "invalid HTTP status codes fail at compile time" do
    assert_compile_error("invalid response status 99", """
    json_endpoint :index do
      response 99 do
        data :ok, :boolean
      end
    end
    """)

    assert_compile_error("invalid error status 700", """
    json_endpoint :index do
      response 200 do
        data :ok, :boolean
      end

      error 700
    end
    """)
  end

  test "duplicate shape fields fail at compile time" do
    assert_compile_error("duplicate shape field(s): :name", """
    json_endpoint :create, method: :post do
      params do
        field :profile, shape(name: :string, name: :integer)
      end

      response 201 do
        data :id, :uuid
      end
    end
    """)
  end

  test "action validation can be enabled for controller modules" do
    assert_compile_error(
      "does not define matching controller action",
      """
      use NbJson.Controller, validate_actions: true

      json_endpoint :index do
        response 200 do
          data :ok, :boolean
        end
      end
      """,
      use_controller?: false
    )

    module = unique_module()

    assert [{^module, _binary}] =
             Code.compile_string("""
             defmodule #{inspect(module)} do
               use NbJson.Controller, validate_actions: true

               json_endpoint :index do
                 response 200 do
                   data :ok, :boolean
                 end
               end

               def index(conn, _params), do: conn
             end
             """)
  end

  defp assert_compile_error(expected, body, opts \\ []) do
    module = unique_module()

    use_controller =
      if Keyword.get(opts, :use_controller?, true) do
        "use NbJson.Controller"
      else
        ""
      end

    error =
      assert_raise ArgumentError, fn ->
        Code.compile_string("""
        defmodule #{inspect(module)} do
          #{use_controller}

          #{body}
        end
        """)
      end

    assert Exception.message(error) =~ expected
  end

  defp unique_module do
    Module.concat([
      NbJson.CompileValidationTest.Generated,
      :"Bad#{System.unique_integer([:positive])}"
    ])
  end
end

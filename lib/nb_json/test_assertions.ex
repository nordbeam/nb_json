defmodule NbJson.TestAssertions do
  @moduledoc """
  Test helpers for validating `nb_json` responses against OpenApiSpex specs.

  These helpers intentionally delegate to `OpenApiSpex.TestAssertions` when it
  is available, so production projects use the same validation engine that
  serves and casts the OpenAPI document.
  """

  @open_api_test_assertions Module.concat(["OpenApiSpex", "TestAssertions"])

  @doc """
  Asserts that a `Plug.Conn` response matches the generated operation schema.

  The conn must have passed through `OpenApiSpex.Plug.PutApiSpec`. Pass either
  an explicit operation id or a controller/action pair:

      assert_json_response(conn, MyAppWeb.UserController, :show)
      assert_json_response(conn, "MyAppWeb.UserController.show")
  """
  @spec assert_json_response(Plug.Conn.t(), binary() | nil) :: Plug.Conn.t()
  def assert_json_response(conn, operation_id \\ nil) do
    assertions = @open_api_test_assertions

    if Code.ensure_loaded?(assertions) and
         function_exported?(assertions, :assert_operation_response, 2) do
      apply(assertions, :assert_operation_response, [conn, operation_id])
    else
      raise ArgumentError,
            "OpenApiSpex.TestAssertions is not available. Add {:open_api_spex, \"~> 3.22\"} " <>
              "to test dependencies before using NbJson.TestAssertions."
    end
  end

  @doc """
  Asserts a response by deriving the operation id from a controller/action pair.
  """
  @spec assert_json_response(Plug.Conn.t(), module(), atom()) :: Plug.Conn.t()
  def assert_json_response(conn, controller, action)
      when is_atom(controller) and is_atom(action) do
    operation = NbJson.OpenApi.open_api_operation(controller, action)
    assert_json_response(conn, operation.operationId)
  end
end

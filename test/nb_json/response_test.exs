defmodule NbJson.ResponseTest do
  use ExUnit.Case

  alias NbJson.Response

  test "success envelopes data with top-level meta and links" do
    assert Response.success(users: [%{id: 1}], meta: %{page: 1}, links: %{self: "/api/users"}) ==
             %{
               data: %{users: [%{id: 1}]},
               meta: %{page: 1},
               links: %{self: "/api/users"}
             }
  end

  test "success can render without an envelope" do
    assert Response.success([users: []], envelope: false) == %{users: []}
  end

  test "error creates a standard error object" do
    assert Response.error(:not_found, "User not found") == %{
             error: %{
               code: "not_found",
               message: "User not found",
               status: 404
             }
           }
  end

  test "validation errors accept plain maps" do
    assert Response.validation_error(%{email: ["is invalid"]}) == %{
             error: %{
               code: "validation_failed",
               message: "Validation failed",
               status: 422,
               details: %{email: ["is invalid"]}
             }
           }
  end
end

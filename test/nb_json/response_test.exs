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

  test "success can render a JSON:API resource document" do
    assert Response.success([user: %{id: 1, name: "Ada", email: "ada@example.com"}],
             profile: :json_api,
             type: "users"
           ) == %{
             data: %{
               type: "users",
               id: "1",
               attributes: %{name: "Ada", email: "ada@example.com"}
             }
           }
  end

  test "JSON:API profile renders lists with top-level meta and links" do
    assert Response.success(
             [
               users: [%{id: 1, name: "Ada"}, %{id: 2, name: "Grace"}],
               meta: %{page: 1},
               links: %{self: "/api/users"}
             ],
             profile: :json_api,
             type: "users"
           ) == %{
             data: [
               %{type: "users", id: "1", attributes: %{name: "Ada"}},
               %{type: "users", id: "2", attributes: %{name: "Grace"}}
             ],
             meta: %{page: 1},
             links: %{self: "/api/users"}
           }
  end

  test "JSON:API profile renders relationship linkage" do
    assert Response.success(
             [
               article: %{
                 id: 1,
                 title: "Typed APIs",
                 author: %{id: 2, name: "Ada"},
                 comments: [%{id: 3}, %{id: 4}]
               }
             ],
             profile: :json_api,
             type: "articles",
             relationships: [
               author: [type: "people"],
               comments: [type: "comments"]
             ]
           ) == %{
             data: %{
               type: "articles",
               id: "1",
               attributes: %{title: "Typed APIs"},
               relationships: %{
                 author: %{data: %{type: "people", id: "2"}},
                 comments: %{
                   data: [
                     %{type: "comments", id: "3"},
                     %{type: "comments", id: "4"}
                   ]
                 }
               }
             }
           }
  end

  test "JSON:API profile renders included resources" do
    assert Response.success(
             [
               article: %{id: 1, title: "Typed APIs", author: %{id: 2}},
               included: [people: [id: 2, name: "Ada"]]
             ],
             profile: :json_api,
             type: "articles",
             relationships: [author: "people"]
           ) == %{
             data: %{
               type: "articles",
               id: "1",
               attributes: %{title: "Typed APIs"},
               relationships: %{author: %{data: %{type: "people", id: "2"}}}
             },
             included: [
               %{type: "people", id: "2", attributes: %{name: "Ada"}}
             ]
           }
  end

  test "JSON:API profile rejects multiple primary data assigns" do
    assert_raise ArgumentError, ~r/require one primary data assign/, fn ->
      Response.success([user: %{id: 1}, team: %{id: 2}], profile: :json_api)
    end
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

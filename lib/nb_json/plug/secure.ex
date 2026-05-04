defmodule NbJson.Plug.Secure do
  @moduledoc """
  Convenience plug that runs `NbJson.Plug.Authenticate` and
  `NbJson.Plug.Authorize` in order.

      plug NbJson.Plug.Secure
      plug NbJson.Plug.Validate
  """

  @doc false
  def init(opts), do: Map.new(opts)

  @doc false
  def call(conn, opts) do
    conn = NbJson.Plug.Authenticate.call(conn, opts)

    if halted?(conn) do
      conn
    else
      NbJson.Plug.Authorize.call(conn, opts)
    end
  end

  defp halted?(%{halted: halted}), do: halted
  defp halted?(_conn), do: false
end

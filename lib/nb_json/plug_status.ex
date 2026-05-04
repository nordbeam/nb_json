defmodule NbJson.PlugStatus do
  @moduledoc false

  @reasons %{
    400 => {:bad_request, "Bad request"},
    401 => {:unauthorized, "Unauthorized"},
    403 => {:forbidden, "Forbidden"},
    404 => {:not_found, "Not found"},
    409 => {:conflict, "Conflict"},
    422 => {:unprocessable_entity, "Unprocessable entity"},
    429 => {:too_many_requests, "Too many requests"},
    500 => {:internal_server_error, "Internal server error"}
  }

  def reason_atom(status) do
    case @reasons[status] do
      {atom, _phrase} -> atom
      nil -> nil
    end
  end

  def reason_phrase(status) do
    case @reasons[status] do
      {_atom, phrase} -> phrase
      nil -> nil
    end
  end
end

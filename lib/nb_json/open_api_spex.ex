defmodule NbJson.OpenApiSpex do
  @moduledoc """
  Optional `open_api_spex` bridge for `NbJson.OpenApi`.

  Use this module to expose an `OpenApiSpex.OpenApi` behaviour module from
  `nb_json` controller contracts:

      defmodule MyAppWeb.ApiSpec do
        use NbJson.OpenApiSpex,
          controllers: [MyAppWeb.UserController],
          title: "My API",
          version: "1.0.0"
      end
  """

  @open_api_behaviour Module.concat(["OpenApiSpex", "OpenApi"])

  @doc false
  defmacro __using__(opts) do
    behaviour = @open_api_behaviour

    unless Code.ensure_loaded?(behaviour) do
      raise ArgumentError,
            "NbJson.OpenApiSpex requires open_api_spex. Add " <>
              "{:open_api_spex, \"~> 3.22\"} to your dependencies."
    end

    controllers =
      Keyword.get_lazy(opts, :controllers, fn ->
        raise ArgumentError, "NbJson.OpenApiSpex requires a :controllers option"
      end)

    open_api_opts = Keyword.drop(opts, [:controllers])

    quote do
      @behaviour unquote(behaviour)
      @impl unquote(behaviour)
      def spec do
        NbJson.OpenApi.to_open_api_spex(
          unquote(controllers),
          unquote(Macro.escape(open_api_opts))
        )
      end
    end
  end
end

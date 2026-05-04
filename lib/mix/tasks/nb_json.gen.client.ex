defmodule Mix.Tasks.NbJson.Gen.Client do
  @shortdoc "Generates a TypeScript API client from NbJson controller contracts"

  @moduledoc """
  Generates a TypeScript fetch client from modules that use `NbJson.Controller`.
  The default output is dependency-free; pass `--react-query` to also emit
  TanStack React Query hooks and query option factories.

  ## Usage

      mix nb_json.gen.client MyAppWeb.UserController --output assets/js/api.ts

      mix nb_json.gen.client MyAppWeb.UserController --no-serializer-imports

      mix nb_json.gen.client MyAppWeb.UserController --react-query
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, modules, _invalid} =
      OptionParser.parse(argv,
        switches: [
          output: :string,
          react_query: :boolean,
          serializer_imports: :boolean,
          title: :string
        ],
        aliases: [o: :output]
      )

    if modules == [] do
      Mix.raise("Expected at least one controller module")
    end

    Mix.Task.run("app.start")

    modules = Enum.map(modules, &Module.concat([&1]))
    output = opts[:output] || "assets/js/api.ts"

    generator_opts =
      opts
      |> Keyword.take([:react_query, :serializer_imports])
      |> Keyword.put(:title, opts[:title] || "nb_json API client")

    NbJson.TypeScriptClient.write!(modules, output, generator_opts)
    Mix.shell().info("Generated #{output}")
  end
end

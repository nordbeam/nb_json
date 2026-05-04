defmodule Mix.Tasks.NbJson.Openapi do
  @shortdoc "Generates an OpenAPI document from NbJson controller contracts"

  @moduledoc """
  Generates an OpenAPI document from modules that use `NbJson.Controller`.

  ## Usage

      mix nb_json.openapi MyAppWeb.UserController MyAppWeb.PostController --output priv/openapi.json
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, modules, _invalid} =
      OptionParser.parse(argv,
        switches: [output: :string, title: :string, version: :string],
        aliases: [o: :output]
      )

    Mix.Task.run("app.start")

    modules = Enum.map(modules, &Module.concat([&1]))

    json =
      NbJson.OpenApi.to_json!(modules,
        title: opts[:title] || "JSON API",
        version: opts[:version] || "0.1.0"
      )

    case opts[:output] do
      nil ->
        Mix.shell().info(json)

      output ->
        File.mkdir_p!(Path.dirname(output))
        File.write!(output, json)
        Mix.shell().info("Generated #{output}")
    end
  end
end

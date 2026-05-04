defmodule NbJson.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nordbeam/nb_json"

  def project do
    [
      app: :nb_json,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "NbJson"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {NbJson.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},

      # Optional Phoenix API integrations
      {:phoenix, "~> 1.7", optional: true},
      {:plug, "~> 1.14", optional: true},
      {:ecto, "~> 3.10", optional: true},
      {:open_api_spex, "~> 3.22", optional: true},

      # Test-time nb ecosystem integrations. Runtime integration is dynamic so
      # consuming apps can provide these packages through Hex, GitHub, or path deps.
      {:nb_serializer, github: "nordbeam/nb_serializer", only: [:dev, :test], optional: true},
      {:nb_ts, github: "nordbeam/nb_ts", only: [:dev, :test], optional: true, runtime: false},
      {:nb_routes,
       github: "nordbeam/nb_routes", only: [:dev, :test], optional: true, runtime: false},
      {:nb_flop, github: "nordbeam/nb_flop", only: [:dev, :test], optional: true},

      # Installer and documentation
      {:igniter, "~> 0.7", optional: true, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Phoenix JSON API developer experience for the nb ecosystem: typed endpoint contracts,
    response envelopes, serializer-aware rendering, and OpenAPI metadata.
    """
  end

  defp package do
    [
      name: "nb_json",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/nb_json"
      },
      maintainers: ["nordbeam"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end

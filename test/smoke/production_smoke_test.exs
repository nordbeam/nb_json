defmodule NbJson.ProductionSmokeTest do
  use ExUnit.Case

  @moduletag :production_smoke
  @moduletag timeout: 240_000

  defmodule ClientController do
    use NbJson.Controller

    json_endpoint :index, method: :get, path: "/api/users/:account_id" do
      params do
        field(:account_id, :uuid, location: :path)
        flop_params(pagination: :all)
      end

      response 200 do
        data(:users, :list)
        flop_meta()
      end
    end

    json_endpoint :create, method: :post, path: "/api/users" do
      params do
        field(:name, :string)
        field(:active, :boolean, default: true)
        field(:profile, shape(timezone: :string, locale: optional(:string)), optional: true)
      end

      response 201 do
        data(:id, :uuid)
      end
    end

    json_endpoint :article, method: :get, path: "/api/articles/:id" do
      params do
        field(:id, :uuid, location: :path)
      end

      response 200,
        profile: :json_api,
        type: "articles",
        relationships: [author: [type: "people"]] do
        data(:article, :map)
      end
    end
  end

  test "a fresh Phoenix API project can install and compile nb_json" do
    app_dir = temp_path("nb_json_fresh_phx")
    nb_json_root = File.cwd!()
    Process.put(:nb_json_smoke_app_dir, app_dir)
    File.rm_rf!(app_dir)
    File.mkdir_p!(Path.dirname(app_dir))

    run!("mix", [
      "phx.new",
      app_dir,
      "--no-ecto",
      "--no-html",
      "--no-assets",
      "--no-dashboard",
      "--no-mailer",
      "--no-gettext",
      "--no-live",
      "--no-install",
      "--no-version-check",
      "--no-agents-md"
    ])

    inject_dep!(Path.join(app_dir, "mix.exs"), "{:nb_json, path: #{inspect(nb_json_root)}}")
    inject_igniter_dep!(Path.join(app_dir, "mix.exs"))

    run!("mix", ["deps.get"], cd: app_dir)
    run!("mix", ["nb_json.install", "--yes"], cd: app_dir)
    run!("mix", ["deps.get"], cd: app_dir)
    run!("mix", ["compile", "--warnings-as-errors"], cd: app_dir)

    api_spec = app_dir |> Path.join("lib/**/*api_spec.ex") |> Path.wildcard() |> List.first()

    assert api_spec
    assert File.read!(api_spec) =~ "use NbJson.OpenApiSpex"
    assert File.read!(Path.join(app_dir, "config/config.exs")) =~ "config :nb_json"
    assert File.read!(Path.join(app_dir, "mix.exs")) =~ ":open_api_spex"
  after
    if app_dir = Process.get(:nb_json_smoke_app_dir) do
      File.rm_rf(app_dir)
    end
  end

  test "generated TypeScript client compiles under strict TypeScript" do
    output_dir = temp_path("nb_json_ts_compile")
    Process.put(:nb_json_smoke_ts_dir, output_dir)
    File.rm_rf!(output_dir)
    File.mkdir_p!(output_dir)

    api_path = Path.join(output_dir, "api.ts")
    NbJson.TypeScriptClient.write!(ClientController, api_path, serializer_imports: false)

    run!(
      "npx",
      [
        "--yes",
        "--package",
        "typescript@5.9.3",
        "tsc",
        "--noEmit",
        "--strict",
        "--target",
        "ES2020",
        "--module",
        "ESNext",
        "--lib",
        "ES2020,DOM",
        api_path
      ],
      cd: output_dir
    )
  after
    if output_dir = Process.get(:nb_json_smoke_ts_dir) do
      File.rm_rf(output_dir)
    end
  end

  defp temp_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end

  defp inject_igniter_dep!(mix_exs) do
    unless File.read!(mix_exs) =~ "{:igniter," do
      inject_dep!(mix_exs, "{:igniter, \"~> 0.7\", only: [:dev, :test], runtime: false}")
    end
  end

  defp inject_dep!(mix_exs, dep) do
    contents = File.read!(mix_exs)

    contents =
      Regex.replace(~r/defp deps do\s*\n\s*\[/, contents, fn match ->
        match <> "\n      #{dep},"
      end)

    File.write!(mix_exs, contents)
  end

  defp run!(command, args, opts \\ []) do
    {output, status} =
      System.cmd(command, args,
        cd: Keyword.get(opts, :cd, File.cwd!()),
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}]
      )

    assert status == 0, """
    Command failed with status #{status}: #{command} #{Enum.join(args, " ")}

    #{output}
    """

    output
  end
end

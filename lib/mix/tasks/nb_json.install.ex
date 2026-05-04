if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.NbJson.Install do
    @shortdoc "Installs NbJson for Phoenix JSON APIs"

    @moduledoc """
    Installs and configures NbJson in a Phoenix application.

    ## Usage

        mix igniter.install nb_json --with-typescript

    ## Options

      * `--with-typescript` - Compose `nb_ts.install`
      * `--with-open-api-spex` - Add OpenApiSpex integration dependencies
      * `--camelize-props` - Configure JSON keys for JavaScript clients
      * `--yes` - Skip dependency confirmation prompts
    """

    use Igniter.Mix.Task

    @task_group :nb
    @forwarded_child_flags ~w(--yes)
    @schema [
      with_typescript: :boolean,
      with_open_api_spex: :boolean,
      camelize_props: :boolean,
      yes: :boolean
    ]

    @defaults [
      with_typescript: false,
      with_open_api_spex: true,
      camelize_props: true,
      yes: false
    ]

    @impl Igniter.Mix.Task
    def info(argv, _parent) do
      options = installer_options(argv)

      %Igniter.Mix.Task.Info{
        group: @task_group,
        schema: @schema,
        defaults: @defaults,
        positional: [],
        composes: composed_tasks(options),
        adds_deps: optional_dependency_specs(options),
        example: "mix igniter.install nb_json --with-typescript"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      with_typescript = igniter.args.options[:with_typescript] || false
      with_open_api_spex = igniter.args.options[:with_open_api_spex] != false
      camelize_props = igniter.args.options[:camelize_props] != false

      igniter
      |> Igniter.Project.Formatter.import_dep(:nb_json)
      |> maybe_import_open_api_spex(with_open_api_spex)
      |> ensure_optional_dependencies_available(with_typescript, with_open_api_spex)
      |> add_configuration(camelize_props)
      |> maybe_create_api_spec(with_open_api_spex)
      |> maybe_setup_nb_ts(with_typescript)
      |> print_next_steps(with_typescript, with_open_api_spex)
    end

    @doc false
    def installer_options(argv) do
      group = Igniter.Util.Info.group(%Igniter.Mix.Task.Info{group: @task_group}, task_name())

      {options, _argv, _invalid} =
        argv
        |> Igniter.Util.Info.args_for_group(group)
        |> OptionParser.parse(switches: @schema)

      Keyword.merge(@defaults, options)
    end

    @doc false
    def composed_tasks(options) do
      if options[:with_typescript], do: ["nb_ts.install"], else: []
    end

    @doc false
    def optional_dependency_specs(options, installed_deps \\ []) do
      options = Keyword.merge(@defaults, options)

      []
      |> maybe_add_optional_dep(
        options[:with_typescript],
        installed_deps,
        {:nb_ts, github: "nordbeam/nb_ts"}
      )
      |> maybe_add_optional_dep(
        options[:with_open_api_spex],
        installed_deps,
        {:open_api_spex, "~> 3.22"}
      )
    end

    defp ensure_optional_dependencies_available(igniter, with_typescript, with_open_api_spex) do
      requested_specs =
        optional_dependency_specs(
          [
            with_typescript: with_typescript,
            with_open_api_spex: with_open_api_spex
          ],
          []
        )

      igniter =
        Enum.reduce(requested_specs, igniter, fn spec, igniter ->
          Igniter.Project.Deps.add_dep(igniter, spec, on_exists: :skip, yes?: true)
        end)

      if requested_specs == [] do
        igniter
      else
        Igniter.apply_and_fetch_dependencies(igniter,
          operation: "installing nb_json companion dependencies",
          yes: igniter.args.options[:yes] || false
        )
      end
    end

    defp add_configuration(igniter, camelize_props) do
      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        :nb_json,
        [:camelize_props],
        camelize_props
      )
    end

    defp maybe_setup_nb_ts(igniter, true),
      do: compose_installer_task(igniter, "nb_ts.install", [])

    defp maybe_setup_nb_ts(igniter, _), do: igniter

    defp maybe_import_open_api_spex(igniter, true),
      do: Igniter.Project.Formatter.import_dep(igniter, :open_api_spex)

    defp maybe_import_open_api_spex(igniter, _), do: igniter

    defp maybe_create_api_spec(igniter, false), do: igniter

    defp maybe_create_api_spec(igniter, true) do
      api_spec_module = Igniter.Libs.Phoenix.web_module_name(igniter, "ApiSpec")

      Igniter.Project.Module.create_module(
        igniter,
        api_spec_module,
        api_spec_content(api_spec_module)
      )
    end

    @doc false
    def api_spec_content(api_spec_module) do
      web_module =
        api_spec_module
        |> Module.split()
        |> Enum.drop(-1)
        |> Module.concat()

      """
      @moduledoc \"\"\"
      OpenAPI specification for this JSON API.

      Add controllers that use `NbJson.Controller` to the `controllers:` list.
      \"\"\"

      use NbJson.OpenApiSpex,
        controllers: [
          # #{inspect(web_module)}.UserController
        ],
        title: \"JSON API\",
        version: \"1.0.0\",
        security_schemes: [
          bearerAuth: :bearer
        ]
      """
    end

    defp print_next_steps(igniter, with_typescript, with_open_api_spex) do
      ts_note =
        if with_typescript do
          "- TypeScript generation is enabled through nb_ts."
        else
          "- Add --with-typescript when you want generated API/client types."
        end

      open_api_note =
        if with_open_api_spex do
          """
          - Add your controllers to `MyAppWeb.ApiSpec`.
          - Put the OpenApiSpex spec in your API pipeline:

              plug OpenApiSpex.Plug.PutApiSpec, module: MyAppWeb.ApiSpec

          - Validate requests inside controllers that use `NbJson.Controller`:

              plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
              plug NbJson.Plug.Validate

          - Serve the spec from a route that passes through the API pipeline:

              get "/openapi", OpenApiSpex.Plug.RenderSpec, []
          """
        else
          "- Add --with-open-api-spex when you want OpenApiSpex serving and validation."
        end

      Igniter.add_notice(igniter, """
      NbJson is configured.

      Next steps:
      - Add `use NbJson.Controller` to API controllers.
      - Declare `json_endpoint` blocks beside controller actions.
      - Use `render_json(conn, :action, assigns)` for envelope rendering.
      - Generate OpenAPI with `mix nb_json.openapi MyAppWeb.UserController`.
      #{open_api_note}
      #{ts_note}
      """)
    end

    defp maybe_add_optional_dep(deps, false, _installed_deps, _spec), do: deps

    defp maybe_add_optional_dep(deps, true, installed_deps, spec) do
      if dep_name(spec) in installed_deps, do: deps, else: [spec | deps]
    end

    defp task_name do
      Mix.Task.task_name(__MODULE__)
    end

    defp compose_installer_task(igniter, task, args) do
      Igniter.compose_task(igniter, task, args ++ forwarded_global_argv(igniter.args.argv_flags))
    end

    @doc false
    def forwarded_global_argv(argv_flags),
      do: Enum.filter(argv_flags, &(&1 in @forwarded_child_flags))

    defp dep_name({name, _requirement}), do: name
    defp dep_name({name, _requirement, _opts}), do: name
  end
end

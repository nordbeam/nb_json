defmodule Mix.Tasks.NbJson.InstallTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.NbJson.Install

  describe "info/2" do
    test "defaults to OpenApiSpex integration for production API validation" do
      options = Install.installer_options([])

      assert Install.optional_dependency_specs(options, []) == [
               {:open_api_spex, "~> 3.22"}
             ]
    end

    test "declares optional deps for requested TypeScript and OpenApiSpex integrations" do
      options = Install.installer_options(["--with-typescript"])

      assert Install.info(["--with-typescript"], nil).composes == ["nb_ts.install"]

      assert Install.optional_dependency_specs(options, []) == [
               {:open_api_spex, "~> 3.22"},
               {:nb_ts, github: "nordbeam/nb_ts"}
             ]
    end

    test "allows opting out of OpenApiSpex dependency setup" do
      options = Install.installer_options(["--no-with-open-api-spex", "--with-typescript"])

      assert Install.optional_dependency_specs(options, []) == [
               {:nb_ts, github: "nordbeam/nb_ts"}
             ]
    end

    test "parses grouped igniter flags for shared nb task namespaces" do
      options = Install.installer_options(["--nb.with-typescript"])

      assert Install.optional_dependency_specs(options, []) == [
               {:open_api_spex, "~> 3.22"},
               {:nb_ts, github: "nordbeam/nb_ts"}
             ]
    end

    test "skips already installed optional dependencies" do
      options = Install.installer_options(["--with-typescript"])

      assert Install.optional_dependency_specs(options, [:open_api_spex, :nb_ts]) == []

      assert Install.optional_dependency_specs(options, [:open_api_spex]) == [
               {:nb_ts, github: "nordbeam/nb_ts"}
             ]
    end
  end

  describe "api_spec_content/1" do
    test "generates an OpenApiSpex bridge module body with production defaults" do
      content = Install.api_spec_content(MyAppWeb.ApiSpec)

      assert content =~ "use NbJson.OpenApiSpex"
      assert content =~ "# MyAppWeb.UserController"
      assert content =~ "security_schemes:"
      assert content =~ "bearerAuth: :bearer"
    end
  end

  describe "forwarded_global_argv/1" do
    test "keeps only child-safe confirmation flags" do
      assert Install.forwarded_global_argv([
               "--yes",
               "--verbose",
               "--only",
               "dev",
               "--with-typescript"
             ]) == ["--yes"]
    end
  end
end

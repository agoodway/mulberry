defmodule Mulberry.MixProject do
  use Mix.Project

  @source_url "https://github.com/agoodway/mulberry"
  @version "0.0.1"

  def project do
    [
      app: :mulberry,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  def package do
    [
      description: "An AI Library",
      maintainers: ["Thomas Brewer"],
      contributors: ["Thomas Brewer"],
      licenses: ["MIT"],
      links: %{
        GitHub: @source_url
      }
    ]
  end

  defp docs do
    [
      extras: [
        LICENSE: [title: "License"],
        "README.md": [title: "Readme"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      api_reference: false,
      formatters: ["html"]
    ]
  end
end

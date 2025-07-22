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
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      preferred_cli_env: [
        check: :test,
        "check.doctor": :dev,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],
      test_coverage: [tool: ExCoveralls],
      test_paths: ["test"],
      test_pattern: "*_test.exs"
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
      {:floki, "~> 0.38.0"},
      {:req, "~> 0.5.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:langchain, "0.3.0-rc.0"},
      {:html2markdown, github: "agoodway/html2markdown", branch: "main"},
      {:flamel, github: "themusicman/flamel", branch: "main"},
      {:text_chunker, "~> 0.3.0"},
      {:tokenizers, "~> 0.5.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:rambo, "~> 0.3"},
      {:mime, "~> 2.0"},
      {:tesseract_ocr, github: "agoodway/tesseract-ocr-elixir", branch: "master"},
      {:playwright, "~> 1.49.1-alpha.2"},
      {:doctor, "~> 0.21.0", only: :dev, runtime: false},
      {:mimic, "~> 1.10", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:faker, "~> 0.18", only: :test}
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

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "credo list --format=oneline",
        "cmd MIX_ENV=dev mix doctor",
        "test",
        "coveralls"
      ],
      "check.coverage": [
        "coveralls.html"
      ]
    ]
  end
end

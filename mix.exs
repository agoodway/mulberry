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
      {:floki, "~> 0.36.0"},
      {:req, "~> 0.5.0"},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false},
      {:langchain, "0.3.0-rc.0"},
      {:html2markdown, github: "agoodway/html2markdown", branch: "main"},
      {:flamel, github: "themusicman/flamel", branch: "main"},
      {:text_chunker, "~> 0.3.0"},
      {:tokenizers, "~> 0.3.0"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:rambo, "~> 0.3"},
      {:mime, "~> 2.0"},
      {:tesseract_ocr, github: "agoodway/tesseract-ocr-elixir", branch: "master"},
      {:playwright, "~> 1.44.0-alpha.3"}
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

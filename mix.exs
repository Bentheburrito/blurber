defmodule Blurber.MixProject do
  use Mix.Project

  def project do
    [
      app: :blurber,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Blurber.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nostrum, github: "Kraigie/nostrum", override: true},
      {:nosedrum, path: "../../Nostrum/nosedrum"},
      {:dotenv_parser, "~> 1.2"},
      {:planetside_api, "~> 0.3.0"}
    ]
  end
end

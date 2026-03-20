defmodule Baklava.MixProject do
  use Mix.Project

  def project do
    [
      app: :baklava,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Baklava.CLI],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Baklava.Application, []}
    ]
  end

  defp deps do
    []
  end
end

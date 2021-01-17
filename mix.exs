defmodule Gambia.MixProject do
  use Mix.Project

  def project do
    [
      app: :gambia,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Gambia.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bento, "~> 0.9"},
      {:magnet, "~> 0.0.1"},
      {:ecto_sql, "~> 3.0"}
    ]
  end
end

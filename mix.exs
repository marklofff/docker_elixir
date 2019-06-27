defmodule Docker.Mixfile do
  use Mix.Project

  def project do
    [app: :docker_elixir,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: "Api wrapper for Docker API in Elixir",
     package: package(),
     deps: deps()]
  end

  def package do
    [
      maintainers: ["Aiman"],
      licenses: ["GPL"],
      links: %{"Github" => "https://github.com/Hinsei/docker_elixir.git", branch: "feat/mass_moving"}
    ]
  end
  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :httpoison]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:jason, "~> 1.1"},
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:httpoison, "~> 1.4"}
    ]
  end
end

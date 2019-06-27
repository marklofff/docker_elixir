defmodule Docker.Application do
  use Application
  @moduledoc """
    This is the core Docker Application
  """

  def start(_type, _args) do
    Application.ensure_all_started(:httpoison)
  end
end

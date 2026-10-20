defmodule HoloChat.Release do
  @moduledoc """
  Operator tasks for a release, where Mix isn't installed. Run them with
  `bin/migrate` and `bin/admin`, or with `bin/holo_chat eval`:

      bin/holo_chat eval 'HoloChat.Release.migrate()'
      bin/holo_chat eval 'HoloChat.Release.grant_admin("alice")'
  """

  alias HoloChat.Accounts

  @app :holo_chat

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Makes the user an admin, like `mix holo_chat.admin grant`. Raises for unknown users.
  """
  def grant_admin(username), do: set_admin(username, true)

  @doc """
  Takes admin rights away, like `mix holo_chat.admin revoke`. Raises for unknown users.
  """
  def revoke_admin(username), do: set_admin(username, false)

  defp set_admin(username, admin?) do
    load_app()

    # Starts only the repo (not the endpoint or the assistant), unless it already runs.
    {:ok, result, _} =
      Ecto.Migrator.with_repo(HoloChat.Repo, fn _repo -> Accounts.set_admin(username, admin?) end)

    case result do
      {:ok, user} when user.is_admin -> IO.puts("#{user.username} is now an admin.")
      {:ok, user} -> IO.puts("#{user.username} is no longer an admin.")
      {:error, :not_found} -> raise ~s(No user named "#{username}".)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

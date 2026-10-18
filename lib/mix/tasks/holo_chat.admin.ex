defmodule Mix.Tasks.HoloChat.Admin do
  @shortdoc "Grants or revokes admin rights"

  @moduledoc """
  Grants or revokes admin rights for a user.

      $ mix holo_chat.admin grant USERNAME
      $ mix holo_chat.admin revoke USERNAME

  Admins can configure the AI assistant at `/admin/assistant`.
  """

  use Mix.Task
  use Boundary, classify_to: HoloChat

  alias HoloChat.Accounts

  @requirements ["app.start"]

  @impl Mix.Task
  def run([action, username]) when action in ["grant", "revoke"] do
    case Accounts.set_admin(username, action == "grant") do
      {:ok, user} when user.is_admin -> Mix.shell().info("#{user.username} is now an admin.")
      {:ok, user} -> Mix.shell().info("#{user.username} is no longer an admin.")
      {:error, :not_found} -> Mix.raise(~s(No user named "#{username}".))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix holo_chat.admin grant|revoke USERNAME")
  end
end

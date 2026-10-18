defmodule HoloChatWeb.AvatarController do
  use HoloChatWeb, :controller

  alias HoloChat.Avatars

  # Avatars are immutable (a new upload gets a new id), so browsers may cache
  # them forever.
  def show(conn, %{"id" => id}) do
    case Avatars.get_avatar(id) do
      nil ->
        send_resp(conn, 404, "Not found")

      avatar ->
        conn
        |> put_resp_content_type(avatar.content_type, nil)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, avatar.data)
    end
  end
end

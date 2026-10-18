defmodule HoloChatWeb.AvatarControllerTest do
  use HoloChatWeb.ConnCase, async: true

  import HoloChat.AvatarFixtures

  alias HoloChat.Avatars

  test "serves an avatar as a cacheable JPEG", %{conn: conn} do
    {:ok, avatar} = Avatars.create_avatar(image_binary(32, 32, {1, 2, 3}))

    conn = get(conn, ~p"/avatars/#{avatar.id}")

    assert response(conn, 200) == avatar.data
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "answers 404 for unknown and malformed ids", %{conn: conn} do
    assert conn |> get(~p"/avatars/#{Ecto.UUID.generate()}") |> response(404)
    assert conn |> get("/avatars/not-a-uuid") |> response(404)
  end
end

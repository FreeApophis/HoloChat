defmodule HoloChatWeb.ChatModerationTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures

  defp as(scope), do: build_conn_with_unique_ip() |> log_in_user(scope.user)

  describe "deleting messages" do
    test "game masters delete messages in their room, for everyone",
         %{conn: conn} do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      message = message_fixture(user_scope_fixture(), room.name, %{"body" => "Rude words"})
      {:ok, watcher, _html} = live(conn, ~p"/rooms/#{room.name}")
      {:ok, view, _html} = live(as(gm), ~p"/rooms/#{room.name}")

      view |> element("#delete-message-#{message.id}") |> render_click()

      refute has_element?(view, "#messages-#{message.id}")
      refute has_element?(watcher, "#messages-#{message.id}")

      {:ok, reloaded, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{room.name}")
      refute has_element?(reloaded, "#messages-#{message.id}")
    end

    test "moderators delete messages in any room, even rooms nobody runs" do
      chat_room = unique_room()
      message = message_fixture(user_scope_fixture(), chat_room)
      {:ok, view, _html} = live(as(role_scope_fixture(:moderator)), ~p"/rooms/#{chat_room}")

      view |> element("#delete-message-#{message.id}") |> render_click()

      refute has_element?(view, "#messages-#{message.id}")
    end

    test "players get no delete buttons, not even for their own messages" do
      player = user_scope_fixture()
      room = roleplay_room_fixture(user_scope_fixture())
      message = message_fixture(player, room.name)

      {:ok, view, _html} = live(as(player), ~p"/rooms/#{room.name}")

      assert has_element?(view, "#messages-#{message.id}")
      refute has_element?(view, "#delete-message-#{message.id}")
    end
  end
end

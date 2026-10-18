defmodule HoloChatWeb.ChatLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures

  alias HoloChat.Chat

  @message_items "#messages > div[id^='messages-']:not(#messages-empty)"

  describe "as a guest" do
    test "shows the lobby with its history", %{conn: conn} do
      message = message_fixture(user_scope_fixture(), "lobby", %{"body" => "earlier"})

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#room-title", "lobby")
      assert has_element?(view, "#messages-#{message.id}", "earlier")
    end

    test "can read live messages but not post", %{conn: conn} do
      room = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      refute has_element?(view, "#message-form")
      assert has_element?(view, "#guest-notice a[href='/users/log-in']")
      assert has_element?(view, "#guest-notice a[href='/users/register']")

      message_fixture(user_scope_fixture(), room, %{"body" => "posted by a member"})
      assert has_element?(view, @message_items, "posted by a member")
    end

    test "sees login and register links in the header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#login-link")
      assert has_element?(view, "#register-link")
      refute has_element?(view, "#current-username")
    end

    test "cannot post by sending the event anyway", %{conn: conn} do
      room = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      render_hook(view, "send", %{"message" => %{"body" => "sneaky"}})

      assert Chat.list_recent_messages(room) == []
    end
  end

  describe "as a logged-in user" do
    setup :register_and_log_in_user

    test "posts under their username and keeps the composer ready",
         %{conn: conn, user: user} do
      room = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      refute has_element?(view, "#message-form input[name='message[username]']")

      view
      |> form("#message-form", message: %{body: "hello there"})
      |> render_submit()

      assert has_element?(view, @message_items, "hello there")
      assert has_element?(view, @message_items, user.username)
      refute has_element?(view, "#message-form input[name='message[body]'][value]")
    end

    test "cannot post under another name", %{conn: conn, user: user} do
      room = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      render_hook(view, "send", %{"message" => %{"body" => "hi", "username" => "mallory"}})

      assert [%{username: username}] = Chat.list_recent_messages(room)
      assert username == user.username
    end

    test "sees messages from other users live", %{conn: conn} do
      room = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      {:ok, other, _html} =
        build_conn_with_unique_ip() |> log_in_user(user_fixture()) |> live(~p"/rooms/#{room}")

      other
      |> form("#message-form", message: %{body: "from someone else"})
      |> render_submit()

      assert has_element?(view, @message_items, "from someone else")
    end

    test "a blank message is not sent", %{conn: conn} do
      room = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      view
      |> form("#message-form", message: %{body: "   "})
      |> render_submit()

      refute has_element?(view, @message_items)
      assert Chat.list_recent_messages(room) == []
    end
  end

  test "timestamps carry the exact instant for local formatting in the browser", %{conn: conn} do
    room = unique_room()
    message = message_fixture(user_scope_fixture(), room)

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

    # The browser hook reads `datetime` and owns the element's text from then on.
    assert has_element?(
             view,
             "#messages-#{message.id} time#message-time-#{message.id}" <>
               "[datetime='#{DateTime.to_iso8601(message.inserted_at)}']" <>
               "[phx-hook][phx-update='ignore']"
           )
  end

  test "messages stay in their room", %{conn: conn} do
    room = unique_room()
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

    message_fixture(user_scope_fixture(), unique_room(), %{"body" => "elsewhere only"})

    refute has_element?(view, @message_items, "elsewhere only")
  end

  test "switching rooms normalizes the name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#room-form", room: %{name: "#Elixir Fans!"})
    |> render_submit()

    # Switching stays in the same LiveView, so per-tab state (unread rooms) survives.
    assert_patch(view, ~p"/rooms/elixir-fans")
    assert has_element?(view, "#room-title", "elixir-fans")
  end

  test "an invalid room in the URL redirects to the lobby", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/rooms/Not_Valid")
  end
end

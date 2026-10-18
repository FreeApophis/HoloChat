defmodule HoloChatWeb.ChatRoomsTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChatWeb.Presence

  @message_items "#messages > div[id^='messages-']:not(#messages-empty)"

  setup do
    Presence.subscribe_rooms()
    on_exit(&await_presence_fetchers/0)
    %{scope: user_scope_fixture()}
  end

  describe "room list" do
    test "shows the lobby first, then rooms by recent activity", %{conn: conn, scope: scope} do
      [older, newer, current] = [unique_room(), unique_room(), unique_room()]
      message_fixture(scope, older)
      message_fixture(scope, newer)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{current}")

      # Other async tests' rooms may show up too, so compare relative order.
      ids = room_link_ids(view)
      ours = ["room-link-#{newer}", "room-link-#{older}"]
      assert hd(ids) == "room-link-lobby"
      assert Enum.filter(ids, &(&1 in ours)) == ours

      assert has_element?(view, "#room-link-#{current}[aria-current='page']")
      refute has_element?(view, "#room-link-#{older}[aria-current]")
    end

    test "adds a room when it gets its first message", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{unique_room()}")
      new_room = unique_room()

      message_fixture(scope, new_room)

      assert has_element?(view, "#room-link-#{new_room}")
    end

    test "shows how many people are in each room", %{conn: conn} do
      busy = unique_room()
      join(busy)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{unique_room()}")
      assert has_element?(view, "#room-online-#{busy}", "1")

      join(busy)
      await_presence(%{room: busy})
      assert has_element?(view, "#room-online-#{busy}", "2")
    end
  end

  describe "unread rooms" do
    test "marks rooms with new messages until you visit them", %{conn: conn, scope: scope} do
      other = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{unique_room()}")

      message_fixture(scope, other, %{"body" => "while you were away"})
      assert has_element?(view, "#room-unread-#{other}")

      view |> element("#room-link-#{other}") |> render_click()

      assert_patch(view, ~p"/rooms/#{other}")
      refute has_element?(view, "#room-unread-#{other}")
      assert has_element?(view, @message_items, "while you were away")
    end

    test "never marks the room you are in", %{conn: conn, scope: scope} do
      room = unique_room()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      message_fixture(scope, room)

      refute has_element?(view, "#room-unread-#{room}")
    end
  end

  describe "switching rooms" do
    test "shows the new room's messages and stops the old room's", %{conn: conn, scope: scope} do
      [from, to] = [unique_room(), unique_room()]
      message_fixture(scope, to, %{"body" => "already here"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{from}")

      view |> element("#room-link-#{to}") |> render_click()
      assert has_element?(view, "#room-title", to)
      assert has_element?(view, @message_items, "already here")

      message_fixture(scope, from, %{"body" => "left behind"})
      message_fixture(scope, to, %{"body" => "new in this room"})

      refute has_element?(view, @message_items, "left behind")
      assert has_element?(view, @message_items, "new in this room")
    end

    test "moves your presence to the new room", %{conn: conn, scope: scope} do
      [from, to] = [unique_room(), unique_room()]
      message_fixture(scope, to)
      {:ok, mover, _html} = live(conn, ~p"/rooms/#{from}")
      {:ok, watcher, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{unique_room()}")

      mover |> element("#room-link-#{to}") |> render_click()
      await_presence(%{room: to})

      assert has_element?(watcher, "#room-online-#{to}", "1")
      refute has_element?(watcher, "#room-online-#{from}")
    end
  end

  defp join(room) do
    {:ok, view, _html} =
      build_conn_with_unique_ip() |> log_in_user(user_fixture()) |> live(~p"/rooms/#{room}")

    view
  end

  defp room_link_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#room-list a")
    |> LazyHTML.attribute("id")
  end
end

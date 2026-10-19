defmodule HoloChatWeb.ChatTabsTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChatWeb.Presence

  setup do
    on_exit(&await_presence_fetchers/0)
    %{scope: user_scope_fixture()}
  end

  test "opens the lobby and the current room as tabs", %{conn: conn} do
    room = unique_room()
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

    assert tab_ids(view) == ["room-tab-lobby", "room-tab-#{room}"]
    assert has_element?(view, "#room-tab-#{room} a[aria-current='page']")
    refute has_element?(view, "#room-tab-lobby a[aria-current]")
  end

  test "rooms you switch to open in a new tab, keeping the old one", %{conn: conn, scope: scope} do
    [from, to] = [unique_room(), unique_room()]
    message_fixture(scope, to)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{from}")

    view |> element("#room-link-#{to}") |> render_click()

    assert_patch(view, ~p"/rooms/#{to}")
    assert tab_ids(view) == ["room-tab-lobby", "room-tab-#{from}", "room-tab-#{to}"]

    view |> element("#room-tab-#{from} a") |> render_click()

    assert_patch(view, ~p"/rooms/#{from}")
    assert has_element?(view, "#room-title", from)
    assert length(tab_ids(view)) == 3
  end

  test "joining a room by name opens a tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rooms/lobby")
    room = unique_room()

    view |> form("#room-form", room: %{name: room}) |> render_submit()

    assert_patch(view, ~p"/rooms/#{room}")
    assert tab_ids(view) == ["room-tab-lobby", "room-tab-#{room}"]
  end

  test "the room browser offers only rooms", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rooms/lobby")

    assert has_element?(view, "#room-browser #room-list")
    refute has_element?(view, "#room-browser a[href='/roleplay']")
  end

  test "the lobby tab cannot be closed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rooms/#{unique_room()}")

    refute has_element?(view, "#close-tab-lobby")
  end

  test "closing another tab keeps you where you are", %{conn: conn} do
    [first, second] = [unique_room(), unique_room()]
    {:ok, view, _html} = live(conn, ~p"/rooms/#{first}")
    view |> form("#room-form", room: %{name: second}) |> render_submit()

    view |> element("#close-tab-#{first}") |> render_click()

    assert tab_ids(view) == ["room-tab-lobby", "room-tab-#{second}"]
    assert has_element?(view, "#room-title", second)
  end

  test "closing the current tab moves to the tab on its left", %{conn: conn} do
    [first, second] = [unique_room(), unique_room()]
    {:ok, view, _html} = live(conn, ~p"/rooms/#{first}")
    view |> form("#room-form", room: %{name: second}) |> render_submit()

    view |> element("#close-tab-#{second}") |> render_click()

    assert_patch(view, ~p"/rooms/#{first}")
    assert tab_ids(view) == ["room-tab-lobby", "room-tab-#{first}"]
  end

  test "marks open tabs with new messages until you visit them", %{conn: conn, scope: scope} do
    [other, current] = [unique_room(), unique_room()]
    {:ok, view, _html} = live(conn, ~p"/rooms/#{other}")
    view |> form("#room-form", room: %{name: current}) |> render_submit()

    message_fixture(scope, other)
    assert has_element?(view, "#tab-unread-#{other}")

    view |> element("#room-tab-#{other} a") |> render_click()
    refute has_element?(view, "#tab-unread-#{other}")
  end

  test "shows how many people are in each open room", %{conn: conn} do
    busy = unique_room()
    Presence.subscribe_rooms()
    {:ok, view, _html} = live(conn, ~p"/rooms/#{busy}")
    await_presence(%{room: busy})

    assert has_element?(view, "#tab-online-#{busy}", "1")
  end

  describe "remembering tabs" do
    test "tells the browser which tabs are open", %{conn: conn} do
      [first, second] = [unique_room(), unique_room()]
      {:ok, view, _html} = live(conn, ~p"/rooms/#{first}")

      view |> form("#room-form", room: %{name: second}) |> render_submit()

      assert_push_event(view, "chat:tabs", %{rooms: ["lobby", ^first, ^second]})
    end

    test "restores the tabs the browser remembers", %{conn: conn} do
      [saved, current] = [unique_room(), unique_room()]
      {:ok, view, _html} = live(conn, ~p"/rooms/#{current}")

      view
      |> element("#room-tabs")
      |> render_hook("restore_tabs", %{"rooms" => ["lobby", saved, "Not Valid!"]})

      assert tab_ids(view) == ["room-tab-lobby", "room-tab-#{saved}", "room-tab-#{current}"]
      assert has_element?(view, "#room-title", current)
    end
  end

  defp tab_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#room-tabs > [id^='room-tab-']")
    |> LazyHTML.attribute("id")
  end
end

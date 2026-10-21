defmodule HoloChatWeb.RoomListLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChat.Rooms
  alias HoloChatWeb.Presence

  setup do
    Presence.subscribe_rooms()
    on_exit(&await_presence_fetchers/0)
    %{gm: user_scope_fixture()}
  end

  test "shows the language every room with a record speaks", %{conn: conn, gm: gm} do
    german = roleplay_room_fixture(gm)
    english = roleplay_room_fixture(gm)
    # Rooms without a record are open to any language.
    open = unique_room()
    message_fixture(user_scope_fixture(), open)
    {:ok, _} = Rooms.update_room(gm, german, %{"language" => "de"})

    {:ok, view, _html} = live(conn, ~p"/rooms")

    assert has_element?(view, "#channel-#{german.name} [data-role='language']", "DE")
    assert has_element?(view, "#channel-#{english.name} [data-role='language']", "EN")
    assert has_element?(view, "#channel-#{open}")
    refute has_element?(view, "#channel-#{open} [data-role='language']")
  end

  test "lists every room with its topic, game masters and people online", %{conn: conn, gm: gm} do
    scene = roleplay_room_fixture(gm, %{"title" => "Sunset Beach", "topic" => "Sun and surf."})
    chat = unique_room()
    message_fixture(user_scope_fixture(), chat)

    {:ok, _visitor, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{scene.name}")
    await_presence(%{room: scene.name})

    {:ok, view, _html} = live(conn, ~p"/rooms")

    row = "#channel-#{scene.name}"
    assert has_element?(view, "#{row} a[href='/rooms/#{scene.name}']", "##{scene.name}")
    assert has_element?(view, "#{row} [data-role='topic']", "Sun and surf.")
    gm_link = "#{row} [data-role='game-masters'] a[href='/u/#{gm.user.username}']"
    assert has_element?(view, "#{gm_link}[title='#{gm.user.username}']")
    refute has_element?(view, "#{row} [data-role='game-masters']", gm.user.username)
    assert has_element?(view, "#{row} [data-role='online']", "1")

    assert has_element?(view, "#channel-#{chat} a[href='/rooms/#{chat}']")
    assert has_element?(view, "#channel-#{chat} [data-role='online']", "0")
    assert has_element?(view, "#channel-lobby")
  end

  test "updates who is online as people come and go", %{conn: conn} do
    room = unique_room()
    message_fixture(user_scope_fixture(), room)
    {:ok, view, _html} = live(conn, ~p"/rooms")
    assert has_element?(view, "#channel-#{room} [data-role='online']", "0")

    {:ok, _visitor, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{room}")
    await_presence(%{room: room})

    assert has_element?(view, "#channel-#{room} [data-role='online']", "1")
  end

  test "filters by name, topic or game master", %{conn: conn, gm: gm} do
    tag = System.unique_integer([:positive])
    beach = roleplay_room_fixture(gm, %{"name" => "beach-#{tag}", "topic" => "Sun and surf."})
    other_gm = user_scope_fixture()
    tavern = roleplay_room_fixture(other_gm, %{"name" => "tavern-#{tag}", "topic" => "Ale."})

    {:ok, view, _html} = live(conn, ~p"/rooms")

    for {query, shown, hidden} <- [
          {"beach-#{tag}", beach, tavern},
          {"SURF", beach, tavern},
          {other_gm.user.username, tavern, beach}
        ] do
      view |> form("#channel-filter", filter: %{query: query}) |> render_change()

      assert has_element?(view, "#channel-#{shown.name}"), "#{query} should show #{shown.name}"
      refute has_element?(view, "#channel-#{hidden.name}"), "#{query} should hide #{hidden.name}"
    end

    view |> form("#channel-filter", filter: %{query: "no-such-room-#{tag}"}) |> render_change()
    assert has_element?(view, "#no-channels")
  end

  test "is linked from the header", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: "/rooms"}}} =
             view |> element("#rooms-nav-link") |> render_click()
  end
end
